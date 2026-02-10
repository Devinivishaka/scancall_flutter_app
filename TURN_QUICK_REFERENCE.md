# ⚡ Quick TURN Setup - Cheat Sheet

## 🏠 Local Testing (What You Need NOW)

### ✅ Current Configuration (Already Done!)

Your `signaling_service.dart` is already set up correctly:

```dart
final Map<String, dynamic> _iceServers = {
  'iceServers': [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
  ]
};
```

### ✅ Testing Steps

```powershell
# Terminal 1: Start signaling server
cd D:\Projects\scancall_mobile_app\signaling_server
npm start

# Terminal 2: Run mobile app
cd D:\Projects\scancall_mobile_app
flutter run

# Browser: Open web caller
# Open: D:\Projects\scancall_mobile_app\web_client\caller.html
# Click "Call Mobile App"
```

**✅ This works because:**
- Both devices on same WiFi (192.168.1.x)
- Google's free STUN servers handle NAT
- No TURN needed for local network!

---

## 🌐 Production Setup (When You Need It)

### When Do You Need TURN?
- ❌ **NOT for local testing** (same WiFi)
- ✅ **YES for production** (different networks)
- ✅ **YES for strict firewalls**
- ✅ **YES for mobile data ↔ WiFi calls**

### Quick Coturn Setup (Ubuntu/Debian)

```bash
# 1. Install
sudo apt update && sudo apt install coturn -y

# 2. Configure
sudo nano /etc/turnserver.conf

# Add these lines:
listening-port=3478
external-ip=YOUR_PUBLIC_IP
realm=yourdomain.com
lt-cred-mech
user=testuser:testpass123
fingerprint

# 3. Start
sudo systemctl enable coturn
sudo systemctl start coturn

# 4. Test
turnutils_uclient -v -u testuser -w testpass123 YOUR_PUBLIC_IP
```

### Update Flutter App

Uncomment the TURN section in `signaling_service.dart`:

```dart
final Map<String, dynamic> _iceServers = {
  'iceServers': [
    {'urls': 'stun:stun.l.google.com:19302'},
    {
      'urls': [
        'turn:YOUR_PUBLIC_IP:3478?transport=udp',
        'turn:YOUR_PUBLIC_IP:3478?transport=tcp',
      ],
      'username': 'testuser',
      'credential': 'testpass123',
    }
  ]
};
```

---

## 🆓 Free TURN for Testing

### Option 1: Metered.ca

```dart
// Get free credentials from: https://www.metered.ca/tools/openrelay/
{
  'urls': 'turn:a.relay.metered.ca:80',
  'username': 'openrelayproject',
  'credential': 'openrelayproject',
}
```

### Option 2: Numb.viagenie.ca

```dart
{
  'urls': 'turn:numb.viagenie.ca',
  'username': 'webrtc@live.com',
  'credential': 'muazkh',
}
```

⚠️ **Warning:** These are public test servers. Don't use for real apps!

---

## 🧪 Testing If TURN is Working

### Method 1: Check Logs

```dart
// Add to signaling_service.dart onIceCandidate callback:
peerConnection!.onIceCandidate = (candidate) {
  print('🔍 Candidate type: ${candidate.type}'); 
  // "relay" = TURN is working!
  // "srflx" = STUN only
  // "host" = Local IP
  _sendIceCandidate(candidate);
};
```

### Method 2: Browser Test Tool

1. Visit: https://webrtc.github.io/samples/src/content/peerconnection/trickle-ice/
2. Add your TURN server
3. Click "Gather candidates"
4. Look for `typ relay` in results

---

## 📋 Configuration Matrix

| Scenario | STUN | TURN | Cost |
|----------|------|------|------|
| Local WiFi Testing | ✅ | ❌ | Free |
| Same ISP (NAT-friendly) | ✅ | ❌ | Free |
| Different Networks (moderate NAT) | ✅ | Maybe | Free-$$$ |
| Strict Firewall / Mobile Data | ✅ | ✅ Required | $$$ |
| Production App | ✅ | ✅ Recommended | $$$ |

---

## 🔧 Common Issues

### "Connection failed" on local WiFi
```
❌ Problem: TURN server not reachable
✅ Solution: Remove TURN, use STUN only (already configured!)
```

### "Works locally, fails remotely"
```
❌ Problem: Need TURN server
✅ Solution: Install Coturn or use cloud service
```

### "relay candidates not appearing"
```
❌ Problem: TURN credentials wrong or firewall blocking
✅ Solution: Check coturn logs: sudo tail -f /var/log/turnserver.log
```

---

## 🎯 Your Current Status

✅ **Configured:** STUN-only (perfect for local testing)  
✅ **Signaling Server:** ws://192.168.1.31:8080  
✅ **Ready to test:** Yes!  
❌ **TURN needed:** Not yet (only for production)

## 🚀 Next Steps

1. **NOW:** Test locally with current STUN-only config
2. **LATER:** If deploying to production, set up TURN server
3. **ADVANCED:** Use dynamic TURN credentials from backend API

---

**Need More Details?** See `TURN_SERVER_CONFIG.md` for complete guide!
