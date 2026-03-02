# 🚀 Quick Start Guide - ScanCall Mobile App

## Prerequisites
- Flutter SDK installed
- Xcode (for iOS development)
- Android Studio (for Android development)
- Firebase project configured

## Setup Steps

### 1. Install Dependencies
```bash
cd D:\Projects\scancall_mobile_app
flutter pub get
```

### 2. iOS Configuration

#### A. Add Swift Files to Xcode
1. Open `ios/Runner.xcworkspace` in Xcode
2. Right-click on `Runner` folder → Add Files to "Runner"
3. Select both:
   - `ios/Runner/PushKitHandler.swift`
   - `ios/Runner/CallProvider.swift`
4. Check "Copy items if needed" and "Add to targets: Runner"

#### B. Enable Capabilities
1. Select `Runner` project in Xcode
2. Go to `Signing & Capabilities` tab
3. Click `+ Capability` and add:
   - **Push Notifications**
   - **Background Modes** → Check "Voice over IP"

#### C. Info.plist Configuration
Add these permissions to `ios/Runner/Info.plist`:
```xml
<key>NSCameraUsageDescription</key>
<string>We need camera access for video calls</string>
<key>NSMicrophoneUsageDescription</key>
<string>We need microphone access for calls</string>
```

### 3. Android Configuration

#### A. Verify google-services.json
Ensure `android/app/google-services.json` exists and is valid.

#### B. Permissions (already in AndroidManifest.xml)
Verify these permissions exist:
- `CAMERA`
- `RECORD_AUDIO`
- `INTERNET`
- `POST_NOTIFICATIONS` (Android 13+)

### 4. Backend Configuration

**Your backend is already configured!** ✅

The app uses your existing WebSocket server and TURN servers in `lib/services/signaling_service.dart`:

```dart
// WebSocket Server
static const String _signalingServerUrl = 'ws://192.168.1.31:8080/ws';
static const String _roomName = 'test-call';

// TURN/STUN Servers  
final Map<String, dynamic> _iceServers = {
  'iceServers': [
    {'urls': 'stun:13.127.40.12:3478'},
    {
      'urls': [
        'turn:13.127.40.12:3478?transport=udp',
        'turn:13.127.40.12:3478?transport=tcp',
      ],
      'username': 'myuser',
      'credential': 'mypassword',
    }
  ]
};
```

**To change:** Edit these values in `lib/services/signaling_service.dart` if needed.

### 5. Run the App

#### For Android:
```bash
flutter run
```

#### For iOS:
```bash
flutter run -d iPhone
```

## Testing Push Notifications

### Android (FCM):
1. Get FCM token from console logs
2. Send test notification from Firebase Console
3. Or use your backend to send:
```json
{
  "to": "FCM_TOKEN",
  "data": {
    "callerName": "John Doe",
    "callerId": "12345",
    "isVideo": "1"
  }
}
```

### iOS (VoIP Push):
1. Get VoIP token from console logs (look for "🍎 REAL VoIP Token")
2. Configure VoIP certificate in Apple Developer Portal
3. Send VoIP push via your backend
4. Payload format:
```json
{
  "callerName": "John Doe",
  "callerId": "12345",
  "isVideo": "1"
}
```

## Common Issues & Solutions

### Issue: App doesn't compile
**Solution:** Run `flutter clean && flutter pub get`

### Issue: iOS build fails
**Solution:** 
```bash
cd ios
pod deintegrate
pod install
```

### Issue: CallKit doesn't show on iOS
**Solution:** 
- Verify Background Modes → Voice over IP is enabled
- Check VoIP certificate is valid
- Restart Xcode

### Issue: No FCM token on Android
**Solution:**
- Verify `google-services.json` is in `android/app/`
- Check Firebase project configuration
- Grant notification permission in app settings

### Issue: Camera permission denied
**Solution:**
- Go to device Settings → Apps → ScanCall → Permissions
- Enable Camera and Microphone

## Expected Console Logs

When app starts successfully, you should see:
```
✅ Video renderers initialized
🔥 FCM Token for this device → [token]
🍎 REAL VoIP Token from iOS → [token] (iOS only)
```

When receiving a call:
```
📬 FCM data: {callerName: John Doe, ...}
📞 Showing CallKit UI
```

When call is accepted:
```
✅ Call ACCEPTED
🔊 Creating WebRTC peer connection
🎥 Local stream ready
```

## File Structure

```
lib/
├── main.dart                          # NEW: Connects UI with existing SignalingService
├── screens/
│   ├── waiting_screen.dart           # NEW: Home screen
│   ├── incoming_audio_call.dart      # NEW: Audio call incoming UI
│   ├── incoming_call_modern.dart     # NEW: Video call incoming UI
│   ├── audio_call_screen.dart        # NEW: Active audio call
│   ├── video_call.dart               # NEW: Active video call
│   └── call_ended_screen.dart        # NEW: Call summary
└── services/
    ├── signaling_service.dart        # EXISTING: WebSocket + TURN servers + WebRTC
    └── call_popup_events.dart        # NEW: CallKit event handler

ios/Runner/
├── AppDelegate.swift                  # UPDATED: iOS entry point
├── PushKitHandler.swift              # NEW: VoIP push handler
└── CallProvider.swift                # NEW: CallKit provider
```

## Next Steps

1. ✅ Run `flutter pub get`
2. ✅ Configure iOS in Xcode
3. ✅ Update backend URL
4. ✅ Test on physical device (push notifications don't work on simulators)
5. ✅ Send test call from backend
6. ✅ Verify CallKit appears
7. ✅ Test accept/decline flow
8. ✅ Verify WebRTC connection

## Support

For issues, check:
- `MIGRATION_SUMMARY.md` for detailed documentation
- Console logs for error messages
- Firebase Console for FCM configuration
- Apple Developer Portal for VoIP certificates

---

**Happy Calling! 📞**
