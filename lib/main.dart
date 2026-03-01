import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/entities/notification_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/call_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Background isolates may not have Firebase configured; fail gracefully.
  try {
    await Firebase.initializeApp();
  } catch (e) {
    print('⚠️ Background Firebase.initializeApp() failed: $e');
    // We can't proceed with Firebase-dependent logic in background, so return.
    return;
  }

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

/// Show a popup dialog asking user to grant permissions
Future<void> _showPermissionDialog(BuildContext context) async {
  bool permissionsGranted = false;

  while (!permissionsGranted) {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('🎥 Permissions Required'),
          content: const SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text(
                  'ScanCall needs the following permissions to work:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 12),
                Text('📷 Camera - To enable video calls'),
                SizedBox(height: 8),
                Text('🎤 Microphone - For audio and video calls'),
                SizedBox(height: 8),
                Text('🔔 Notifications - For incoming call alerts'),
                SizedBox(height: 16),
                Text(
                  'Please grant these permissions to continue.',
                  style: TextStyle(fontStyle: FontStyle.italic, color: Colors.red),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                print('⚠️ User skipped permissions - app may not work properly');
                permissionsGranted = true; // Allow proceeding anyway
              },
              child: const Text('Skip for Now'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Request permissions
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: const Text(
                'Grant Permissions Now',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );

    // After dialog closes, request permissions if not skipped
    if (!permissionsGranted) {
      final granted = await _requestCameraAndMicrophonePermissions();
      permissionsGranted = granted;

      // If permissions still not granted, show status dialog
      if (!permissionsGranted && context.mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('⚠️ Permissions Status'),
              content: const Text(
                'Some permissions were not granted. Video calls may not work properly. '
                'Please grant permissions in the system settings.',
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    print('User dismissed permission status');
                    permissionsGranted = true; // Continue anyway
                  },
                  child: const Text('Continue'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    openAppSettings(); // Open phone settings
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Open Settings'),
                ),
              ],
            );
          },
        );
      }
    }
  }
}

/// Request camera and microphone permissions required for video calls
/// Returns true if BOTH camera and microphone permissions are granted
Future<bool> _requestCameraAndMicrophonePermissions() async {
  try {
    print('🎥 Requesting camera and microphone permissions...');

    // Request both camera and microphone permissions
    final statuses = await [
      Permission.camera,
      Permission.microphone,
    ].request();

    bool cameraGranted = false;
    bool microphoneGranted = false;

    // Check camera permission
    if (statuses[Permission.camera]?.isGranted ?? false) {
      print('✅ Camera permission GRANTED');
      cameraGranted = true;
    } else if (statuses[Permission.camera]?.isDenied ?? false) {
      print('❌ Camera permission DENIED - video calls may not work');
      print('   Go to Settings > Apps > ScanCall > Permissions and enable Camera');
    } else if (statuses[Permission.camera]?.isPermanentlyDenied ?? false) {
      print('🔒 Camera permission PERMANENTLY DENIED');
      print('   Go to Settings > Apps > ScanCall > Permissions and enable Camera');
    }

    // Check microphone permission
    if (statuses[Permission.microphone]?.isGranted ?? false) {
      print('✅ Microphone permission GRANTED');
      microphoneGranted = true;
    } else if (statuses[Permission.microphone]?.isDenied ?? false) {
      print('❌ Microphone permission DENIED - audio/video calls may not work');
      print('   Go to Settings > Apps > ScanCall > Permissions and enable Microphone');
    } else if (statuses[Permission.microphone]?.isPermanentlyDenied ?? false) {
      print('🔒 Microphone permission PERMANENTLY DENIED');
      print('   Go to Settings > Apps > ScanCall > Permissions and enable Microphone');
    }

    if (cameraGranted && microphoneGranted) {
      print('✅ ALL PERMISSIONS GRANTED - Ready for video calls');
      return true;
    } else {
      print('❌ SOME PERMISSIONS DENIED');
      return false;
    }
  } catch (e) {
    print('❌ Error requesting permissions: $e');
    return false;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();


  // Try to initialize Firebase but don't crash the app if it fails. Many
  // developers forget to add android/app/google-services.json or to apply the
  // Google Services plugin — which causes the error shown in the logs. We'll
  // handle that situation gracefully and continue running the app while
  // disabling FCM-specific flows.
  var firebaseInitialized = false;
  try {
    await Firebase.initializeApp();
    firebaseInitialized = true;

    // Print Firebase config for debugging
    try {
      final options = Firebase.app().options;
      print('Firebase initialized: projectId=${options.projectId}, appId=${options.appId}');
    } catch (e) {
      print('⚠️ Could not read Firebase options after init: $e');
    }
  } catch (e) {
    // The PlatformException thrown by the plugin will be caught here. Provide a
    // clear helpful message so the developer knows how to fix it.
    print('E/flutter (⚠️) Firebase.initializeApp() failed: $e');
    print('  → This usually means android/app/google-services.json is missing,');
    print('    or the Google Services Gradle plugin did not generate the required');
    print('    resources (google_app_id etc.). To fix: add the google-services.json');
    print('    file from your Firebase Console into android/app/ and re-run the build,');
    print('    or initialize Firebase manually with Firebase.initializeApp(options: ...).');
  }

  saveUserData();

  if (firebaseInitialized) {
    // Request notification permission (required for Android 13+)
    await _requestNotificationPermission();

    // Listen for token refreshes
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      print('🔑 FCM Token refreshed: $newToken');
    });

    // Print the current FCM token on initialization
    try {
      final currentToken = await FirebaseMessaging.instance.getToken();
      print('🔑 FCM token on init: $currentToken');
    } catch (e) {
      print('⚠️ Failed to retrieve FCM token on init: $e');
    }

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
  } else {
    print('⚠️ Skipping FCM setup because Firebase failed to initialize.');
    print('   Add android/app/google-services.json or initialize Firebase with FirebaseOptions in Dart.');
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

    // Show permission dialog after a short delay to ensure UI is ready
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _showPermissionDialog(context);
      }
    });
  }

  /// Listen for CallKit accept/decline events
  void _listenCallKitEvents() {
    _callkitSubscription =
        FlutterCallkitIncoming.onEvent.listen((event) async {
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
              print('Unhandled CallKit event: ${event?.event}');
              break;
          }
        });
  }

  Future<void> _onCallAccepted(CallEvent? event) async {
    print('✅ Call ACCEPTED via CallKit');

    // Close native CallKit UI
    await FlutterCallkitIncoming.endAllCalls();

    final body = event?.body ?? {};
    final extra =
        body['extra'] as Map<dynamic, dynamic>? ?? {};

    final callId =
        extra['callId']?.toString() ??
            body['id']?.toString() ??
            '';

    final callerName =
        extra['callerName']?.toString() ??
            body['nameCaller']?.toString() ??
            'Unknown';

    print('callId: $callId');
    print('callerName: $callerName');
  }

  void _onCallDeclined(CallEvent? event) {
    print('❌ Call DECLINED via CallKit');
  }

  @override
  void dispose() {
    _callkitSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WebRTC Receiver App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme:
        ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const CallScreen(),
    );
  }
}

Future<void> saveUserData() async {
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  print('Saving user data to SharedPreferences');
  await prefs.setString('userId', 'u_2208212d-9e4c-46e8-9731-9cc20ec7c8e5');
}
