# ScanCall FCM Testing Suite

## 🚀 Quick Setup

### 1. Install Dependencies
```bash
cd fcm_testing
npm install
```

### 2. Get Firebase Service Account Key
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project → **Project Settings** → **Service Accounts**
3. Click **Generate new private key**
4. Download the JSON file
5. Rename it to `service-account-key.json` and place it in this folder

### 3. Get FCM Token from Your App
1. Run your Flutter app
2. Look for this log message:
   ```
   🔑 FCM Registration Token: [very_long_token_here]
   ```
3. Copy the token

### 4. Configure Token
**Method 1 (Recommended):** Update `.env` file:
```env
FCM_TOKEN=your_actual_fcm_token_here
```

**Method 2:** Edit `fcm-test-script.js` directly:
```javascript
fcmToken: 'your_actual_fcm_token_here'
```

## 🧪 Testing Commands

### Interactive Test (Recommended)
```bash
npm test
```
This will:
- Send an incoming call notification
- Wait 30 seconds
- Auto-cancel the call
- Show results

### Manual Commands
```bash
# Send an incoming call
npm run test-call

# Send a specific call with custom ID and name
npm run test-call room_123 "Alice Smith"

# Cancel a call
npm run test-cancel room_123
```

## 📱 Expected App Behavior

### ✅ When Working Correctly:

1. **App Foreground:**
   - Console shows: `🔔 FCM Message Received (foreground)`
   - Native incoming call UI appears
   - Shows caller name and accept/reject buttons

2. **App Background:**
   - Native call UI appears even when app is backgrounded
   - Phone may ring/vibrate

3. **App Terminated:**
   - Call UI appears when FCM is received
   - App may launch in background

4. **User Actions:**
   - **Accept:** App opens CallScreen with callId
   - **Reject:** Call UI dismisses

## 🔍 Troubleshooting

### "Firebase initialization failed"
- ✅ Download `service-account-key.json` from Firebase Console
- ✅ Place it in the `fcm_testing` folder

### "registration-token-not-registered"
- ✅ Get fresh FCM token from app logs
- ✅ Make sure app is using Google Play Services (not AOSP emulator)

### "No incoming call UI appears"
- ✅ Check Flutter app logs for FCM message reception
- ✅ Verify Android permissions in AndroidManifest.xml
- ✅ Check `flutter_callkit_incoming` setup

### "CallScreen doesn't open on accept"
- ✅ Verify `CallEvent.actionCallAccept` handler in Flutter
- ✅ Check if `callId` is being passed correctly

## 📊 Sample FCM Messages

### Incoming Call
```json
{
  "data": {
    "type": "incoming_call",
    "callId": "room_123",
    "callerName": "John Doe",
    "callerAvatar": "https://example.com/avatar.jpg"
  }
}
```

### Call Cancel
```json
{
  "data": {
    "type": "call_cancel", 
    "callId": "room_123"
  }
}
```

## 📋 Testing Checklist

- [ ] Firebase service account key downloaded
- [ ] FCM token copied from app logs  
- [ ] Dependencies installed (`npm install`)
- [ ] Incoming call test works (`npm test`)
- [ ] Call UI appears on device
- [ ] Accept button opens CallScreen
- [ ] Reject button dismisses UI
- [ ] Cancel message dismisses UI
- [ ] Works when app is backgrounded
- [ ] Works when app is terminated

## 🔗 Integration with Backend

Use the exported functions in your Spring Boot backend:

```javascript
const { sendIncomingCall, sendCallCancel } = require('./fcm-test-script');

// In your call initiation endpoint
await sendIncomingCall(userFcmToken, callId, callerName);

// In your call cancellation endpoint  
await sendCallCancel(userFcmToken, callId);
```

## 📞 Next Steps

After FCM testing works:
1. Integrate with your Spring Boot signaling server
2. Add FCM sending to your call initiation endpoint
3. Handle call states (ringing, connected, ended)
4. Add timeout handling
5. Test network reconnection scenarios

---

**Need help?** Check the console logs and compare with expected messages above.
