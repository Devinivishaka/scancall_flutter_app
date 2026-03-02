import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'screens/waiting_screen.dart';
import 'screens/incoming_audio_call.dart';
import 'screens/incoming_call_modern.dart';
import 'screens/audio_call_screen.dart';
import 'screens/video_call.dart';
import 'screens/call_ended_screen.dart';
import 'services/signaling_service.dart'; // Use existing service with WebSocket, TURN servers
import 'services/call_popup_events.dart';

/// Background FCM handler
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await _handleIncomingCallPush(message.data);
}

/// Show system CallKit UI (iOS + Android) from push data
Future<void> _handleIncomingCallPush(Map<String, dynamic> data) async {
  debugPrint("📬 FCM data: $data");

  final id = const Uuid().v4();
  final callerName = data['callerName'] ?? 'Unknown';
  final callerId = data['callerId'] ?? 'id';
  final isVideo =
      data['isVideo'] == "1" || data['type']?.toString() == "video";

  final params = CallKitParams(
    id: id,
    nameCaller: callerName,
    appName: 'ScanCall',
    avatar: 'https://i.pravatar.cc/300',
    handle: callerId,
    type: isVideo ? 1 : 0,
    duration: 30000,
    textAccept: 'Accept',
    textDecline: 'Decline',
    extra: data,
  );

  await FlutterCallkitIncoming.showCallkitIncoming(params);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  await FirebaseMessaging.instance.requestPermission();

  runApp(const MyApp());
}


class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // Use existing SignalingService with WebSocket server, TURN servers, backend endpoints
  final SignalingService _signalingService = SignalingService();

  // Used to show dialogs (e.g. incoming call-type change) regardless of which screen is active
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  CallState _callState = CallState.idle;
  String _statusText = 'Initializing...';
  bool _showIncomingCallUI = false;
  String _callType = 'video'; // 'audio' or 'video'

  // Video renderers
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  @override
  void initState() {
    super.initState();
    _initializeApp();
    _setupCallKitListeners();
  }

  Future<void> _initializeApp() async {
    // Initialize renderers
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    print('✅ Video renderers initialized');

    // Initialize signaling service (connects to WebSocket server with TURN servers)
    await _signalingService.initialize();

    // Listen to call state changes
    _signalingService.onCallStateChanged.listen((state) {
      setState(() {
        _callState = state;
        _statusText = _getStatusText(state);

        if (state == CallState.waiting) {
          _showIncomingCallUI = false;
          _localRenderer.srcObject = null;
          _remoteRenderer.srcObject = null;
        }

        if (state == CallState.connecting || state == CallState.connected) {
          _showIncomingCallUI = false;
        }
      });
    });

    // Listen for incoming calls (from WebSocket server)
    _signalingService.onIncomingCall.listen((_) {
      setState(() {
        _showIncomingCallUI = true;
        _callState = CallState.incoming;
        _callType = _signalingService.callType;
        _statusText = '📞 Incoming Call!';
      });
      print('🔔 INCOMING CALL - Call type: $_callType');
    });

    // Listen to remote stream
    _signalingService.onRemoteStream.listen((stream) {
      print('🎥 Remote stream received');
      setState(() {
        _remoteRenderer.srcObject = stream;
      });
    });

    // Listen to local stream
    _signalingService.onLocalStream.listen((stream) {
      print('📹 Local stream received');
      setState(() {
        _localRenderer.srcObject = stream;
      });
    });

    // Listen to call type changes (confirmed after renegotiation completes)
    _signalingService.onCallTypeChanged.listen((newType) {
      setState(() {
        _callType = newType;
      });
      print('🔄 Call type changed → $newType');
    });

    // Listen to call-type-change REQUESTS from the remote (web) side.
    _signalingService.onChangeTypeRequest.listen((requestedType) {
      print('🔄 Web requesting call type change → $requestedType');
      if (requestedType == 'audio') {
        // Video → Audio: auto-accept immediately, no permission needed.
        print('🔇 Auto-accepting video→audio switch');
        _signalingService.acceptChangeCallType(requestedType);
      } else {
        // Audio → Video: show a permission dialog on the current screen.
        final ctx = _navigatorKey.currentContext;
        if (ctx != null && mounted) {
          showDialog<void>(
            context: ctx,
            barrierDismissible: false,
            builder: (dialogCtx) => AlertDialog(
              title: const Text('Switch to Video Call?'),
              content: const Text(
                'The web caller wants to switch to a video call. Allow?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Decline'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(dialogCtx).pop();
                    _signalingService.acceptChangeCallType(requestedType);
                  },
                  child: const Text('Accept'),
                ),
              ],
            ),
          );
        }
      }
    });

    // Register FCM token with backend so the server can send push notifications.
    // This runs in background — a failure does not block the app.
    try {
      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken != null) {
        print('📲 FCM token: $fcmToken');
        await _signalingService.registerFcmToken(fcmToken);
      } else {
        print('⚠️ Could not retrieve FCM token');
      }
    } catch (e) {
      print('⚠️ FCM token registration failed: $e');
    }

    // Connect to signaling server and wait for calls
    await _signalingService.connectAndWaitForCalls();

    print('✅ App initialized - Ready to receive calls');
  }

  void _setupCallKitListeners() {
    // Listen to CallKit events (Accept/Decline from system UI)
    CallPopupEvents.listen((action, data) async {
      print('📞 CallKit action: $action');

      switch (action) {
        case 'ACTION_CALL_ACCEPT':
          await _acceptCall();
          break;

        case 'ACTION_CALL_DECLINE':
          await _rejectCall();
          break;

        case 'ACTION_CALL_ENDED':
          await _endCall();
          break;
      }
    });

    // Listen for FCM messages (for push notifications)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('🔔 Foreground FCM message: ${message.data}');
      _handleIncomingCallPush(message.data);
    });
  }

  Future<void> _acceptCall() async {
    try {
      print('✅ User accepted the call');

      // Check permissions
      Map<Permission, PermissionStatus> statuses = await [
        Permission.camera,
        Permission.microphone,
      ].request();

      if (statuses[Permission.camera] != PermissionStatus.granted ||
          statuses[Permission.microphone] != PermissionStatus.granted) {
        print('❌ Permissions denied');
        return;
      }

      setState(() {
        _showIncomingCallUI = false;
        _statusText = 'Accepting call...';
      });

      // Use existing signaling service's accept method (handles WebRTC setup)
      await _signalingService.acceptCall();
    } catch (e) {
      print('❌ Error accepting call: $e');
    }
  }

  Future<void> _rejectCall() async {
    try {
      print('❌ User rejected the call');
      setState(() {
        _showIncomingCallUI = false;
        _statusText = 'Call rejected';
      });

      await _signalingService.rejectCall();
    } catch (e) {
      print('❌ Error rejecting call: $e');
    }
  }

  Future<void> _endCall() async {
    try {
      print('📵 Ending call');
      await _signalingService.endCall();

      setState(() {
        _showIncomingCallUI = false;
        _statusText = 'Call ended';
        _callState = CallState.waiting;
      });
    } catch (e) {
      print('❌ Error ending call: $e');
    }
  }

  String _getStatusText(CallState state) {
    switch (state) {
      case CallState.idle:
        return 'Ready';
      case CallState.waiting:
        return 'Waiting for call...';
      case CallState.incoming:
        return '📞 Incoming Call!';
      case CallState.connecting:
        return 'Connecting...';
      case CallState.connected:
        return '✅ Call connected';
      case CallState.ended:
        return 'Call ended';
      case CallState.error:
        return '❌ Error occurred';
    }
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _signalingService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget screen;

    // Show incoming call UI
    if (_showIncomingCallUI) {
      screen = _callType == 'audio'
          ? IncomingAudioCallScreen(
              name: "Web Caller",
              avatar: "https://randomuser.me/api/portraits/men/32.jpg",
              onAccept: _acceptCall,
              onReject: _rejectCall,
            )
          : IncomingCallModern(
              onAccept: _acceptCall,
              onReject: _rejectCall,
            );
    }
    // Show active call UI
    else if (_callState == CallState.connected || _callState == CallState.connecting) {
      screen = _callType == 'audio'
          ? AudioCallScreen(
              name: "Web Caller",
              avatar: "https://randomuser.me/api/portraits/men/32.jpg",
              local: _localRenderer,
              remote: _remoteRenderer,
              onEnd: _endCall,
              onChangeType: () =>
                  _signalingService.requestChangeCallType('video'),
            )
          : VideoCallScreen(
              local: _localRenderer,
              remote: _remoteRenderer,
              onEnd: _endCall,
              callType: _callType,
              onChangeType: () => _signalingService.requestChangeCallType(
                _callType == 'video' ? 'audio' : 'video',
              ),
            );
    }
    // Show waiting screen
    else {
      screen = const WaitingScreen();
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ScanCall',
      navigatorKey: _navigatorKey,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: screen,
    );
  }
}

