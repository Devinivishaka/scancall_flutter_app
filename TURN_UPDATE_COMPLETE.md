# ✅ TURN Server Configuration - UPDATE COMPLETE

## 📍 Location of Changes

I've updated **2 files** with your TURN server configuration:

---

## 1️⃣ Flutter App (Mobile Receiver)

**File:** `lib/services/signaling_service.dart`  
**Lines:** 18-37

### ✅ What Was Changed:

```dart
final Map<String, dynamic> _iceServers = {
  'iceServers': [
    // Public STUN servers (free to use)
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},

    // Production TURN server (Coturn on 60.70.80.91)
    // ⚠️ IMPORTANT: Change 'myuser' and 'mypassword' to your actual credentials
    {
      'urls': [
        'turn:60.70.80.91:3478?transport=udp',
        'turn:60.70.80.91:3478?transport=tcp',
      ],
      'username': 'myuser',
      'credential': 'mypassword',
    }
  ]
};
```

**Status:** ✅ Updated with your public IP `60.70.80.91`

---

## 2️⃣ Web Client (Browser Caller)

**File:** `web_client/caller.html`  
**Lines:** 227-239

### ✅ What Was Changed:

```javascript
const ICE_SERVERS = {
  iceServers: [
    { urls: 'stun:stun.l.google.com:19302' },
    {
      urls: [
        'turn:60.70.80.91:3478?transport=udp',
        'turn:60.70.80.91:3478?transport=tcp'
      ],
      username: 'myuser', // ⚠️ Change to your actual TURN username
      credential: 'mypassword' // ⚠️ Change to your actual TURN password
    }
  ]
};
```

**Status:** ✅ Updated with your public IP `60.70.80.91`

---

## ⚠️ IMPORTANT: Update Credentials

Both files currently use placeholder credentials:
- **Username:** `myuser`
- **Password:** `mypassword`

### Before Testing, You MUST:

1. **Update Coturn config** with secure credentials:
   ```bash
   # Generate secure hash
   turnadmin -k -u scancall_user -r yourdomain.com -p YourSecurePassword123!
   
   # Output: 0xABCDEF123456...
   
   # Edit coturn config
   sudo nano /etc/turnserver.conf
   
   # Update:
   user=scancall_user:0xABCDEF123456...
   
   # Restart coturn
   sudo systemctl restart coturn
   ```

2. **Update Flutter app** (`lib/services/signaling_service.dart` line 34-35):
   ```dart
   'username': 'scancall_user',
   'credential': 'YourSecurePassword123!', // Use CLEAR password, NOT hash
   ```

3. **Update Web client** (`web_client/caller.html` line 235-236):
   ```javascript
   username: 'scancall_user',
   credential: 'YourSecurePassword123!' // Use CLEAR password, NOT hash
   ```

---

## 🚀 Next Steps

### Step 1: Test Current Configuration (with default credentials)

```powershell
# 1. Start signaling server
cd signaling_server
npm start

# 2. Run Flutter app
flutter run

# 3. Open web client
# Open web_client/caller.html in browser

# 4. Make a test call
```

**Expected:** Should work if your Coturn is running with `myuser:mypassword`

### Step 2: Secure Your Credentials (Production)

Follow the credential update steps above.

### Step 3: Verify TURN is Working

Check Flutter app logs for:
```
🧊 ICE Candidate: candidate:... typ relay ...
```

The word `relay` means TURN server is being used! ✅

---

## 🧪 Test TURN Server Status

```bash
# Check if coturn is running
sudo systemctl status coturn

# Test TURN connectivity
turnutils_uclient -v -u myuser -w mypassword 60.70.80.91

# Expected output:
# ...
# 0: Total connect time is 0
# 0: Total lost packets 0 (0.000000%), total send dropped 0 (0.000000%)
# 0: Average round trip delay 25.000000 ms
# 0: Total message send errors 0
# 0: Success rate is 100.000000%
```

---

## 📊 Configuration Summary

| Component | File | Status | IP Address | Port |
|-----------|------|--------|------------|------|
| **Flutter App** | `lib/services/signaling_service.dart` | ✅ Updated | 60.70.80.91 | 3478 |
| **Web Client** | `web_client/caller.html` | ✅ Updated | 60.70.80.91 | 3478 |
| **Coturn Server** | `/etc/turnserver.conf` | ⚠️ Update credentials | 60.70.80.91 | 3478 |

---

## 🔒 Security Reminder

### Current State (INSECURE):
```
username: myuser
password: mypassword
```

### Production State (SECURE):
```
username: scancall_prod_user_2025
password: S3cur3!P@ssw0rd#WebRTC$2025
```

**Action Required:** Change credentials before production deployment!

---

## ✅ What to Test

### Test 1: Local Network (Same WiFi)
- Should work with just STUN (TURN not needed)
- Check logs - should see `typ host` or `typ srflx`

### Test 2: Different Networks
- **This is where TURN is needed!**
- Mobile on 4G/5G, Web on WiFi (or vice versa)
- Check logs - should see `typ relay` 

### Test 3: Behind Firewall
- Corporate network, strict firewall
- TURN will relay all traffic
- Higher latency but guaranteed connectivity

---

## 🎯 Quick Verification Checklist

- [x] ✅ Flutter app updated with TURN config
- [x] ✅ Web client updated with TURN config
- [ ] ⚠️ Coturn credentials changed from defaults
- [ ] ⚠️ Flutter app credentials updated
- [ ] ⚠️ Web client credentials updated
- [ ] 🔲 Coturn service running
- [ ] 🔲 Firewall ports opened (3478, 5349, 49152-65535)
- [ ] 🔲 Tested with turnutils_uclient
- [ ] 🔲 Tested actual call across different networks

---

## 📞 Need Help?

### Check Coturn Logs:
```bash
sudo tail -f /var/log/turnserver.log
```

### Check Flutter Logs:
```
flutter run
# Look for ICE candidate logs
```

### Common Issues:

**TURN not working?**
- Check firewall: `sudo ufw status`
- Check coturn status: `sudo systemctl status coturn`
- Check credentials match in all 3 locations

**Calls fail across networks?**
- This means TURN isn't relaying - check config
- Verify ports 49152-65535 UDP are open
- Test with: `turnutils_uclient -v -u USER -w PASS IP`

**Authentication errors?**
- Credentials must match exactly
- Use CLEAR password in Flutter/Web (not hash)
- Use HASH in coturn config (or clear password)

---

## 🎉 Summary

**Your TURN server configuration is now set in both Flutter app and web client!**

**Next:** 
1. Update credentials from defaults (`myuser:mypassword`)
2. Start coturn service
3. Test connectivity
4. Make calls across different networks

**Files Modified:**
- ✅ `lib/services/signaling_service.dart`
- ✅ `web_client/caller.html`

**Ready to test!** 🚀
