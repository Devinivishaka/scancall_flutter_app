# FCM Test Caller - Complete Testing Guide

## Overview
This test UI allows you to initiate WebRTC video calls to your Flutter app using FCM notifications, simulating a complete production call flow.

## Prerequisites

1. **Backend Running**: Make sure the ScanCall backend is running on port 8080
2. **Flutter App Running**: Install and run the Flutter app on your device/emulator
3. **FCM Configured**: The Flutter app must have Firebase configured properly

## Setup Instructions

### 1. Get Your FCM Token

1. Launch the Flutter app
2. On the home screen, you'll see your FCM token
3. Tap "Copy Token" to copy it to clipboard
4. Keep this token ready for testing

### 2. Update Server URL

Open `fcm_test_caller.html` and update the server URL:

```javascript
// For Android Emulator
ws://10.0.2.2:8080/ws

// For Physical Device (use your computer's local IP)
ws://192.168.1.xxx:8080/ws
```

To find your local IP:
- **Windows**: Open Command Prompt → `ipconfig` → Look for "IPv4 Address"
- **Mac/Linux**: Open Terminal → `ifconfig` → Look for "inet" under your network interface

### 3. Open the Test UI

Simply open `fcm_test_caller.html` in your web browser (Chrome/Firefox/Edge recommended).

## How to Make a Test Call

### Step 1: Configure
1. Enter your WebSocket server URL (default: `ws://10.0.2.2:8080/ws`)
2. Paste the FCM token from your Flutter app
3. (Optional) Enter a custom Call ID, or leave empty for auto-generation

### Step 2: Initiate Call
1. Click "📞 Call Device"
2. Allow camera and microphone access when prompted
3. The page will join a WebSocket room and wait

### Step 3: Send FCM Notification
You need to send an FCM push notification to trigger the call on the mobile device.

**Using the FCM Test Script:**

```bash
cd tools/fcm_caller
npm install
node index.js -t <YOUR_FCM_TOKEN> -i <CALL_ID> -c "Web Caller"
```

Replace:
- `<YOUR_FCM_TOKEN>`: The FCM token from your Flutter app
- `<CALL_ID>`: The Call ID shown in the web UI

**Alternatively**, you can use the Firebase Console or your own FCM sending method.

The FCM payload should be:
```json
{
  "to": "<FCM_TOKEN>",
  "priority": "high",
  "data": {
    "type": "incoming_call",
    "callId": "<CALL_ID>",
    "callerName": "Web Caller"
  }
}
```

### Step 4: Accept Call on Mobile
1. Your Flutter app will show a native call UI (CallKit on iOS, similar on Android)
2. Accept the call
3. Grant camera and microphone permissions if prompted

### Step 5: Video Call Established!
- The web UI will detect that the receiver joined
- It will automatically send the WebRTC offer
- The mobile app will send back an answer
- Video call should connect within a few seconds

## Troubleshooting

### Call doesn't connect

1. **Check WebSocket Connection**
   - Look at the logs in the web UI
   - Make sure you see "✅ Connected to signaling server"
   - Make sure you see "📥 Joined room: call-xxx"

2. **Check Mobile App Logs**
   - In Android Studio: View → Tool Windows → Logcat
   - Filter by "flutter" to see app logs
   - Look for WebSocket connection messages

3. **Verify Same Room**
   - Both web caller and mobile app must join the SAME room (call ID)
   - Check logs on both sides to confirm room names match

4. **Network Issues**
   - If on physical device, make sure it's on the same WiFi as your computer
   - Check firewall settings - port 8080 should be accessible
   - Try pinging your computer's IP from a terminal app on the device

5. **FCM Notification Not Received**
   - Check that Firebase is properly configured in the Flutter app
   - Verify FCM token is correct and not expired
   - Check FCM test script output for errors
   - Look at Firebase Console → Cloud Messaging for delivery status

### Video doesn't show

1. **Check Permissions**
   - Make sure both devices have granted camera/microphone permissions
   - On mobile: Settings → Apps → ScanCall → Permissions

2. **Check ICE Connection**
   - Look for ICE connection state logs
   - Should see "✅ ICE Connected" on both sides
   - If stuck on "checking", there may be NAT/firewall issues

3. **TURN Server**
   - If on different networks, you may need a TURN server
   - Check TURN server configuration in both the web UI and Flutter app
   - Verify TURN server is running (if self-hosted)

## Advanced: Testing Without FCM

For quick testing without FCM infrastructure, you can:

1. Paste the same Call ID in both the web UI and a second browser tab
2. Open `web_receiver.html` in another tab
3. Both will join the same room and connect directly

## Technical Details

### Call Flow

1. Web caller connects to WebSocket and joins room `<callId>`
2. Web caller sends FCM notification to target device
3. Mobile device receives FCM → Shows CallKit UI
4. User accepts → CallScreen opens and connects to WebSocket
5. Mobile app joins same room `<callId>`
6. Backend notifies web caller: "user-joined"
7. Web caller creates and sends WebRTC offer
8. Mobile app receives offer → Auto-accepts (user already accepted via CallKit)
9. Mobile app creates and sends WebRTC answer
10. ICE candidates exchanged → Media flows!

### WebRTC Signaling

- **SDP Offer/Answer**: Describes media capabilities
- **ICE Candidates**: Network connectivity information
- **Backend Role**: Relays messages between peers
- **Room-based**: Peers join same "room" to exchange messages

### Security Notes

- This is a testing tool - production apps should:
  - Validate and authenticate users
  - Encrypt signaling messages
  - Use secure WebSocket (wss://)
  - Implement proper access control

## Files

- `fcm_test_caller.html` - Main test UI (this file)
- `tools/fcm_caller/index.js` - FCM notification sender script
- `web_receiver.html` - Alternative web receiver (for testing without mobile)
- `web_caller.html` - Original web-to-web test (hardcoded room)

## Need Help?

Check the browser console (F12) and mobile device logs for detailed debugging information. All major events are logged.
