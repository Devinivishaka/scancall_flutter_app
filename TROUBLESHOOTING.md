# 🔧 Troubleshooting Guide

Common issues and their solutions for the WebRTC Call App.

## 🐛 Build & Compilation Issues

### Issue: Kotlin Compilation Cache Errors

**Error Message:**
```
Could not close incremental caches in D:\Projects\scancall_mobile_app\build\flutter_webrtc\kotlin...
Storage for [...] is already registered
```

**Solution:**
These are usually non-fatal warnings from Kotlin's incremental compilation. If the build succeeds (shows "Built build\app\outputs\flutter-apk\app-debug.apk"), you can ignore them.

**If build fails, try:**

```powershell
# 1. Clean the build
flutter clean

# 2. Delete gradle cache
cd android
./gradlew clean
cd ..

# 3. Rebuild
flutter pub get
flutter build apk --debug
```

---

### Issue: "cannot find symbol PluginRegistry.Registrar"

**Error Message:**
```
error: cannot find symbol
import io.flutter.plugin.common.PluginRegistry.Registrar;
```

**Cause:** Outdated flutter_webrtc version incompatible with Flutter SDK

**Solution:**

```yaml
# In pubspec.yaml, update to:
flutter_webrtc: ^0.12.4  # or higher
```

Then run:
```powershell
flutter clean
flutter pub get
```

---

### Issue: Java/Kotlin Version Warnings

**Warning Message:**
```
warning: [options] source value 8 is obsolete
warning: [options] target value 8 is obsolete
```

**Solution:**
These are just warnings and won't prevent the build. To suppress them, update `android/build.gradle.kts`:

```kotlin
tasks.withType<JavaCompile> {
    options.compilerArgs.add("-Xlint:-options")
}
```

---

## 📱 Runtime Issues

### Issue: "Connection Failed"

**Symptoms:**
- App shows "Error occurred"
- Web client can't receive calls
- Console shows WebSocket errors

**Solutions:**

**1. Check Signaling Server:**
```powershell
# Make sure server is running
cd signaling_server
npm start
```

**2. Verify Server URL:**
```dart
// In lib/services/signaling_service.dart
// Use your actual IP address, not localhost on real device
static const String _signalingServerUrl = 'ws://192.168.1.100:8080';
```

**3. For Android Emulator:**
```dart
// Use special emulator address
static const String _signalingServerUrl = 'ws://10.0.2.2:8080';
```

**4. Check Network:**
- Device and computer must be on the same WiFi
- Check firewall isn't blocking port 8080
- Try pinging the server IP from device

---

### Issue: "Microphone Permission Denied"

**Symptoms:**
- Can't start call
- Error when tapping "Call Web"
- Permission dialog doesn't appear

**Solutions:**

**1. Grant Permission in Settings:**
```
Settings > Apps > scancall_mobile_app > Permissions > Microphone > Allow
```

**2. Check Manifest:**
Ensure `android/app/src/main/AndroidManifest.xml` contains:
```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
```

**3. Reinstall App:**
```powershell
flutter clean
flutter run
```

---

### Issue: "Call Connects but No Audio"

**Symptoms:**
- Status shows "Connected"
- But no audio is heard on either side

**Solutions:**

**1. Check Device Volume:**
- Ensure volume is up on both devices
- Check that audio isn't muted

**2. Verify TURN/STUN Servers:**
```dart
// In signaling_service.dart
// Make sure TURN credentials are correct
'username': 'correct_username',
'credential': 'correct_password',
```

**3. Test on Same Network:**
- Try with devices on same local WiFi
- STUN alone should work for local network
- TURN is only needed for different networks

**4. Check Audio Permissions:**
```powershell
# Reinstall to reset permissions
flutter clean
flutter run
```

---

### Issue: "Storage for [...] is already registered"

**Symptoms:**
- Build fails with Kotlin cache errors
- Multiple "already registered" messages

**Solution:**

```powershell
# Stop any Gradle daemons
cd android
./gradlew --stop
cd ..

# Clean everything
flutter clean

# Delete .gradle folder
Remove-Item -Recurse -Force android\.gradle

# Rebuild
flutter pub get
flutter build apk --debug
```

---

## 🌐 WebSocket Issues

### Issue: "WebSocket Connection Refused"

**Solutions:**

**1. Check Server is Running:**
```powershell
cd signaling_server
npm start
# Should show: "WebSocket signaling server running on port 8080"
```

**2. Find Your IP Address:**
```powershell
ipconfig
# Look for "IPv4 Address" under WiFi adapter
```

**3. Update Code with Correct IP:**
```dart
// Update in lib/services/signaling_service.dart
static const String _signalingServerUrl = 'ws://YOUR_ACTUAL_IP:8080';
```

**4. Test Server Accessibility:**
```powershell
# From your device browser, visit:
http://YOUR_IP:8080
# If server is running, it should respond (even if with error)
```

---

### Issue: "Web Client Not Receiving Calls"

**Solutions:**

**1. Check Web Client Connection:**
- Open browser console (F12)
- Look for "Connected to signaling server"
- Ensure "Connect to Server" button was clicked

**2. Update Web Client URL:**
```javascript
// In web_client/index.html, line 149
const SIGNALING_SERVER = 'ws://YOUR_IP:8080';  // Use actual IP
```

**3. Check Same Room:**
Both mobile and web should use same room name:
- Mobile: `test-call` (in signaling_service.dart)
- Web: `test-call` (in index.html)

---

## 📦 Dependency Issues

### Issue: "Target of URI doesn't exist"

**Error:**
```
Target of URI doesn't exist: 'package:flutter_webrtc/flutter_webrtc.dart'
```

**Solution:**
```powershell
# Get dependencies
flutter pub get

# If still fails, clean first
flutter clean
flutter pub get

# Restart IDE/Editor
```

---

### Issue: "version solving failed"

**Error:**
```
Because dependency X requires Y and...
version solving failed
```

**Solution:**

**1. Update Dependencies:**
```powershell
flutter pub upgrade
```

**2. Check Flutter Version:**
```powershell
flutter --version
# Should be 3.10.8 or higher
```

**3. Update Flutter:**
```powershell
flutter upgrade
```

---

## 🔥 Emergency Fixes

### Nuclear Option: Complete Reset

If nothing else works:

```powershell
# 1. Stop all processes
cd android
./gradlew --stop
cd ..

# 2. Delete all caches
flutter clean
Remove-Item -Recurse -Force android\.gradle
Remove-Item -Recurse -Force android\.idea
Remove-Item -Recurse -Force build

# 3. Clear pub cache (optional, slow)
flutter pub cache repair

# 4. Fresh install
flutter pub get

# 5. Rebuild
flutter build apk --debug
```

---

## 📊 Diagnostic Commands

### Check Flutter Setup
```powershell
flutter doctor -v
```

### Check Dependencies
```powershell
flutter pub outdated
```

### Check Connected Devices
```powershell
flutter devices
```

### Verbose Build (More Info)
```powershell
flutter build apk --debug --verbose
```

### Run with Logs
```powershell
flutter run --verbose
```

---

## 🔍 Debugging Tips

### Enable More Logging

**In Flutter (lib/services/signaling_service.dart):**
```dart
// Add more print statements
print('DEBUG: Current state = $_callState');
print('DEBUG: ICE candidate = ${candidate.candidate}');
```

**In Web Client (index.html):**
```javascript
// Check browser console (F12)
console.log('DEBUG:', data);
```

**Signaling Server (server.js):**
```javascript
// Already has console.log statements
// Check terminal where server is running
```

---

## 🆘 Still Having Issues?

### 1. Check Prerequisites
- [ ] Flutter SDK installed and in PATH
- [ ] Android SDK installed
- [ ] Device connected or emulator running
- [ ] Node.js installed (for signaling server)

### 2. Verify Configuration
- [ ] Correct server IP in signaling_service.dart
- [ ] Same WiFi network
- [ ] Permissions granted
- [ ] Signaling server running

### 3. Test Components Individually
- [ ] Can you build a simple Flutter app?
- [ ] Can web client connect to signaling server?
- [ ] Can you access server from device browser?

### 4. Collect Information
When asking for help, provide:
- Flutter version: `flutter --version`
- Error messages (full stack trace)
- Steps to reproduce
- What you've already tried

---

## 📝 Common Configuration Values

### For Local Testing (Same WiFi)

**Mobile App (signaling_service.dart):**
```dart
static const String _signalingServerUrl = 'ws://192.168.1.100:8080';
```

**Web Client (index.html):**
```javascript
const SIGNALING_SERVER = 'ws://localhost:8080';  // If on same computer
// OR
const SIGNALING_SERVER = 'ws://192.168.1.100:8080';  // If on different computer
```

### For Android Emulator

**Mobile App:**
```dart
static const String _signalingServerUrl = 'ws://10.0.2.2:8080';
```

### For Production

**Both:**
```
wss://your-domain.com/signaling  // Note: wss (secure) not ws
```

---

**Remember:** Most issues are related to network configuration or permissions. Always check these first!
