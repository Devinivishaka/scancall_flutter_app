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
import 'firebase_options.dart';
import 'screens/call_screen.dart';

/// 🔑 Global navigator key (required to navigate from CallKit event)
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// 🔥 IMPORTANT: Must be top-level & annotated
/// This handler runs in a separate isolate when the app is terminated or in background
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize Firebase in this isolate
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  print('═══════════════════════════════════════════════════════════');
  print('🔁 [BACKGROUND HANDLER] FCM Message Received');
  print('═══════════════════════════════════════════════════════════');
  print('   Message ID: ${message.messageId}');
  print('   Sent Time: ${message.sentTime}');
  print('   Data: ${message.data}');

  if (message.notification != null) {
    print('   Notification Title: ${message.notification!.title}');
    print('   Notification Body: ${message.notification!.body}');
  }
  print('═══════════════════════════════════════════════════════════');

  // Handle incoming call
  if (message.data.isNotEmpty && message.data['type'] == 'incoming_call') {
    print('🔔 Showing incoming call UI from background handler...');
    await _showIncomingCallUI(message.data);
  } else {
    print('⚠️ Message type is not "incoming_call" or data is empty');
  }
}

/// 🔔 Show native incoming call UI with full-screen intent
Future<void> _showIncomingCallUI(Map<String, dynamic> data) async {
  try {
    final callId = data['callId']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();
    final callerName = data['callerName']?.toString() ?? data['caller_name']?.toString() ?? "Unknown Caller";
    final callerId = data['callerId']?.toString() ?? data['caller_id']?.toString() ?? "";
    final isVideo = data['isVideo'] == true || data['is_video'] == true || data['type'] == 'video_call';

    print('📞 Creating call with:');
    print('   Call ID: $callId');
    print('   Caller: $callerName');
    print('   Caller ID: $callerId');
    print('   Is Video: $isVideo');

    final params = CallKitParams(
      id: callId,
      nameCaller: callerName,
      appName: 'ScanCall',
      avatar: data['avatar']?.toString(),
      handle: callerId,
      type: isVideo ? 1 : 0, // 0 = audio, 1 = video
      duration: 45000, // 45 seconds timeout
      textAccept: 'Accept',
      textDecline: 'Decline',
      extra: data, // Store extra data for later use
      headers: <String, dynamic>{'platform': Platform.operatingSystem},
      android: AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0955fa',
        backgroundUrl: '',
        actionColor: '#4CAF50',
        textColor: '#ffffff',
        incomingCallNotificationChannelName: "Incoming Call",
        missedCallNotificationChannelName: "Missed Call",
        isShowCallID: false,
        isShowFullLockedScreen: true,
      ),
      ios: IOSParams(
        iconName: 'CallKitLogo',
        handleType: 'generic',
        supportsVideo: true,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'default',
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 44100.0,
        audioSessionPreferredIOBufferDuration: 0.005,
        supportsDTMF: true,
        supportsHolding: true,
        supportsGrouping: false,
        supportsUngrouping: false,
        ringtonePath: 'system_ringtone_default',
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(params);
    print('✅ Incoming call UI displayed successfully');
  } catch (e, stackTrace) {
    print('❌ Error showing incoming call UI: $e');
    print('Stack trace: $stackTrace');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  print('═══════════════════════════════════════════════════════════');
  print('🚀 APP STARTING - Initializing Firebase');
  print('═══════════════════════════════════════════════════════════');

  try {
    // Initialize Firebase with platform-specific options
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('✅ Firebase initialized successfully');

    // Log Firebase configuration
    final options = Firebase.app().options;
    print('📋 Firebase Configuration:');
    print('   App ID: ${options.appId}');
    print('   Project ID: ${options.projectId}');
    print('   Messaging Sender ID: ${options.messagingSenderId}');
    print('   Platform: ${Platform.operatingSystem}');
  } catch (e, stackTrace) {
    print('❌ Firebase initialization failed: $e');
    print('Stack trace: $stackTrace');
  }

  // Register background message handler BEFORE requesting permissions
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  print('✅ Background message handler registered');

  // Request notification permissions
  await _requestNotificationPermissions();

  // Get and display FCM token
  await _getFCMToken();

  // Listen for token refresh
  FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
    print('═══════════════════════════════════════════════════════════');
    print('🔄 FCM Token Refreshed');
    print('═══════════════════════════════════════════════════════════');
    print('New Token: $newToken');
    print('═══════════════════════════════════════════════════════════');

    // TODO: Send this token to your backend server
  }, onError: (error) {
    print('❌ Error listening to token refresh: $error');
  });

  // Setup foreground message handler
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    print('═══════════════════════════════════════════════════════════');
    print('🔔 [FOREGROUND] FCM Message Received');
    print('═══════════════════════════════════════════════════════════');
    print('   Message ID: ${message.messageId}');
    print('   Sent Time: ${message.sentTime}');
    print('   Data: ${message.data}');

    if (message.notification != null) {
      print('   Notification Title: ${message.notification!.title}');
      print('   Notification Body: ${message.notification!.body}');
    }
    print('═══════════════════════════════════════════════════════════');

    // Show incoming call UI when app is in foreground
    if (message.data.isNotEmpty && message.data['type'] == 'incoming_call') {
      print('🔔 Showing incoming call UI (foreground)...');
      _showIncomingCallUI(message.data);
    } else {
      print('⚠️ Message type is not "incoming_call" or data is empty');
    }
  }, onError: (error) {
    print('❌ Error in onMessage listener: $error');
  });

  // Handle notification opened app (from background)
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    print('═══════════════════════════════════════════════════════════');
    print('📲 [OPENED APP] User tapped notification');
    print('═══════════════════════════════════════════════════════════');
    print('   Message ID: ${message.messageId}');
    print('   Data: ${message.data}');
    print('═══════════════════════════════════════════════════════════');

    // Handle the action when user taps notification
    if (message.data['type'] == 'incoming_call') {
      _showIncomingCallUI(message.data);
    }
  }, onError: (error) {
    print('❌ Error in onMessageOpenedApp listener: $error');
  });

  // Check if app was opened from a terminated state via notification
  try {
    final RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      print('═══════════════════════════════════════════════════════════');
      print('🚀 [INITIAL MESSAGE] App opened from terminated state');
      print('═══════════════════════════════════════════════════════════');
      print('   Message ID: ${initialMessage.messageId}');
      print('   Data: ${initialMessage.data}');
      print('═══════════════════════════════════════════════════════════');

      if (initialMessage.data['type'] == 'incoming_call') {
        // Delay slightly to ensure UI is ready
        Future.delayed(const Duration(milliseconds: 500), () {
          _showIncomingCallUI(initialMessage.data);
        });
      }
    }
  } catch (e, stackTrace) {
    print('❌ Error checking initial message: $e');
    print('Stack trace: $stackTrace');
  }

  print('═══════════════════════════════════════════════════════════');
  print('✅ All FCM handlers configured successfully');
  print('═══════════════════════════════════════════════════════════');

  runApp(const MyApp());
}

/// Request notification permissions
Future<void> _requestNotificationPermissions() async {
  try {
    print('🔐 Requesting notification permissions...');

    final NotificationSettings settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    print('🔐 Notification permission status: ${settings.authorizationStatus}');

    switch (settings.authorizationStatus) {
      case AuthorizationStatus.authorized:
        print('✅ User granted permission');
        break;
      case AuthorizationStatus.provisional:
        print('⚠️ User granted provisional permission');
        break;
      case AuthorizationStatus.denied:
        print('❌ User denied permission');
        break;
      case AuthorizationStatus.notDetermined:
        print('⚠️ User has not yet chosen permission');
        break;
    }

    // For Android, also check alert, sound, and badge
    if (Platform.isAndroid) {
      print('🔔 Android notification settings:');
      print('   Alert: ${settings.alert}');
      print('   Sound: ${settings.sound}');
      print('   Badge: ${settings.badge}');
    }
  } catch (e, stackTrace) {
    print('❌ Error requesting notification permission: $e');
    print('Stack trace: $stackTrace');
  }
}

/// Get and display FCM token
Future<void> _getFCMToken() async {
  try {
    print('🔑 Fetching FCM token...');

    final String? fcmToken = await FirebaseMessaging.instance.getToken();

    if (fcmToken == null) {
      print('═══════════════════════════════════════════════════════════');
      print('❌ FCM TOKEN IS NULL');
      print('═══════════════════════════════════════════════════════════');
      print('Possible causes:');
      print('1. Device/emulator lacks Google Play services');
      print('2. Use an emulator with "Google Play" image');
      print('3. Test on a physical device with Google Play');
      print('4. Check google-services.json configuration');
      print('5. Ensure app package name matches Firebase console');

      if (Platform.isAndroid) {
        print('\n📱 Android-specific checks:');
        print('   - Use AVD with Google Play Store');
        print('   - Ensure device has active internet connection');
        print('   - Check if Google Play services is up to date');
      }
      print('═══════════════════════════════════════════════════════════');
    } else {
      print('═══════════════════════════════════════════════════════════');
      print('✅ FCM TOKEN RETRIEVED');
      print('═══════════════════════════════════════════════════════════');
      print('Token: $fcmToken');
      print('═══════════════════════════════════════════════════════════');
      print('📋 COPY THIS TOKEN TO TEST SENDING NOTIFICATIONS');
      print('═══════════════════════════════════════════════════════════');

      // TODO: Send this token to your backend server
      // Example: await sendTokenToBackend(fcmToken);
    }
  } catch (e, stackTrace) {
    print('═══════════════════════════════════════════════════════════');
    print('❌ FAILED TO GET FCM TOKEN');
    print('═══════════════════════════════════════════════════════════');
    print('Error: $e');
    print('Stack trace: $stackTrace');
    print('═══════════════════════════════════════════════════════════');
  }
}


class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  StreamSubscription<CallEvent?>? _callkitSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    print('═══════════════════════════════════════════════════════════');
    print('🎧 Setting up CallKit event listener');
    print('═══════════════════════════════════════════════════════════');

    /// 🎧 Listen for CallKit events
    _callkitSubscription = FlutterCallkitIncoming.onEvent.listen(
      (CallEvent? event) async {
        if (event == null) {
          print('⚠️ Received null CallKit event');
          return;
        }

        print('═══════════════════════════════════════════════════════════');
        print('🔔 CallKit Event: ${event.event}');
        print('═══════════════════════════════════════════════════════════');
        print('   Call ID: ${event.body['id']}');
        print('   Caller Name: ${event.body['nameCaller']}');
        print('   Extra Data: ${event.body['extra']}');
        print('═══════════════════════════════════════════════════════════');

        switch (event.event) {
          case Event.actionCallAccept:
            await _onCallAccepted(event);
            break;

          case Event.actionCallDecline:
            await _onCallDeclined(event);
            break;

          case Event.actionCallEnded:
            await _onCallEnded(event);
            break;

          case Event.actionCallTimeout:
            await _onCallTimeout(event);
            break;

          default:
            print('⚠️ Unhandled CallKit event: ${event.event}');
            break;
        }
      },
      onError: (error) {
        print('❌ Error in CallKit event listener: $error');
      },
    );

    print('✅ CallKit event listener configured');
  }

  /// Handle call accepted
  Future<void> _onCallAccepted(CallEvent? event) async {
    print('═══════════════════════════════════════════════════════════');
    print('✅ Call Accepted');
    print('═══════════════════════════════════════════════════════════');

    try {
      // Close native incoming call UI
      await FlutterCallkitIncoming.endAllCalls();
      print('✅ Native call UI closed');

      // Navigate to CallScreen
      if (navigatorKey.currentState != null) {
        navigatorKey.currentState!.push(
          MaterialPageRoute(
            builder: (_) => const CallScreen(),
          ),
        );
        print('✅ Navigated to CallScreen');
      } else {
        print('❌ Navigator key state is null');
      }

      /// TODO: Connect to signaling server and establish WebRTC connection
      /// Extract call data from event.body['extra'] and pass to CallScreen
      final callData = event?.body['extra'] as Map<String, dynamic>?;
      if (callData != null) {
        print('📞 Call data available: $callData');
        // You can pass this data to CallScreen via constructor or a service
      }
    } catch (e, stackTrace) {
      print('❌ Error handling accepted call: $e');
      print('Stack trace: $stackTrace');
    }
  }

  /// Handle call declined
  Future<void> _onCallDeclined(CallEvent? event) async {
    print('═══════════════════════════════════════════════════════════');
    print('❌ Call Declined');
    print('═══════════════════════════════════════════════════════════');

    try {
      // End all calls
      await FlutterCallkitIncoming.endAllCalls();

      /// TODO: Notify backend that call was rejected
      final callData = event?.body['extra'] as Map<String, dynamic>?;
      if (callData != null) {
        print('📞 Declining call with data: $callData');
        // Send rejection notification to backend
        // Example: await notifyBackendCallRejected(callData['callId']);
      }
    } catch (e, stackTrace) {
      print('❌ Error handling declined call: $e');
      print('Stack trace: $stackTrace');
    }
  }

  /// Handle call ended
  Future<void> _onCallEnded(CallEvent? event) async {
    print('═══════════════════════════════════════════════════════════');
    print('📴 Call Ended');
    print('═══════════════════════════════════════════════════════════');

    try {
      await FlutterCallkitIncoming.endAllCalls();

      /// TODO: Clean up WebRTC connection and notify backend
    } catch (e, stackTrace) {
      print('❌ Error handling ended call: $e');
      print('Stack trace: $stackTrace');
    }
  }

  /// Handle call timeout
  Future<void> _onCallTimeout(CallEvent? event) async {
    print('═══════════════════════════════════════════════════════════');
    print('⏱️ Call Timeout (Missed Call)');
    print('═══════════════════════════════════════════════════════════');

    try {
      await FlutterCallkitIncoming.endAllCalls();

      /// TODO: Log missed call and notify backend
      final callData = event?.body['extra'] as Map<String, dynamic>?;
      if (callData != null) {
        print('📞 Missed call data: $callData');
        // Example: await notifyBackendMissedCall(callData['callId']);
      }
    } catch (e, stackTrace) {
      print('❌ Error handling timeout call: $e');
      print('Stack trace: $stackTrace');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    print('📱 App lifecycle state changed: $state');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _callkitSubscription?.cancel();
    print('🔇 CallKit event listener cancelled');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'ScanCall Mobile App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const CallScreen(),
    );
  }
}
