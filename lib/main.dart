import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  String _status = 'Ready to Receive Calls';
  bool _showToken = false;

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

  void _copyToken() {
    Clipboard.setData(ClipboardData(text: _fcmToken));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('FCM Token copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showNotificationHelp() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enable Notifications'),
        content: const Text(
          'To receive incoming calls, please enable notifications:\n\n'
          '1. Open Settings\n'
          '2. Go to Apps → ScanCall\n'
          '3. Enable Notifications\n'
          '4. Allow full-screen alerts',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('ScanCall'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Main status card
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32.0,
                        vertical: 48.0,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Icon with animated gradient background
                          Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [
                                  Colors.blue.shade400,
                                  Colors.blue.shade600,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.blue.withValues(alpha: 0.3),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.phone_in_talk_rounded,
                              size: 60,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 32),

                          // Status text
                          Text(
                            _status,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),

                          // Description
                          Text(
                            'Your app is ready to receive incoming calls via push notifications',
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.grey[600],
                              height: 1.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 32),

                          // Status indicator
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.green.shade200,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.green.withValues(alpha: 0.5),
                                        blurRadius: 4,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Text(
                                  'Online & Active',
                                  style: TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Notification settings button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _showNotificationHelp,
                      icon: const Icon(Icons.notifications_active),
                      label: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16.0),
                        child: Text(
                          'Notification Settings',
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // FCM Token section (expandable)
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        InkWell(
                          onTap: () {
                            setState(() {
                              _showToken = !_showToken;
                            });
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20.0,
                              vertical: 16.0,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.vpn_key,
                                  color: Colors.grey[600],
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'FCM Token',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey[800],
                                    ),
                                  ),
                                ),
                                Icon(
                                  _showToken
                                      ? Icons.expand_less
                                      : Icons.expand_more,
                                  color: Colors.grey[600],
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_showToken)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[100],
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.grey[300]!,
                                    ),
                                  ),
                                  child: SelectableText(
                                    _fcmToken,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontFamily: 'monospace',
                                      color: Colors.grey[800],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: _fcmToken != 'Loading...'
                                        ? _copyToken
                                        : null,
                                    icon: const Icon(Icons.copy, size: 18),
                                    label: const Text('Copy Token'),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Info text
                  Text(
                    'Make sure notifications are enabled to receive incoming calls',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[500],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
