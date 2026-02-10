# 📞 WebRTC Mobile Call App

A simple Flutter mobile application that can **initiate** a one-to-one WebRTC audio call to a web client.

## 🎯 Features

- ✅ Audio-only WebRTC calls (video-ready structure)
- ✅ One-to-one call between mobile (caller) and web (receiver)
- ✅ WebSocket-based signaling
- ✅ TURN/STUN server support
- ✅ Simple, clean UI with call status indicators
- ✅ Android support (iOS-ready structure)

## 🛠️ Tech Stack

- **Flutter** (SDK ^3.10.8)
- **flutter_webrtc** (^0.11.7) - WebRTC implementation
- **web_socket_channel** (^3.0.1) - WebSocket signaling
- **permission_handler** (^11.3.1) - Runtime permissions

## 📋 Prerequisites

Before running the app, ensure you have:

1. **Flutter SDK** installed ([installation guide](https://docs.flutter.dev/get-started/install))
2. **Android Studio** or **VS Code** with Flutter extensions
3. **Android device** or **emulator** (API level 21+)
4. **Node.js** (for running the signaling server)

## 🚀 Quick Start

### Step 1: Install Dependencies

```bash
# Install Flutter dependencies
flutter pub get

# Install signaling server dependencies
cd signaling_server
npm install
cd ..
```

### Step 2: Configure the App

Open `lib/services/signaling_service.dart` and update these values:

```dart
// Line 10: Update with your server IP
static const String _signalingServerUrl = 'ws://YOUR_SERVER_IP:8080';

// Lines 22-27: Update TURN credentials if needed
'username': 'YOUR_TURN_USERNAME',
'credential': 'YOUR_TURN_PASSWORD',
```

**Example for local testing:**
```dart
static const String _signalingServerUrl = 'ws://192.168.1.100:8080';
```

> **Note:** Use your computer's local IP address (not localhost) when testing on a real device.

### Step 3: Start the Signaling Server

```bash
cd signaling_server
npm start
```

You should see:
```
WebSocket signaling server running on port 8080
Waiting for connections...
```

### Step 4: Open the Web Client

1. Open `web_client/index.html` in a web browser
2. Update the server URL in the file if needed (line 149):
   ```javascript
   const SIGNALING_SERVER = 'ws://localhost:8080';
   ```
3. Click "Connect to Server" button
4. Wait for "Connected - Waiting for call..." message

### Step 5: Run the Flutter App

```bash
# Run on connected device
flutter run

# Or build and install APK
flutter build apk
flutter install
```

### Step 6: Make a Call

1. **On Mobile App:** Tap the "Call Web" button
2. **On Web Client:** The call will be automatically answered
3. **Both sides:** Start talking!
4. **To end:** Tap "End Call" on mobile

## 📁 Project Structure

```
scancall_mobile_app/
├── lib/
│   ├── main.dart                    # App entry point
│   ├── screens/
│   │   └── call_screen.dart         # Main call UI
│   └── services/
│       └── signaling_service.dart   # WebRTC & signaling logic
├── signaling_server/
│   ├── server.js                    # WebSocket signaling server
│   └── package.json                 # Server dependencies
├── web_client/
│   └── index.html                   # Web receiver client
├── android/
│   └── app/src/main/
│       └── AndroidManifest.xml      # Android permissions
└── pubspec.yaml                     # Flutter dependencies
```

## 🔄 Call Flow Explained

```
┌─────────────┐                 ┌──────────┐                 ┌────────────┐
│ Mobile App  │                 │ Signaling│                 │ Web Client │
│  (Caller)   │                 │  Server  │                 │ (Receiver) │
└─────────────┘                 └──────────┘                 └────────────┘
      │                               │                            │
      │  1. Connect to WS             │                            │
      │─────────────────────────────>│                            │
      │                               │                            │
      │  2. Join room "test-call"     │                            │
      │─────────────────────────────>│                            │
      │                               │                            │
      │  3. Get local media (audio)   │                            │
      │◄─────────────────────────────│                            │
      │                               │                            │
      │  4. Create offer              │                            │
      │─────────────────────────────>│                            │
      │                               │  5. Forward offer          │
      │                               │──────────────────────────>│
      │                               │                            │
      │                               │  6. Create answer          │
      │                               │◄──────────────────────────│
      │  7. Receive answer            │                            │
      │◄─────────────────────────────│                            │
      │                               │                            │
      │  8. Exchange ICE candidates   │                            │
      │◄────────────────────────────►│◄──────────────────────────│
      │                               │                            │
      │  9. 🔊 Audio Connection Established 🔊                    │
      │◄──────────────────────────────────────────────────────────│
      │                               │                            │
```

### Detailed Steps:

1. **Connection**: Mobile app connects to WebSocket signaling server
2. **Join Room**: Joins hard-coded room "test-call"
3. **Media**: Requests microphone access and gets local audio stream
4. **Offer**: Creates WebRTC offer with SDP (Session Description Protocol)
5. **Forward**: Server forwards offer to web client in the same room
6. **Answer**: Web client creates answer SDP
7. **Receive**: Mobile receives the answer
8. **ICE Exchange**: Both peers exchange ICE candidates for NAT traversal
9. **Connected**: Direct peer-to-peer audio connection established

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

**To use your own TURN server:**
- Replace the IP address and port
- Update username and credential

**For testing without TURN:**
- Keep only the STUN server (works on same network)

### Enable Video (Optional)

To enable video calls:

1. In `lib/services/signaling_service.dart` (line 90):
   ```dart
   'video': true, // Change from false to true
   ```

2. In `lib/services/signaling_service.dart` (line 99):
   ```dart
   'offerToReceiveVideo': true, // Change from false to true
   ```

3. Add video renderers to UI in `call_screen.dart`

## 🧪 Testing

### On Android Emulator

```bash
# Start emulator
flutter emulators --launch <emulator_id>

# Run app
flutter run
```

**Important:** Use `10.0.2.2` instead of `localhost` for signaling server:
```dart
static const String _signalingServerUrl = 'ws://10.0.2.2:8080';
```

### On Real Android Device

1. Enable **Developer Options** and **USB Debugging**
2. Connect device via USB
3. Ensure device and computer are on the **same WiFi network**
4. Use your computer's **local IP address** (e.g., `192.168.1.100`)
5. Run: `flutter run`

### Finding Your Local IP

**Windows:**
```powershell
ipconfig
# Look for "IPv4 Address" under your WiFi adapter
```

**Mac/Linux:**
```bash
ifconfig
# Look for "inet" address under your WiFi interface
```

## 📱 Permissions

The app requests these permissions on Android:

- ✅ **RECORD_AUDIO** - Required for audio calls
- ✅ **INTERNET** - Required for signaling and WebRTC
- ✅ **CAMERA** - Optional, for video calls
- ✅ **MODIFY_AUDIO_SETTINGS** - For audio routing
- ✅ **ACCESS_NETWORK_STATE** - For connection monitoring

Permissions are handled automatically by `permission_handler` plugin.

## 🐛 Troubleshooting

### "Connection Failed"
- ✅ Check signaling server is running
- ✅ Verify server URL in `signaling_service.dart`
- ✅ Ensure device and server are on same network
- ✅ Check firewall settings

### "Microphone Permission Denied"
- ✅ Grant microphone permission when prompted
- ✅ Check app permissions in device settings

### "Call Connects but No Audio"
- ✅ Check device volume
- ✅ Verify TURN/STUN server credentials
- ✅ Test with devices on same local network first

### "WebSocket Connection Refused"
- ✅ Use local IP address, not `localhost` on real device
- ✅ Use `10.0.2.2` instead of `localhost` on emulator
- ✅ Check port 8080 is not blocked by firewall

### "Build Failed"
- ✅ Run `flutter clean`
- ✅ Run `flutter pub get`
- ✅ Check Flutter version: `flutter --version`
- ✅ Update dependencies: `flutter pub upgrade`

## 🔐 Security Notes

⚠️ **This is an MVP/Demo application with hardcoded values. For production:**

- ❌ Don't hardcode TURN credentials in source code
- ✅ Use environment variables or secure config
- ✅ Implement proper authentication
- ✅ Use secure WebSocket (wss://) instead of ws://
- ✅ Validate all signaling messages
- ✅ Implement rate limiting on signaling server
- ✅ Use HTTPS for web client

## 🚀 Next Steps / Enhancements

For a production-ready app, consider:

1. **Authentication** - User login and identity verification
2. **Database** - Store call history and user data
3. **QR Code Scanning** - Dynamic room joining
4. **Push Notifications** - Notify users of incoming calls
5. **Video Support** - Full video calling with UI
6. **Multiple Participants** - Group calling
7. **Call Quality Indicators** - Network stats, bandwidth
8. **Recording** - Save calls (with consent)
9. **Screen Sharing** - Share screen during call
10. **Chat** - Text messaging during calls

## 📄 License

This project is open source and available under the MIT License.

## 🤝 Contributing

Contributions, issues, and feature requests are welcome!

## 📞 Support

For issues or questions:
- Check the troubleshooting section
- Review Flutter WebRTC documentation
- Open an issue in the repository

---

**Built with ❤️ using Flutter & WebRTC**

