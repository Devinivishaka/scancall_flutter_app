import 'dart:async';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/entities/notification_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'screens/call_screen.dart';

/// Global navigator key (required to navigate from CallKit event)
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// IMPORTANT: Must be top-level & annotated for background FCM
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print('📩 Background FCM message received: ${message.data}');

  final type = message.data['type'];
  if (type == 'incoming_call') {
    await _showIncomingCall(message.data);
  } else if (type == 'call_cancel') {
    // Cancel the call UI if the caller hung up
    final callId = message.data['callId'] ?? '';
    if (callId.isNotEmpty) {
      await FlutterCallkitIncoming.endCall(callId);
    } else {
      await FlutterCallkitIncoming.endAllCalls();
    }
  }
}

/// Show native incoming call UI via flutter_callkit_incoming
Future<void> _showIncomingCall(Map<String, dynamic> data) async {
  final callId = data['callId'] ?? DateTime.now().millisecondsSinceEpoch.toString();
  final callerName = data['callerName'] ?? 'Unknown Caller';
  final callerAvatar = data['callerAvatar'] ?? '';

  print('📞 Showing incoming call UI - callId: $callId, caller: $callerName');

  final params = CallKitParams(
    id: callId,
    nameCaller: callerName,
    appName: 'ScanCall',
    avatar: callerAvatar,
    handle: 'Video Call',
    type: 0, // 0 = audio, 1 = video
    duration: 45000, // ring for 45 seconds
    textAccept: 'Accept',
    textDecline: 'Decline',
    missedCallNotification: const NotificationParams(
      showNotification: true,
      isShowCallback: false,
      subtitle: 'Missed Call',
    ),
    extra: <String, dynamic>{
      'callId': callId,
      'callerName': callerName,
    },
    android: const AndroidParams(
      isCustomNotification: true,
      isShowLogo: false,
      ringtonePath: 'system_ringtone_default',
      backgroundColor: '#0955fa',
      actionColor: '#4CAF50',
      isShowFullLockedScreen: true,
      isShowCallID: false,
    ),
    ios: const IOSParams(
      iconName: 'CallKitLogo',
      handleType: 'generic',
      supportsVideo: true,
      maximumCallGroups: 1,
      maximumCallsPerCallGroup: 1,
      audioSessionMode: 'default',
      audioSessionActive: true,
      audioSessionPreferredSampleRate: 44100.0,
      audioSessionPreferredIOBufferDuration: 0.005,
      supportsDTMF: false,
      supportsHolding: false,
      supportsGrouping: false,
      supportsUngrouping: false,
      ringtonePath: 'system_ringtone_default',
    ),
  );

  await FlutterCallkitIncoming.showCallkitIncoming(params);
  print('✅ Incoming call UI shown successfully');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Print Firebase config for debugging
  try {
    final options = Firebase.app().options;
    print('Firebase initialized: projectId=${options.projectId}, appId=${options.appId}');
  } catch (e) {
    print('⚠️ Could not read Firebase options: $e');
  }

  // Request notification permission (required for Android 13+)
  await _requestNotificationPermission();

  // Print FCM token
  await _printFcmToken();

  // Listen for token refreshes
  FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
    print('🔑 FCM Token refreshed: $newToken');
  });

  // Set foreground notification presentation options
  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: false, // Don't show notification banner (we use CallKit)
    badge: false,
    sound: false,
  );

  // Register background message handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Foreground message handler
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    print('🔔 Foreground FCM message: ${message.data}');
    final type = message.data['type'];
    if (type == 'incoming_call') {
      _showIncomingCall(message.data);
    } else if (type == 'call_cancel') {
      final callId = message.data['callId'] ?? '';
      if (callId.isNotEmpty) {
        FlutterCallkitIncoming.endCall(callId);
      } else {
        FlutterCallkitIncoming.endAllCalls();
      }
    }
  });

  // Handle notification tap when app was terminated
  RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    print('📩 App opened from terminated state with FCM: ${initialMessage.data}');
    if (initialMessage.data['type'] == 'incoming_call') {
      await _showIncomingCall(initialMessage.data);
    }
  }

  // Handle notification tap when app is in background
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    print('📩 App opened from background with FCM: ${message.data}');
  });

  // Check for any active calls that may have been triggered while app was starting
  final activeCalls = await FlutterCallkitIncoming.activeCalls();
  if (activeCalls is List && activeCalls.isNotEmpty) {
    print('📞 Found ${activeCalls.length} active call(s) on startup');
  }

  runApp(const MyApp());
}

/// Request notification permission for Android 13+ (API 33)
Future<void> _requestNotificationPermission() async {
  final messaging = FirebaseMessaging.instance;

  final settings = await messaging.requestPermission(
    alert: true,
    announcement: false,
    badge: true,
    carPlay: false,
    criticalAlert: true,
    provisional: false,
    sound: true,
  );

  print('📱 Notification permission: ${settings.authorizationStatus}');

  if (settings.authorizationStatus == AuthorizationStatus.denied) {
    print('⚠️ Notification permission DENIED - FCM push will not work!');
    print('   Go to Settings > Apps > ScanCall > Notifications and enable them.');
  }
}

/// Print FCM registration token for testing
Future<void> _printFcmToken() async {
  try {
    final String? fcmToken = await FirebaseMessaging.instance.getToken();
    if (fcmToken == null) {
      print('⚠️ FCM token is null. Possible causes:');
      print('   - No Google Play services on device/emulator');
      if (Platform.isAndroid) {
        print('   - Use emulator with Google Play image or a real device');
      }
    } else {
      print('');
      print('══════════════════════════════════════════════════════');
      print('🔑 FCM TOKEN (copy this for testing):');
      print(fcmToken);
      print('══════════════════════════════════════════════════════');
      print('');
    }
  } catch (e, st) {
    print('⚠️ Failed to get FCM token: $e\n$st');
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  StreamSubscription? _callkitSubscription;

  @override
  void initState() {
    super.initState();
    _listenCallKitEvents();
  }

  /// Listen for CallKit accept/decline events
  void _listenCallKitEvents() {
    _callkitSubscription = FlutterCallkitIncoming.onEvent.listen((event) async {
      print('📱 CallKit event: ${event?.event}');

      switch (event?.event) {
        case Event.actionCallAccept:
          await _onCallAccepted(event);
          break;

        case Event.actionCallDecline:
          _onCallDeclined(event);
          break;

        case Event.actionCallTimeout:
          print('⏰ Call timed out (not answered)');
          await FlutterCallkitIncoming.endAllCalls();
          break;

        case Event.actionCallEnded:
          print('📵 Call ended via CallKit');
          break;

        default:
          print('   Unhandled CallKit event: ${event?.event}');
          break;
      }
    });
  }

  Future<void> _onCallAccepted(CallEvent? event) async {
    print('✅ Call ACCEPTED via CallKit');

    // End the CallKit UI
    await FlutterCallkitIncoming.endAllCalls();

    // Extract call data from the event
    final body = event?.body ?? {};
    final extra = body['extra'] as Map<dynamic, dynamic>? ?? {};
    final callId = extra['callId']?.toString() ?? body['id']?.toString() ?? '';
    final callerName = extra['callerName']?.toString() ?? body['nameCaller']?.toString() ?? 'Unknown';

    print('   callId: $callId, callerName: $callerName');

    // Navigate to CallScreen with call data
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => CallScreen(
          callId: callId,
          callerName: callerName,
        ),
      ),
    );
  }

  void _onCallDeclined(CallEvent? event) {
    print('❌ Call DECLINED via CallKit');
    // Optionally notify backend
  }

  @override
  void dispose() {
    _callkitSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'ScanCall',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

/// Simple home screen showing app status and FCM token
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _fcmToken = 'Loading...';
  String _status = 'Waiting for incoming calls...';

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  Future<void> _loadToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      setState(() {
        _fcmToken = token ?? 'Token unavailable';
      });
    } catch (e) {
      setState(() {
        _fcmToken = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ScanCall'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 40),
            const Icon(
              Icons.phone_in_talk,
              size: 80,
              color: Colors.blue,
            ),
            const SizedBox(height: 24),
            Text(
              _status,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'The app will show an incoming call screen\nwhen an FCM push notification is received.',
              style: TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'FCM Token:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    _fcmToken,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade700,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loadToken,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh Token'),
            ),
            const Spacer(),
            // Test button to simulate incoming call
            ElevatedButton.icon(
              onPressed: () async {
                await _showIncomingCall({
                  'callId': 'test_${DateTime.now().millisecondsSinceEpoch}',
                  'callerName': 'Test Caller',
                  'type': 'incoming_call',
                });
                setState(() {
                  _status = 'Test call triggered!';
                });
                Future.delayed(const Duration(seconds: 3), () {
                  if (mounted) {
                    setState(() {
                      _status = 'Waiting for incoming calls...';
                    });
                  }
                });
              },
              icon: const Icon(Icons.phone),
              label: const Text('Test Incoming Call (Local)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
