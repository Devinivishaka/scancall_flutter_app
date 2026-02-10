# 📞 Incoming Call with Accept/Reject Buttons

## ✨ What Changed?

The mobile app now shows **incoming call notifications** with **Accept** and **Reject** buttons instead of auto-answering!

## 🎯 New Call Flow

```
1. Mobile app waits for calls → Shows "Waiting for call..."
2. Web caller initiates call → Sends offer
3. Mobile receives offer → Shows INCOMING CALL screen 📞
4. User sees:
   ✅ "INCOMING CALL" text
   ✅ Orange phone icon
   ✅ "From: Web Caller"
   ✅ Two buttons: REJECT (red) | ACCEPT (green)
5. User taps ACCEPT → Call connects
   OR
   User taps REJECT → Call is declined, returns to waiting
```

## 🖼️ UI Layout

```
┌─────────────────────────────────┐
│     WebRTC Receiver             │
├─────────────────────────────────┤
│                                 │
│        [Phone Icon              │
│         (Orange)]               │
│                                 │
│     📞 INCOMING CALL            │
│                                 │
│     From: Web Caller            │
│                                 │
│                                 │
│   [🔴]          [🟢]           │
│  REJECT        ACCEPT           │
│                                 │
└─────────────────────────────────┘
```

## 🔄 Complete Call Sequence

### Before Accept

```
Web Caller                     Mobile Receiver
    │                               │
    │ Clicks "Call Mobile"          │
    │──────────────────────────────>│
    │                               │
    │                          📞 INCOMING CALL!
    │                          (Shows Accept/Reject)
    │                               │
    │ Waiting for answer...         │
    │                          [User sees UI]
    │                               │
```

### After User Taps Accept

```
Web Caller                     Mobile Receiver
    │                               │
    │                          User taps ACCEPT ✅
    │                               │
    │                          Processing...
    │ <─────────────────────────────│
    │   Answer received!            │
    │                               │
    │ ✅ Call connected!       ✅ Call connected!
    │                               │
    │ ────── Audio Stream ─────────>│
    │                               │
```

### If User Taps Reject

```
Web Caller                     Mobile Receiver
    │                               │
    │                          User taps REJECT ❌
    │                               │
    │ <─────────────────────────────│
    │   Rejection message           │
    │                               │
    │ ❌ Call rejected         Back to waiting...
    │                               │
```

## 🎨 Button Design

### Accept Button (Green)
- **Shape:** Circular
- **Icon:** Phone (call icon)
- **Color:** Green (#4CAF50)
- **Action:** Accepts the call
- **Label:** "Accept"

### Reject Button (Red)
- **Shape:** Circular
- **Icon:** Phone hangup (call_end icon)
- **Color:** Red (#F44336)
- **Action:** Rejects the call
- **Label:** "Reject"

## 🧪 Testing the Feature

### Step 1: Run Mobile App

```powershell
flutter run
```

**Expected:** App shows "Waiting for call..."

### Step 2: Make a Call from Web

Open `web_client/caller.html` and click "📞 Call Mobile App"

### Step 3: Observe Mobile App

You should see:
- ✅ Screen changes to show "📞 INCOMING CALL"
- ✅ Orange phone icon at the top
- ✅ "From: Web Caller" text
- ✅ Two circular buttons at the bottom

### Step 4: Test Accept

Tap the **green Accept button**:
- ✅ Call connects immediately
- ✅ Status changes to "Connected"
- ✅ You hear audio from web caller
- ✅ "End Call" button appears

### Step 5: Test Reject (New Call)

Make another call from web, then tap the **red Reject button**:
- ✅ Incoming call screen disappears
- ✅ Shows "Call rejected" briefly
- ✅ Returns to "Waiting for call..."
- ✅ Web caller sees rejection (connection fails)

## 📱 State Management

| State | Screen Display | User Action Available |
|-------|----------------|----------------------|
| `waiting` | "Waiting for call..." | None - just waiting |
| `incoming` | "📞 INCOMING CALL" | Accept or Reject buttons |
| `connecting` | "Connecting..." | None - processing |
| `connected` | "✅ Call connected" | End Call button |
| `ended` | "Call ended" | None - returns to waiting |

## 🎯 Code Changes Made

### 1. SignalingService (`signaling_service.dart`)

**Added:**
- `_pendingOffer` - Stores offer until user accepts
- `acceptCall()` - Processes offer when user taps Accept
- `rejectCall()` - Declines offer when user taps Reject

**Modified:**
- `_handleSignalingMessage()` - No longer auto-processes offer
- Offer is now stored and waits for user action

### 2. CallScreen (`call_screen.dart`)

**Added:**
- `_acceptCall()` - Handles Accept button tap
- `_rejectCall()` - Handles Reject button tap
- Incoming call UI with Accept/Reject buttons
- Circular button design for Accept/Reject

**Modified:**
- `_showIncomingCallUI` logic updated
- Better state management for incoming calls

**Fixed:**
- Removed problematic animation that caused UI duplication
- Clean, single display of incoming call notification

## 🔔 Future Enhancements

Want to make it even better? Add these features:

### 1. Ringtone
```dart
import 'package:audioplayers/audioplayers.dart';

final player = AudioPlayer();
// Play when call arrives
await player.play(AssetSource('ringtone.mp3'));
// Stop when accepted/rejected
await player.stop();
```

### 2. Vibration
```dart
import 'package:vibration/vibration.dart';

// Vibrate pattern when call arrives
Vibration.vibrate(pattern: [500, 1000, 500, 1000], repeat: 0);
// Stop when accepted/rejected
Vibration.cancel();
```

### 3. Notification
```dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Show notification even when app is in background
await flutterLocalNotificationsPlugin.show(
  0,
  'Incoming Call',
  'Web Caller is calling...',
  NotificationDetails(/* ... */),
);
```

### 4. Full-Screen Call UI
```dart
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

// Native iOS/Android incoming call screen
await FlutterCallkitIncoming.showCallkitIncoming(/* ... */);
```

### 5. Caller Information
Display actual caller name/ID:
- Modify web caller to send caller info
- Display in UI: "From: John Doe"
- Show avatar/profile picture

### 6. Call Timer
Show duration after accepting:
```dart
Timer? _callTimer;
int _callDuration = 0;

// Start timer on accept
_callTimer = Timer.periodic(Duration(seconds: 1), (timer) {
  setState(() => _callDuration++);
});

// Display: "00:${_callDuration}"
```

## ✅ Summary

**Before:** Auto-answer (no user control)
- Call arrives → Automatically answered → Connected

**After:** Manual accept/reject (user has control)
- Call arrives → User sees notification → User decides → Action taken

**Benefits:**
- ✅ User has control over incoming calls
- ✅ Can reject unwanted calls
- ✅ Better user experience
- ✅ More realistic phone behavior
- ✅ Prevents accidental call acceptance

---

**Ready to test?** Run the app and make a call from the web client to see the new incoming call UI! 📞✨
