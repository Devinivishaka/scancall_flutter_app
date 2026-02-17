# FCM (Firebase Cloud Messaging) Setup & Troubleshooting Guide

## 🔥 Current Firebase Configuration

**Project:** scancall-f8c81  
**Package Name:** co.protonestiot.scancall_mobile_app  
**App ID:** 1:1009964498010:android:b1f3ad1a92d75e19616c63

---

## ✅ Setup Checklist

### 1. **Verify google-services.json**
- ✅ Located at: `android/app/google-services.json`
- ✅ Package name matches: `co.protonestiot.scancall_mobile_app`
- ✅ Project ID: `scancall-f8c81`

### 2. **Build Configuration**
- ✅ Google Services plugin applied in `android/app/build.gradle.kts`
- ✅ Build script dependency added in `android/build.gradle.kts`

### 3. **AndroidManifest Permissions**
Required permissions for FCM and incoming calls:
```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.WAKE_LOCK"/>
<uses-permission android:name="android.permission.VIBRATE" />
```

### 4. **Flutter Dependencies**
```yaml
firebase_core: ^4.4.0
firebase_messaging: ^16.1.1
```

---

## 🧪 Testing FCM

### Step 1: Run the App and Get FCM Token

```bash
flutter clean
flutter pub get
flutter run
```

**Look for this in the console output:**
```
═══════════════════════════════════════════════════════════
✅ FCM TOKEN RETRIEVED
═══════════════════════════════════════════════════════════
Token: eXaMpLe_ToKeN_HeRe...
═══════════════════════════════════════════════════════════
```

**Copy this token!** You'll need it for testing.

---

### Step 2: Send Test Notification Using cURL

**Option A: Using Firebase REST API v1 (Recommended)**

First, get your access token from Firebase Console:
1. Go to: https://console.firebase.google.com/project/scancall-f8c81/settings/serviceaccounts/adminsdk
2. Click "Generate new private key"
3. Use the service account JSON to get an OAuth2 token

Then send the message:
```bash
curl -X POST https://fcm.googleapis.com/v1/projects/scancall-f8c81/messages:send \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "message": {
      "token": "YOUR_FCM_TOKEN_HERE",
      "data": {
        "type": "incoming_call",
        "callId": "test-call-123",
        "callerName": "John Doe",
        "callerId": "+1234567890",
        "isVideo": "false"
      },
      "android": {
        "priority": "high"
      }
    }
  }'
```

**Option B: Using Legacy Server Key (Simpler for testing)**

Get your Server Key:
1. Go to: https://console.firebase.google.com/project/scancall-f8c81/settings/cloudmessaging
2. Enable "Cloud Messaging API (Legacy)"
3. Copy the "Server key"

```bash
curl -X POST https://fcm.googleapis.com/fcm/send \
  -H "Authorization: key=YOUR_SERVER_KEY_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "to": "YOUR_FCM_TOKEN_HERE",
    "priority": "high",
    "data": {
      "type": "incoming_call",
      "callId": "test-call-123",
      "callerName": "John Doe",
      "callerId": "+1234567890",
      "isVideo": "false"
    }
  }'
```

**PowerShell Version:**
```powershell
$headers = @{
    "Authorization" = "key=YOUR_SERVER_KEY_HERE"
    "Content-Type" = "application/json"
}

$body = @{
    to = "YOUR_FCM_TOKEN_HERE"
    priority = "high"
    data = @{
        type = "incoming_call"
        callId = "test-call-$(Get-Date -Format 'yyyyMMddHHmmss')"
        callerName = "Test Caller"
        callerId = "+1234567890"
        isVideo = "false"
    }
} | ConvertTo-Json -Depth 10

Invoke-RestMethod -Uri "https://fcm.googleapis.com/fcm/send" -Method POST -Headers $headers -Body $body
```

---

## 🔍 Troubleshooting

### Issue 1: App Not Receiving FCM Messages

**Check List:**
1. ✅ **Google Play Services installed?**
   - Run on a physical device OR
   - Use an Android emulator with "Google Play" system image (not "Google APIs")

2. ✅ **Internet connection active?**
   ```bash
   adb shell ping -c 3 8.8.8.8
   ```

3. ✅ **FCM token is not null?**
   - If token is null, Google Play Services is not working
   - Check console logs for errors

4. ✅ **Notification permissions granted?**
   - Android 13+: App must request POST_NOTIFICATIONS permission
   - Check: Settings > Apps > Your App > Notifications

5. ✅ **Battery optimization disabled?**
   - Android may kill background apps
   - Settings > Apps > Your App > Battery > Unrestricted

---

### Issue 2: FCM Token is NULL

**Possible Causes:**
- ❌ Emulator doesn't have Google Play Services
- ❌ google-services.json is missing or incorrect
- ❌ Package name mismatch between app and Firebase console
- ❌ No internet connection
- ❌ Firebase SDK not properly initialized

**Solutions:**
1. **Use correct emulator:**
   - Open Android Studio > AVD Manager
   - Create/Use device with "Google Play" image (has Play Store icon)
   - NOT "Google APIs" (doesn't have Play Store)

2. **Verify google-services.json:**
   ```bash
   cat android/app/google-services.json | grep package_name
   ```
   Should show: `"package_name": "co.protonestiot.scancall_mobile_app"`

3. **Rebuild completely:**
   ```bash
   flutter clean
   cd android
   ./gradlew clean
   cd ..
   flutter pub get
   flutter run
   ```

---

### Issue 3: Messages Received but CallKit Not Showing

**Check:**
1. ✅ **Data payload format correct?**
   - Must include: `type`, `callId`, `callerName`
   - Check console logs for payload received

2. ✅ **CallKit permissions?**
   - Android: Display over other apps permission
   - Settings > Apps > Your App > Display over other apps

3. ✅ **Console shows "Showing incoming call UI"?**
   - If yes but no UI: Check permissions
   - If no: Check data payload format

---

### Issue 4: Only Works in Foreground, Not Background

**Check:**
1. ✅ **Background handler registered?**
   ```dart
   FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
   ```
   This MUST be called before `runApp()`

2. ✅ **Handler is top-level function?**
   - Must be outside any class
   - Must have `@pragma('vm:entry-point')` annotation

3. ✅ **Sending data-only messages?**
   - DO NOT include "notification" field in FCM payload
   - Only use "data" field
   ```json
   {
     "to": "token...",
     "data": { ... }  // ✅ Good
     // NO "notification" field!
   }
   ```

---

## 📱 Testing Scenarios

### Scenario 1: App in Foreground
**Expected:** `FirebaseMessaging.onMessage` triggered → Shows incoming call UI

### Scenario 2: App in Background
**Expected:** `_firebaseMessagingBackgroundHandler` triggered → Shows incoming call UI

### Scenario 3: App Terminated
**Expected:** `_firebaseMessagingBackgroundHandler` triggered → Shows incoming call UI

### Scenario 4: User Taps Notification
**Expected:** `FirebaseMessaging.onMessageOpenedApp` triggered → Shows incoming call UI

---

## 🐛 Debug Commands

```bash
# Check if Google Play Services is available
adb shell dumpsys package com.google.android.gms | grep -i version

# Check app permissions
adb shell dumpsys package co.protonestiot.scancall_mobile_app | grep -i permission

# View Firebase logs
adb logcat | grep -i firebase

# View FCM logs
adb logcat | grep -i "FCM\|FirebaseMessaging"

# Check notification settings
adb shell dumpsys notification | grep co.protonestiot.scancall_mobile_app
```

---

## 📝 Console Log Interpretation

### ✅ Success Logs
```
✅ Firebase initialized successfully
✅ Notification permission status: AuthorizationStatus.authorized
✅ FCM TOKEN RETRIEVED
Token: eXaMpLe...
```

### ⚠️ Warning Logs
```
⚠️ FCM token is null
⚠️ User granted provisional permission
```

### ❌ Error Logs
```
❌ Firebase initialization failed
❌ FAILED TO GET FCM TOKEN
❌ Error in onMessage listener
```

---

## 🔗 Useful Links

- Firebase Console: https://console.firebase.google.com/project/scancall-f8c81
- Cloud Messaging Settings: https://console.firebase.google.com/project/scancall-f8c81/settings/cloudmessaging
- Service Accounts: https://console.firebase.google.com/project/scancall-f8c81/settings/serviceaccounts/adminsdk

---

## 📞 Support

If issues persist after following this guide:
1. Check Flutter doctor: `flutter doctor -v`
2. Check Android SDK: Ensure SDK 33+ installed
3. Review complete console logs
4. Verify Firebase project settings match app configuration
