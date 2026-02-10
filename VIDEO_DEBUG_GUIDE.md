# 🔍 Video Not Showing - Debug Guide

## 🐛 Issue: Android Call Screen Not Showing Video

You mentioned the Android call page is not showing the actual video. Let's debug this systematically.

---

## ✅ Fixes Applied

### 1. Enhanced Video Track Handling
- ✅ Added explicit track enabling in onTrack callback
- ✅ Improved stream accumulation for multiple track events
- ✅ Added track ID and status logging

### 2. Improved Video Renderer Display
- ✅ Added null check for srcObject before showing video
- ✅ Added loading indicators with status messages
- ✅ Enhanced video view properties (filterQuality, mirror)
- ✅ Added better fallback UI for missing video

### 3. Enhanced Stream Reception
- ✅ Force setState after stream is set
- ✅ Added delayed rebuild to ensure rendering
- ✅ Explicit track enabling in UI layer

### 4. Better SDP Debugging
- ✅ Added video codec detection in SDP
- ✅ Added video direction checking (sendrecv/recvonly/sendonly)
- ✅ Enhanced offer/answer logging

---

## 🧪 Testing Steps

### Step 1: Clean Rebuild

```powershell
cd D:\Projects\scancall_mobile_app
flutter clean
flutter pub get
flutter run --verbose
```

### Step 2: Start Signaling Server

```powershell
cd signaling_server
npm start
```

### Step 3: Make Test Call

1. Open `web_client/caller.html` in browser
2. Click "Make Call"
3. Accept permissions in browser
4. On Android: Tap "Accept Call"
5. Grant permissions if prompted

### Step 4: Check Logs

**Look for these specific log messages:**

#### On Android (Expected Success Logs):

```
✅ Video renderers initialized
   - Local renderer ready: true
   - Remote renderer ready: true

✅ Permissions granted
Accepting call...
Requesting camera and microphone access...

✅ Got local audio/video stream
   - Video tracks: 1
   - Audio tracks: 1
   - Video track enabled: track_id_here

✅ Added video track to peer connection
✅ Added audio track to peer connection

📥 Processing incoming offer...
✅ Remote description (offer) set
✅ Offer contains video track
   - Video codecs found: 1 (or more)

✅ Answer contains video track
   - Video codecs in answer: 1 (or more)
   - Video direction: sendrecv ✅

✅ Local description (answer) set
✅ Answer sent - Call connecting...

🎥 Received remote video track
   - Track ID: some_track_id
   - Track enabled: true
✅ New remote stream: stream_id
   - Video tracks: 1
   - Audio tracks: 1

📹 Local stream received in UI
   - Video tracks: 1
   - Audio tracks: 1
   - Local video track: track_id, enabled: true
   ✅ Local renderer updated with stream

🎥 Remote stream received in UI
   - Video tracks: 1
   - Audio tracks: 1
   - Remote video track: track_id, enabled: true
   ✅ Remote renderer updated with stream

Connection state: RTCPeerConnectionStateConnected
```

---

## 🔍 Diagnostic Checklist

### Issue: Black Screen on Android

Check these in order:

#### 1. Check Permissions
```
Android Settings → Apps → scancall_mobile_app → Permissions
- Camera: ✅ Allow
- Microphone: ✅ Allow
```

**If permissions denied:**
- Uninstall app
- Reinstall: `flutter run`
- Grant permissions when prompted

#### 2. Check Video Tracks in Logs

**Look for:**
```
Video tracks: 1  ← Should be 1, not 0
Audio tracks: 1  ← Should be 1, not 0
```

**If you see "Video tracks: 0":**
- Camera is not being accessed
- Check permission errors above
- Another app might be using camera

#### 3. Check Renderer Initialization

**Look for:**
```
✅ Video renderers initialized
   - Local renderer ready: true
   - Remote renderer ready: true
```

**If "false" or error:**
- Renderer initialization failed
- Try restarting the app

#### 4. Check SDP Video Presence

**Look for:**
```
✅ Offer contains video track
✅ Answer contains video track
   - Video direction: sendrecv ✅
```

**If "does NOT contain video":**
- Web caller might not be sending video
- Check web browser console for errors
- Ensure web browser granted camera permission

#### 5. Check onTrack Events

**Look for:**
```
🎥 Received remote video track
✅ New remote stream: stream_id
   - Video tracks: 1
```

**If you DON'T see this:**
- Peer connection is not receiving tracks
- Check ICE connection state
- Might need TURN server

#### 6. Check UI Stream Reception

**Look for:**
```
🎥 Remote stream received in UI
   ✅ Remote renderer updated with stream
```

**If you DON'T see this:**
- Stream is not reaching UI layer
- Check if callback is registered properly

---

## 🔧 Common Issues & Solutions

### Issue 1: "Camera permission denied"

**Solution:**
```powershell
# Uninstall and reinstall
adb uninstall com.example.scancall_mobile_app
flutter run
# Grant permissions when prompted
```

### Issue 2: "Video tracks: 0"

**Possible causes:**
- Camera already in use by another app
- Permission not granted
- Camera hardware issue

**Solution:**
```
1. Close all camera apps
2. Restart Android device
3. Reinstall app
4. Grant permissions
```

### Issue 3: Video works but shows black screen

**Possible causes:**
- Video track disabled
- Wrong video constraints
- Renderer not updating

**Check logs for:**
```
Track enabled: false  ← Should be true!
```

**Our fix handles this by explicitly enabling tracks**

### Issue 4: Only audio works, no video

**Possible causes:**
- Web caller not sending video
- SDP negotiation missing video
- Video codec mismatch

**Check:**
1. Web browser console for errors
2. "Offer contains video track" in logs
3. "Answer contains video track" in logs

### Issue 5: Local video works, remote video doesn't

**Possible causes:**
- Web caller's camera not working
- Network blocking video packets
- TURN server needed

**Solution:**
1. Test web caller camera with another app
2. Check TURN server is running
3. Verify firewall rules

---

## 📱 Visual Verification

### What You Should See on Android:

1. **Top-right corner:** Small video of yourself (local video)
   - Your face from front camera
   - Mirror effect applied
   - 120x160 pixels
   - White border

2. **Full screen:** Video from web caller (remote video)
   - Caller's face
   - Full screen coverage
   - No mirror effect
   - Should fill entire screen

### What You Should See in Web Browser:

1. **Local video element:** Your own face
2. **Remote video element:** Android user's face

---

## 🧪 Quick Test Script

Run this to get comprehensive logs:

```powershell
# Terminal 1: Start signaling server
cd D:\Projects\scancall_mobile_app\signaling_server
npm start

# Terminal 2: Run app with verbose logging
cd D:\Projects\scancall_mobile_app
flutter run --verbose 2>&1 | Select-String -Pattern "Video|video|track|Track|stream|Stream|renderer|Renderer|permission|Permission"
```

This filters logs to show only video-related messages.

---

## 🔍 Advanced Debugging

### Check Video Renderer State

Add this temporary debug code to `call_screen.dart`:

```dart
// In _buildVideoCallUI(), before return Stack
print('🎬 Building video UI:');
print('   - Remote renderer initialized: $_remoteVideoInitialized');
print('   - Remote srcObject null: ${_remoteRenderer.srcObject == null}');
print('   - Local renderer initialized: $_localVideoInitialized');
print('   - Local srcObject null: ${_localRenderer.srcObject == null}');
```

### Check Track States

Add this in `signaling_service.dart` after getting local stream:

```dart
print('📊 Local Stream Analysis:');
for (var track in _localStream!.getTracks()) {
  print('   ${track.kind}: ${track.id}');
  print('      - enabled: ${track.enabled}');
  print('      - muted: ${track.muted}');
  print('      - readyState: ${track.readyState}');
}
```

### Dump Full SDP

Add this after creating answer:

```dart
print('📄 FULL ANSWER SDP:');
print(answer.sdp);
```

Look for these sections:
- `m=video` line (video media section)
- `a=sendrecv` (bidirectional video)
- `a=rtpmap` lines (video codecs)

---

## 🎯 Expected Behavior

### Timeline of Events:

```
1. App starts → Renderers initialized ✅
2. Call comes in → Ringtone plays ✅
3. User accepts → Request camera/mic ✅
4. Permissions granted → Get local stream ✅
5. Add tracks → Peer connection has tracks ✅
6. Create answer → SDP includes video ✅
7. Send answer → Web receives answer ✅
8. ICE negotiation → Connection establishes ✅
9. onTrack fires → Remote stream received ✅
10. UI updates → Video displays ✅
```

**If video doesn't show, find where in this timeline it fails.**

---

## 📊 Comparison: Working vs Not Working

### Working Scenario Logs:
```
✅ Got local audio/video stream
   - Video tracks: 1
   - Audio tracks: 1
✅ Added video track to peer connection
✅ Offer contains video track
✅ Answer contains video track
🎥 Received remote video track
   - Video tracks: 1
🎥 Remote stream received in UI
   ✅ Remote renderer updated with stream
```

### Not Working Scenario (Examples):

**Scenario A: No permissions**
```
❌ Failed to get camera/microphone
⚠️ Make sure camera and microphone permissions are granted
```
→ **Fix:** Grant permissions

**Scenario B: No video tracks**
```
✅ Got local audio/video stream
   - Video tracks: 0  ← PROBLEM!
   - Audio tracks: 1
```
→ **Fix:** Camera in use by another app

**Scenario C: SDP has no video**
```
✅ Remote description (offer) set
⚠️ Offer does NOT contain video track  ← PROBLEM!
```
→ **Fix:** Web caller not sending video

**Scenario D: Never receives remote track**
```
✅ Answer sent - Call connecting...
[No onTrack event]  ← PROBLEM!
Connection state: RTCPeerConnectionStateConnected
```
→ **Fix:** Check TURN server, firewall

---

## 🚀 Next Steps

1. **Rebuild and run** the app with new fixes
   ```powershell
   flutter clean && flutter pub get && flutter run
   ```

2. **Make a test call** from web to Android

3. **Capture the logs** and check for the success patterns above

4. **Report back** with:
   - What you see on screen
   - What the logs show
   - At which step it fails

---

## 📞 Specific Things to Report

Please check and report:

1. **Do you see the loading indicator?**
   - "Waiting for video..." text?
   - Spinning progress indicator?

2. **What do the logs show?**
   - "Video tracks: 1" or "Video tracks: 0"?
   - "Offer contains video track"?
   - "Received remote video track"?

3. **Permissions status?**
   - Are they granted?
   - Any permission errors in logs?

4. **Web browser status?**
   - Does web browser show Android user's video?
   - Any errors in browser console?

---

**Run the test now and share the logs!** We've added extensive debugging to pinpoint exactly where the issue is. 🔍

