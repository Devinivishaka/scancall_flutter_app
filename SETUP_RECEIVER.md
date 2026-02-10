# 🚀 Quick Setup Guide - Receiver Mode

This guide will help you get the WebRTC **RECEIVER** app running in **5 minutes**.

## 📱 What is Receiver Mode?

- **Mobile app WAITS for calls** (doesn't initiate them)
- **Web app CALLS the mobile** (initiates the call)
- **Auto-answer enabled** (no user interaction needed)
- **Audio flows: Web → Mobile** (web talks, mobile hears)

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

Edit `lib/services/signaling_service.dart`, line 12:

```dart
// Before:
static const String _signalingServerUrl = 'ws://YOUR_SERVER_IP:8080';

// After (use YOUR IP):
static const String _signalingServerUrl = 'ws://192.168.1.100:8080';
```

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

### 4️⃣ Run Mobile App - RECEIVER (1 minute)

Back in your main PowerShell window:

```powershell
# For connected Android device or emulator
flutter run
```

**Expected behavior:**
- App opens and shows "Waiting for call..."
- Status indicator shows "WAITING" (blue)
- App is now listening for incoming calls
- Leave this running!

### 5️⃣ Open Web Caller (30 seconds)

1. Navigate to `web_client/caller.html`
2. Right-click and open with your browser (Chrome/Edge recommended)
3. **Update server URL in the HTML file if needed** (line 162):
   ```javascript
   const SIGNALING_SERVER = 'ws://localhost:8080'; // or your IP
   ```

### 6️⃣ Make a Call from Web! (10 seconds)

**On Web Browser:**
1. Click the **"📞 Call Mobile App"** button
2. **Grant microphone permission** when prompted
3. You'll see "Creating call offer..."

**On Mobile (Automatically):**
1. Shows "📞 Incoming Call!"
2. Automatically answers (no user action needed!)
3. Status changes to "CONNECTING" → "CONNECTED"
4. You're now in the call!

**Test Audio:**
- **Speak into your computer microphone**
- **Hear your voice on the mobile device**
- Tap "End Call" on mobile to hang up

## 🎉 Success Indicators

✅ **Signaling Server:** Shows "Client connected" messages  
✅ **Mobile App:** Shows "✅ Call connected"  
✅ **Web Caller:** Shows "Call connected!"  
✅ **Audio:** Mobile hears audio from web caller

## 🔄 Call Flow Summary

```
1. Mobile App Starts → Connects to Server → Waits
2. Web Opens → User Clicks "Call Mobile App"
3. Web Creates Offer → Sends to Server
4. Server Forwards to Mobile → Mobile Shows "Incoming Call!"
5. Mobile Auto-Answers → Creates Answer → Sends Back
6. Connection Established → Web Audio → Mobile Hears
```

## 🧪 Testing Configurations

### Configuration 1: Real Device (Recommended)

```dart
// In signaling_service.dart:
static const String _signalingServerUrl = 'ws://192.168.1.100:8080';
// Use your actual local IP
```

```javascript
// In caller.html:
const SIGNALING_SERVER = 'ws://192.168.1.100:8080';
// Use same IP as mobile
```

- Device and PC must be on **same WiFi**
- Most reliable for testing

### Configuration 2: Android Emulator

```dart
// In signaling_service.dart:
static const String _signalingServerUrl = 'ws://10.0.2.2:8080';
// Special emulator address for host machine
```

```javascript
// In caller.html:
const SIGNALING_SERVER = 'ws://localhost:8080';
// Use localhost since browser is on same machine
```

## 🔧 Common Issues & Quick Fixes

### Issue: Mobile Shows "Error occurred"

**Fix:**
- Ensure signaling server is running
- Check IP address in code matches your computer's IP
- Make sure mobile device and computer are on **same WiFi**

### Issue: "Waiting for call..." Forever

**Fix:**
- Make sure web caller connected successfully
- Check browser console (F12) for errors
- Verify both use same room name: "test-call"
- Restart signaling server

### Issue: No Audio on Mobile

**Fix:**
- Check mobile device volume
- Grant microphone permission on web browser
- Verify web caller is speaking
- Try refreshing web page and calling again

### Issue: "Build Failed"

**Fix:**
```powershell
flutter clean
flutter pub get
flutter run
```

## 📊 Expected Console Output

**Signaling Server:**
```
WebSocket signaling server running on port 8080
New client connected (mobile)
Client abc123 joined room: test-call
New client connected (web)
Offer forwarded from def456
Answer forwarded from abc123
```

**Mobile App (Flutter):**
```
SignalingService initialized (Receiver Mode)
Connected to signaling server - Waiting for calls...
Joined room: test-call - Ready to receive calls
📞 INCOMING CALL!
Processing incoming offer...
Answer sent - Call connecting...
Connection state: connected
```

**Web Caller (Browser Console):**
```
Connected to signaling server
Joined room: test-call
Got local audio stream
Created offer
📤 Offer sent to mobile app
📥 Received answer from mobile app
Connection state: connected
✅ Call connected successfully!
```

## 🎯 Quick Test Checklist

Before making a call, verify:

- [ ] Signaling server is running (see console output)
- [ ] Mobile app shows "Waiting for call..."
- [ ] Web caller page is loaded
- [ ] Mobile and web use same server IP
- [ ] Both are in room "test-call"
- [ ] Mobile device has internet connection

## 💡 Pro Tips

1. **Keep all three windows visible:**
   - Signaling server terminal
   - Mobile app (device/emulator)
   - Web browser (caller)

2. **Test audio immediately:**
   - Speak into computer mic right after call connects
   - Should hear echo on mobile within 1-2 seconds

3. **Check logs if issues:**
   - Signaling server shows all message flows
   - Mobile app prints detailed WebRTC states
   - Browser console shows web side logs

4. **Auto-answer is instant:**
   - No delay or user prompt
   - Call connects automatically
   - Can add accept/reject UI later if needed

5. **Room name is key:**
   - Must be exactly "test-call" on both sides
   - Case-sensitive
   - One room = one call pair

## 🆘 Still Having Issues?

### Check These:

1. **Network:** Same WiFi for device and computer
2. **Firewall:** Port 8080 not blocked
3. **Server IP:** Matches in both mobile and web code
4. **Server Running:** Terminal shows "Waiting for connections..."
5. **Permissions:** Browser microphone access granted

### Get More Info:

```powershell
# Verbose Flutter logs
flutter run --verbose

# Check devices
flutter devices

# Check Flutter doctor
flutter doctor -v
```

## 📖 Understanding Receiver Mode

### What Happens When App Opens?

```
App Launch
    ↓
Initialize WebRTC
    ↓
Connect to Signaling Server
    ↓
Join Room "test-call"
    ↓
Status: "Waiting for call..."
    ↓
Listen for incoming offers
    ↓
(App stays in this state until call arrives)
```

### What Happens When Call Arrives?

```
Offer Received
    ↓
Show "📞 Incoming Call!"
    ↓
Automatically create answer
    ↓
Send answer back
    ↓
Exchange ICE candidates
    ↓
Status: "Connected"
    ↓
Play incoming audio
```

## 🎓 Next Steps After Testing

Once you have it working:

1. **Add User Confirmation:**
   - Show accept/reject buttons
   - Replace auto-answer with user choice

2. **Add Notifications:**
   - Use `flutter_local_notifications`
   - Show incoming call notification
   - Play ringtone

3. **Add Two-Way Audio:**
   - Request microphone on mobile
   - Add local audio track
   - Enable full conversation

4. **Add Call UI:**
   - Use `flutter_callkit_incoming`
   - Native iOS/Android call interface
   - Better user experience

---

**Ready to receive calls?** Follow the steps above and you'll be connected in 5 minutes! 📱🔔
