# 📱 WebRTC Mobile Receiver App

A simple Flutter mobile application that **RECEIVES** one-to-one WebRTC audio calls from a web client.

## 🎯 Features

- ✅ **Receiver Mode** - Mobile app waits for incoming calls
- ✅ **Automatic Answering** - Answers calls automatically (no user interaction)
- ✅ Audio-only WebRTC calls (video-ready structure)
- ✅ One-to-one call between web (caller) and mobile (receiver)
- ✅ WebSocket-based signaling
- ✅ TURN/STUN server support
- ✅ Simple, clean UI with call status indicators
- ✅ Android support (iOS-ready structure)

## 🛠️ Tech Stack

- **Flutter** (SDK ^3.10.8)
- **flutter_webrtc** (^0.12.4+) - WebRTC implementation
- **web_socket_channel** (^3.0.1) - WebSocket signaling

## 🔄 Call Flow (Receiver Mode)

```
┌─────────────┐                 ┌──────────┐                 ┌────────────┐
│  Web Caller │                 │ Signaling│                 │ Mobile App │
│             │                 │  Server  │                 │ (RECEIVER) │
└─────────────┘                 └──────────┘                 └────────────┘
      │                               │                            │
      │                               │  1. App opens              │
      │                               │  2. Connect & Wait         │
      │                               │◄───────────────────────────│
      │                               │  3. Join room "test-call"  │
      │                               │◄───────────────────────────│
      │                               │                            │
      │  4. User clicks "Call"        │                            │
      │  5. Get microphone            │                            │
      │  6. Create offer              │                            │
      │─────────────────────────────>│                            │
      │                               │  7. Forward offer          │
      │                               │──────────────────────────>│
      │                               │  📞 INCOMING CALL!         │
      │                               │                            │
      │                               │  8. Auto-answer            │
      │                               │  9. Create answer          │
      │                               │ 10. Send answer            │
      │ 11. Receive answer            │◄───────────────────────────│
      │◄─────────────────────────────│                            │
      │                               │                            │
      │ 12. Exchange ICE candidates   │                            │
      │◄────────────────────────────►│◄──────────────────────────│
      │                               │                            │
      │ 13. 🔊 Audio Connection Established 🔊                    │
      │──────────────────────────────────────────────────────────>│
      │           (Web talks → Mobile hears)                       │
```

## 📋 Prerequisites

Before running the app, ensure you have:

1. **Flutter SDK** installed ([installation guide](https://docs.flutter.dev/get-started/install))
2. **Android Studio** or **VS Code** with Flutter extensions
3. **Android device** or **emulator** (API level 21+)
4. **Node.js** (for running the signaling server)

## 🚀 Quick Start

### Step 1: Install Dependencies

```powershell
# Install Flutter dependencies
flutter pub get

# Install signaling server dependencies
cd signaling_server
npm install
cd ..
```

### Step 2: Configure the Mobile App

Open `lib/services/signaling_service.dart` and update:

```dart
// Line 12: Update with your server IP
static const String _signalingServerUrl = 'ws://YOUR_SERVER_IP:8080';

// Lines 24-29: Update TURN credentials (optional for local testing)
'username': 'YOUR_TURN_USERNAME',
'credential': 'YOUR_TURN_PASSWORD',
```

**Example for local testing:**
```dart
static const String _signalingServerUrl = 'ws://192.168.1.100:8080';
```

> **Note:** Use your computer's local IP address (not localhost) when testing on a real device.

### Step 3: Start the Signaling Server

```powershell
cd signaling_server
npm start
```

You should see:
```
WebSocket signaling server running on port 8080
Waiting for connections...
```

### Step 4: Run the Mobile App (Receiver)

```powershell
# Run on connected device
flutter run

# Or build and install APK
flutter build apk
flutter install
```

**Expected behavior:**
- App opens
- Shows "Waiting for call..."
- Status: "WAITING"
- Mobile is now ready to receive calls

### Step 5: Open the Web Caller

1. Open `web_client/caller.html` in a web browser
2. Update the server URL if needed (line 162):
   ```javascript
   const SIGNALING_SERVER = 'ws://localhost:8080';
   ```
3. Click the **"📞 Call Mobile App"** button
4. Grant microphone permission when prompted

### Step 6: Observe the Call

**On Mobile (Receiver):**
1. You'll see "📞 Incoming Call!"
2. App automatically answers (no user interaction)
3. Status changes to "CONNECTING" → "CONNECTED"
4. You'll hear audio from the web caller
5. Tap "End Call" to hang up

**On Web (Caller):**
1. Shows "Waiting for mobile app to answer..."
2. Mobile auto-answers
3. Status shows "Call connected!"
4. Speak into your microphone
5. Mobile app will hear you

## 📁 Project Structure

```
scancall_mobile_app/
├── lib/
│   ├── main.dart                    # App entry point (Receiver)
│   ├── screens/
│   │   └── call_screen.dart         # Receiver UI
│   └── services/
│       └── signaling_service.dart   # WebRTC receiver logic
├── signaling_server/
│   ├── server.js                    # WebSocket signaling server
│   └── package.json                 # Server dependencies
├── web_client/
│   ├── caller.html                  # NEW: Web caller (initiates calls)
│   └── index.html                   # OLD: Web receiver (not used now)
├── android/
│   └── app/src/main/
│       └── AndroidManifest.xml      # Android permissions
└── pubspec.yaml                     # Flutter dependencies
```

## 🎯 Key Differences: Receiver vs Caller Mode

| Aspect | **Receiver Mode (This App)** | Caller Mode (Old) |
|--------|------------------------------|-------------------|
| Initiates Call | ❌ No - Waits for calls | ✅ Yes - Starts calls |
| User Interaction | Minimal - Auto-answers | Required - Tap to call |
| Microphone | Not needed initially | Needed to start call |
| WebRTC Flow | Receives offer → Creates answer | Creates offer → Waits for answer |
| Use Case | Always-on receiver, incoming calls | On-demand calling |

## 🔧 Configuration

### ICE Servers (STUN/TURN)

Current configuration in `signaling_service.dart`:

```dart
final Map<String, dynamic> _iceServers = {
  'iceServers': [
    {'urls': 'stun:13.127.40.12:3478'},
    {
      'urls': [
        'turn:13.127.40.12:3478?transport=udp',
        'turn:13.127.40.12:3478?transport=tcp',
      ],
      'username': 'YOUR_TURN_USERNAME',
      'credential': 'YOUR_TURN_PASSWORD',
    }
  ]
};
```

**For local testing (same WiFi):**
- STUN server alone is sufficient
- No need for TURN credentials

**For production (different networks):**
- TURN server required
- Update username and credential

## 🧪 Testing Scenarios

### Scenario 1: Same Computer (Easiest)

**Signaling Server:** `localhost:8080`  
**Mobile App:** `ws://10.0.2.2:8080` (if emulator) or `ws://LOCAL_IP:8080` (if real device)  
**Web Caller:** `ws://localhost:8080`

### Scenario 2: Same WiFi Network

**Signaling Server:** Running on computer with IP `192.168.1.100`  
**Mobile App:** `ws://192.168.1.100:8080`  
**Web Caller:** `ws://192.168.1.100:8080`

### Scenario 3: Different Networks (Production)

Requires:
- Public signaling server (wss://)
- Properly configured TURN server
- Valid TURN credentials

## 🎤 Audio Flow

```
Web Caller (Microphone)
        ↓
  Get User Media
        ↓
  Add to PeerConnection
        ↓
   WebRTC Transport
        ↓
Mobile Receiver (Speaker)
        ↓
  onTrack Event
        ↓
  Audio Playback
```

**Note:** Audio automatically plays through the mobile device speaker. No manual renderer setup needed for audio-only calls.

## 🐛 Troubleshooting

### Mobile App Shows "Error"

✅ Check signaling server is running  
✅ Verify correct IP address in `signaling_service.dart`  
✅ Ensure device and server are on same network  
✅ Check firewall isn't blocking port 8080

### "Waiting for call..." Forever

✅ Make sure web caller connected to same server  
✅ Verify room name is "test-call" on both sides  
✅ Check browser console for web caller errors  
✅ Restart signaling server

### No Audio Heard on Mobile

✅ Check mobile device volume  
✅ Verify web caller granted microphone permission  
✅ Test with devices on same local network first  
✅ Check TURN credentials if on different networks

### Build Errors

```powershell
# Clean and rebuild
flutter clean
flutter pub get
flutter run
```

## 📱 Permissions

The app only requests permissions when needed:

- **No automatic permission request** - Since mobile is receiver only
- **Audio playback** - Works without permission (incoming audio)
- **If you add 2-way audio** - Would need RECORD_AUDIO permission

Current `AndroidManifest.xml` includes:
```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
```

## 🚀 Next Steps / Enhancements

### Basic Improvements
- [ ] Add accept/reject buttons (instead of auto-answer)
- [ ] Play ringtone when call arrives
- [ ] Show caller ID or caller name
- [ ] Add call duration timer
- [ ] Mute button for microphone

### Advanced Features
- [ ] **flutter_local_notifications** - Show incoming call notification
- [ ] **flutter_callkit_incoming** - Native iOS/Android call UI
- [ ] Two-way audio (add microphone to mobile)
- [ ] Video support
- [ ] Call history
- [ ] Multiple callers queue

### Production Ready
- [ ] User authentication
- [ ] Database for call logs
- [ ] Push notifications for missed calls
- [ ] Secure WebSocket (wss://)
- [ ] End-to-end encryption

## 📊 Call States Explained

| State | Meaning | UI Display |
|-------|---------|------------|
| `idle` | App just started | "Ready" |
| `waiting` | Connected, waiting for calls | "Waiting for call..." |
| `incoming` | Call offer received | "📞 Incoming Call!" |
| `connecting` | Answering call | "Connecting..." |
| `connected` | Call active | "✅ Call connected" |
| `ended` | Call terminated | "Call ended" |
| `error` | Something went wrong | "❌ Error occurred" |

## 🔐 Security Notes

⚠️ **This is an MVP/Demo application. For production:**

- ✅ Implement authentication (who can call you?)
- ✅ Use secure WebSocket (wss://) not ws://
- ✅ Validate signaling messages
- ✅ Add rate limiting
- ✅ Encrypt sensitive data
- ✅ Use HTTPS for web client
- ✅ Store TURN credentials securely

## 📄 License

This project is open source and available under the MIT License.

## 🤝 Contributing

Contributions, issues, and feature requests are welcome!

---

**Built with ❤️ using Flutter & WebRTC**

**Mode:** 📱 Receiver | **Type:** Audio-Only | **Auto-Answer:** ✅ Enabled
