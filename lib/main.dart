import 'dart:async';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'screens/call_screen.dart';

/// 🔑 Global navigator key (required to navigate from CallKit event)
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// 🔥 IMPORTANT: Must be top-level & annotated
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await showIncomingCall(message.data);
}

/// 🔔 Show native incoming call UI
Future<void> showIncomingCall(Map<String, dynamic> data) async {
  final params = CallKitParams(
    id: data['callId'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
    nameCaller: data['callerName'] ?? "Unknown Caller",
    appName: 'WebRTC Receiver App',
    type: 0, // 0 = audio, 1 = video
    duration: 30000,
    textAccept: 'Accept',
    textDecline: 'Decline',
    android: const AndroidParams(
      isCustomNotification: true,
      isShowLogo: false,
      ringtonePath: 'system_ringtone_default',
    ),
  );

  await FlutterCallkitIncoming.showCallkitIncoming(params);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Debug: show loaded Firebase apps and options
  try {
    final options = Firebase.app().options;
    print('🔧 Firebase apps: ${Firebase.apps.map((a) => a.name).toList()}');
    print('🔧 FirebaseOptions: appId=${options.appId}, projectId=${options.projectId}, apiKey=${options.apiKey}, messagingSenderId=${options.messagingSenderId}');
  } catch (e) {
    print('⚠️ Could not read Firebase.app().options: $e');
  }

  // Print current FCM registration token so you can copy it for testing (shown in terminal)
  try {
    final String? fcmToken = await FirebaseMessaging.instance.getToken();
    if (fcmToken == null) {
      print('⚠️ FCM token is null. Possible causes:');
      print('   - Device/emulator has no Google Play services (use an emulator image with Google Play).');
      print('   - Firebase Messaging not supported on this platform or configuration issue.');
      if (Platform.isAndroid) {
        print('   - Running on Android. Ensure the emulator image includes Google Play ("Google Play" image) or test on a real device.');
      }
    } else {
      print('🔑 FCM Registration Token: $fcmToken');
    }
  } catch (e, st) {
    print('⚠️ Failed to get FCM token: $e\n$st');
  }

  // Listen for token refreshes (prints new token)
  FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
    print('🔑 FCM Token refreshed: $newToken');
  });

  /// Background message handler
  FirebaseMessaging.onBackgroundMessage(
      _firebaseMessagingBackgroundHandler);

  /// Foreground messages
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    print('🔔 FCM Message Received: ${message.data}');
    if (message.data['type'] == 'incoming_call') {
      showIncomingCall(message.data);
    }
  });

  runApp(const MyApp());
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

    /// 🎧 Listen for CallKit events
    _callkitSubscription =
        FlutterCallkitIncoming.onEvent.listen((event) async {
          switch (event?.event) {
            case Event.actionCallAccept:
              _onCallAccepted(event);
              break;

            case Event.actionCallDecline:
              _onCallDeclined(event);
              break;

            default:
              break;
          }
        });
  }

  void _onCallAccepted(CallEvent? event) async {
    /// Close native UI
    await FlutterCallkitIncoming.endAllCalls();

    /// Navigate to CallScreen
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => const CallScreen(),
      ),
    );

    /// TODO:
    /// Connect WebSocket here
    /// Start WebRTC here
  }

  void _onCallDeclined(CallEvent? event) {
    /// TODO:
    /// Notify backend that call was rejected
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
      title: 'WebRTC Receiver App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const CallScreen(),
    );
  }
}
