# 🚀 Quick Setup Guide

This guide will help you get the WebRTC call app running in **5 minutes**.

## ⚡ Prerequisites Checklist

- [ ] Flutter SDK installed
- [ ] Node.js installed
- [ ] Android device or emulator ready
- [ ] Text editor (VS Code recommended)

## 📝 Step-by-Step Setup

### 1️⃣ Install Dependencies (2 minutes)

Open PowerShell in the project directory:

```powershell
# Install Flutter dependencies
flutter pub get

# Install signaling server dependencies
cd signaling_server
npm install
cd ..
```

### 2️⃣ Configure Server URL (1 minute)

**Find your computer's IP address:**

```powershell
ipconfig
```

Look for "IPv4 Address" (example: `192.168.1.100`)

**Update the Flutter app:**

Edit `lib/services/signaling_service.dart`, line 10:

```dart
// Before:
static const String _signalingServerUrl = 'ws://YOUR_SERVER_IP:8080';

// After (use YOUR IP):
static const String _signalingServerUrl = 'ws://192.168.1.100:8080';
```

**Update TURN credentials (optional):**

Lines 22-27 in the same file:

```dart
'username': 'your_actual_username',
'credential': 'your_actual_password',
```

> **Tip:** For local testing on the same network, you can skip TURN setup.

### 3️⃣ Start Signaling Server (30 seconds)

Open a **new PowerShell window**:

```powershell
cd signaling_server
npm start
```

Keep this window open! You should see:
```
WebSocket signaling server running on port 8080
Waiting for connections...
```

### 4️⃣ Open Web Client (30 seconds)

1. Navigate to `web_client/index.html`
2. Right-click and open with your browser (Chrome/Edge recommended)
3. **Update server URL in the HTML file if needed** (line 149):
   ```javascript
   const SIGNALING_SERVER = 'ws://localhost:8080'; // or your IP
   ```
4. Click the **"Connect to Server"** button
5. You should see "Connected - Waiting for call..."

### 5️⃣ Run Flutter App (1 minute)

Back in your main PowerShell window:

```powershell
# For connected Android device or emulator
flutter run
```

Wait for the app to install and launch.

### 6️⃣ Make Your First Call! (10 seconds)

1. **On Mobile:** Tap the green **"Call Web"** button
2. **Grant microphone permission** when prompted
3. **On Web:** The call will auto-answer
4. **Talk!** You should hear each other
5. **To end:** Tap **"End Call"** on mobile

## 🎉 Success Indicators

✅ **Signaling Server:** Shows "Client connected" messages  
✅ **Web Client:** Status shows "Call connected!"  
✅ **Mobile App:** Status shows "Connected"  
✅ **Audio:** You can hear audio between devices

## 🔧 Common Issues & Quick Fixes

### Issue: "Connection Failed"

**Fix:**
- Ensure signaling server is running
- Check that IP address in code matches your computer's IP
- Make sure mobile device and computer are on **same WiFi**

### Issue: "Permission Denied"

**Fix:**
- Grant microphone permission when prompted
- If denied, go to Settings > Apps > Permissions and enable Microphone

### Issue: "No Audio"

**Fix:**
- Check device volume
- Try on same local network first
- Verify microphone is not muted

### Issue: "Build Failed"

**Fix:**
```powershell
flutter clean
flutter pub get
flutter run
```

## 🧪 Testing Configurations

### Configuration 1: Real Device (Recommended)

```dart
// In signaling_service.dart:
static const String _signalingServerUrl = 'ws://192.168.1.100:8080';
// Use your actual local IP
```

- Device and PC must be on **same WiFi**
- Most reliable for testing

### Configuration 2: Android Emulator

```dart
// In signaling_service.dart:
static const String _signalingServerUrl = 'ws://10.0.2.2:8080';
// Special emulator address for host machine
```

- Works without real device
- Audio quality may vary

## 📊 Expected Console Output

**Signaling Server:**
```
WebSocket signaling server running on port 8080
Waiting for connections...
New client connected
Client abc123 joined room: test-call
Offer forwarded from abc123
ICE candidate forwarded from abc123
```

**Mobile App (Flutter):**
```
SignalingService initialized
Connected to signaling server
Offer sent
Answer received and set
ICE candidate added
Connection state: RTCPeerConnectionStateConnected
```

**Web Client:**
```
[12:34:56] Connected to signaling server
[12:34:57] Joined room: test-call
[12:34:58] Received: offer
[12:34:58] Received remote track
[12:34:59] Connection state: connected
[12:34:59] Call connected successfully!
```

## 🎯 Quick Test Checklist

Before making a call, verify:

- [ ] Signaling server is running (see console output)
- [ ] Web client shows "Connected - Waiting for call..."
- [ ] Mobile app shows "Ready to call"
- [ ] Mobile device has internet connection
- [ ] Microphone permission is granted
- [ ] Server IP is correct in code

## 🆘 Need More Help?

1. Check the main [README.md](README.md) for detailed documentation
2. Review the **Troubleshooting** section
3. Verify all configuration values match your setup
4. Check console logs for error messages

## 🎓 Understanding the Flow

```
Mobile App → WebSocket Server → Web Client
     ↓                              ↓
  Creates                        Answers
   Offer                          Offer
     ↓                              ↓
  Exchange ICE Candidates ←→ Exchange
     ↓                              ↓
         Direct Audio Connection
```

## 💡 Pro Tips

1. **Keep signaling server logs visible** - helps debug issues
2. **Test on same WiFi first** - eliminates network complexity
3. **Use real device** - better audio quality than emulator
4. **Check browser console** - web client logs are helpful
5. **Grant permissions immediately** - avoid call setup delays

---

**Ready to go?** Follow the steps above and you'll be making calls in 5 minutes! 🚀
