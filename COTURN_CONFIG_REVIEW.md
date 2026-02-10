# 🔍 Coturn Configuration Review

## ✅ Overall Assessment: **GOOD** with minor recommendations

Your configuration is **correct and production-ready** with proper security measures. Below is a detailed analysis:

---

## 📋 Configuration Analysis

### ✅ Core Settings (CORRECT)

```conf
listening-port=3478          ✅ Standard TURN port
tls-listening-port=5349      ✅ Standard TLS/DTLS port
external-ip=60.70.80.91      ✅ Your public IP configured
relay-ip=60.70.80.91         ✅ Matches external IP
realm=yourdomain.com         ✅ Set (should be your actual domain)
```

### ✅ Authentication (CORRECT)

```conf
lt-cred-mech                 ✅ Long-term credentials enabled
user=myuser:mypassword       ✅ User configured
```

**⚠️ IMPORTANT:** Change default credentials before production:
- `myuser:mypassword` → Use strong, unique credentials
- Consider using hashed passwords (see below)

### ✅ Security Settings (EXCELLENT)

```conf
fingerprint                  ✅ TURN message fingerprints enabled
no-multicast-peers           ✅ Blocks broadcast addresses
no-rfc5780                   ✅ Reduces amplification attack risk
no-stun-backward-compatibility ✅ Disables old STUN protocol
response-origin-only-with-rfc5780 ✅ Reduces response size
```

These are **excellent security choices** that:
- Prevent DDoS amplification attacks
- Block access to multicast addresses
- Reduce attack surface

### ✅ Port Range (CORRECT)

```conf
min-port=49152               ✅ IANA recommended range
max-port=65535               ✅ Maximum ephemeral port
```

### ✅ Logging (CORRECT)

```conf
verbose                      ✅ Good for debugging
log-file=/var/log/turnserver.log ✅ Proper log location
syslog                       ✅ System logging enabled
```

---

## 🔧 Recommendations

### 1. **Change Default Credentials (HIGH PRIORITY)**

Current:
```conf
user=myuser:mypassword
```

**Option A:** Use clear password (less secure)
```conf
user=scancall_user:Str0ng!P@ssw0rd#2025
```

**Option B:** Use hashed key (more secure - RECOMMENDED)
```bash
# Generate hashed credential
turnadmin -k -u scancall_user -r yourdomain.com -p Str0ng!P@ssw0rd#2025

# Output example:
# 0xbc807ee29df3c9ffa736523fb2c4e8ee

# Then use in config:
user=scancall_user:0xbc807ee29df3c9ffa736523fb2c4e8ee
```

### 2. **Update Realm (MEDIUM PRIORITY)**

Current:
```conf
realm=yourdomain.com
```

Recommended:
```conf
# If you have a domain:
realm=scancall.yourdomain.com

# If using IP only:
realm=60.70.80.91
```

**Note:** The realm MUST match in your Flutter app!

### 3. **Add TLS Certificates (for production)**

If you want encrypted TURN (TURNS protocol):
```conf
# Uncomment and configure:
cert=/etc/letsencrypt/live/yourdomain.com/fullchain.pem
pkey=/etc/letsencrypt/live/yourdomain.com/privkey.pem
```

Get free certificates:
```bash
# Install certbot
sudo apt install certbot

# Get certificate
sudo certbot certonly --standalone -d yourdomain.com
```

### 4. **Firewall Rules (CRITICAL)**

Make sure your firewall allows TURN traffic:
```bash
# UFW (Ubuntu)
sudo ufw allow 3478/tcp
sudo ufw allow 3478/udp
sudo ufw allow 5349/tcp
sudo ufw allow 5349/udp
sudo ufw allow 49152:65535/tcp
sudo ufw allow 49152:65535/udp

# Or iptables
sudo iptables -A INPUT -p tcp --dport 3478 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 3478 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 5349 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 5349 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 49152:65535 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 49152:65535 -j ACCEPT
```

### 5. **Set Resource Limits (RECOMMENDED)**

Add these to prevent abuse:
```conf
# Maximum bytes per second per session (10 Mbps)
max-bps=10000000

# Total allocation quota (100 simultaneous sessions)
total-quota=100

# Per-user quota (5 sessions per user)
user-quota=5

# Max allocation lifetime (1 hour)
max-allocate-lifetime=3600
```

---

## 🚀 Quick Setup Steps

### Step 1: Save Configuration

```bash
# Save your config to coturn config file
sudo nano /etc/turnserver.conf

# Paste your configuration
# Save and exit (Ctrl+X, Y, Enter)
```

### Step 2: Enable and Start Coturn

```bash
# Enable coturn to start on boot
sudo systemctl enable coturn

# Start the service
sudo systemctl start coturn

# Check status
sudo systemctl status coturn
```

### Step 3: Generate Secure Credentials

```bash
# Install turnadmin if not available
sudo apt install coturn

# Generate hashed password
turnadmin -k -u your_username -r yourdomain.com -p your_strong_password

# Copy the output (starts with 0x...)
# Update /etc/turnserver.conf with the hash
sudo nano /etc/turnserver.conf

# Find the user= line and update:
user=your_username:0x[generated_hash]

# Restart coturn
sudo systemctl restart coturn
```

### Step 4: Test TURN Server

```bash
# Install testing tools
sudo apt install coturn-utils

# Test UDP
turnutils_uclient -v -u your_username -w your_password 60.70.80.91

# Expected output: "SUCCESS" messages
```

### Step 5: Update Flutter App

Edit `lib/services/signaling_service.dart`:

```dart
final Map<String, dynamic> _iceServers = {
  'iceServers': [
    {'urls': 'stun:stun.l.google.com:19302'},
    {
      'urls': [
        'turn:60.70.80.91:3478?transport=udp',
        'turn:60.70.80.91:3478?transport=tcp',
      ],
      'username': 'your_username',  // Same as in coturn config
      'credential': 'your_password', // Same as in coturn config (NOT the hash!)
    }
  ]
};
```

**⚠️ IMPORTANT:** In Flutter app, use the **original password**, not the hash!

### Step 6: Update Web Client

Edit `web_client/caller.html` (around line 162):

```javascript
const ICE_SERVERS = {
  iceServers: [
    { urls: 'stun:stun.l.google.com:19302' },
    {
      urls: [
        'turn:60.70.80.91:3478?transport=udp',
        'turn:60.70.80.91:3478?transport=tcp'
      ],
      username: 'your_username',
      credential: 'your_password'
    }
  ]
};
```

---

## 🧪 Testing Your Configuration

### Test 1: Check Service Status

```bash
sudo systemctl status coturn
# Expected: ● coturn.service - Coturn TURN Server
#          Loaded: loaded
#          Active: active (running)
```

### Test 2: Check Logs

```bash
sudo tail -f /var/log/turnserver.log
# Expected: No ERROR messages
# Look for: "Listener XX on IP YY:3478 ready..."
```

### Test 3: Test with Online Tool

1. Visit: https://webrtc.github.io/samples/src/content/peerconnection/trickle-ice/
2. Add TURN server:
   - **TURN URI:** `turn:60.70.80.91:3478`
   - **Username:** `your_username`
   - **Password:** `your_password`
3. Click "Gather candidates"
4. Look for candidates with `type: relay` (means TURN works!)

### Test 4: Test in Your App

```dart
// Add logging in signaling_service.dart
_peerConnection!.onIceCandidate = (candidate) {
  print('🧊 ICE Candidate: ${candidate.candidate}');
  print('   Type: ${candidate.type}');
  print('   Protocol: ${candidate.protocol}');
  
  // If you see "typ relay" in candidate string, TURN is working!
  _sendIceCandidate(candidate);
};
```

---

## 🔐 Security Checklist

- [x] ✅ Long-term credentials enabled (`lt-cred-mech`)
- [ ] ⚠️ Change default username/password
- [x] ✅ Fingerprinting enabled
- [x] ✅ Multicast peers blocked
- [x] ✅ RFC5780 disabled (security)
- [x] ✅ Old STUN compatibility disabled
- [ ] 🔲 Add resource limits (max-bps, quotas)
- [ ] 🔲 Add TLS certificates for TURNS
- [ ] 🔲 Configure firewall rules
- [ ] 🔲 Use hashed passwords instead of cleartext
- [ ] 🔲 Test TURN server functionality

---

## 🎯 Final Configuration Template (Production-Ready)

```conf
# Coturn TURN SERVER configuration file
#

# Listening ports
listening-port=3478
tls-listening-port=5349

# External IP (your server's public IP)
external-ip=60.70.80.91

# Relay IP (usually same as external IP)
relay-ip=60.70.80.91

# Realm (your domain or IP)
realm=scancall.yourdomain.com

# Authentication
lt-cred-mech

# Strong credentials (use turnadmin to generate hash)
user=scancall_prod:0xYOUR_GENERATED_HASH_HERE

# Logging
verbose
log-file=/var/log/turnserver.log
syslog

# Security
fingerprint
no-multicast-peers
no-rfc5780
no-stun-backward-compatibility
response-origin-only-with-rfc5780

# Port range
min-port=49152
max-port=65535

# Resource limits
max-bps=10000000
total-quota=100
user-quota=5
max-allocate-lifetime=3600

# TLS certificates (for TURNS)
# cert=/etc/letsencrypt/live/yourdomain.com/fullchain.pem
# pkey=/etc/letsencrypt/live/yourdomain.com/privkey.pem
```

---

## 📞 Troubleshooting

### Problem: Service won't start

```bash
# Check configuration syntax
sudo turnserver -c /etc/turnserver.conf --check-config

# Check logs
sudo journalctl -u coturn -n 50
```

### Problem: Firewall blocking

```bash
# Test if port is open
nc -zv 60.70.80.91 3478

# Check listening ports
sudo netstat -tulpn | grep 3478
```

### Problem: TURN not being used

```bash
# Check if relay candidates are generated
# In Flutter app logs, look for: "typ relay"
# If you only see "typ host" or "typ srflx", TURN isn't working
```

### Problem: Authentication failing

```bash
# Verify credentials match in:
# 1. /etc/turnserver.conf
# 2. Flutter app (signaling_service.dart)
# 3. Web client (caller.html)

# Test with turnutils
turnutils_uclient -v -u USERNAME -w PASSWORD 60.70.80.91
```

---

## ✅ Summary

**Your configuration is CORRECT!** 

### What's Good:
✅ Proper port configuration  
✅ External IP set correctly  
✅ Security features enabled  
✅ Authentication configured  

### Before Production:
1. ⚠️ Change `myuser:mypassword` to strong credentials
2. ⚠️ Update `realm=yourdomain.com` to your actual domain/IP
3. ⚠️ Configure firewall rules
4. ⚠️ Add resource limits
5. ⚠️ Test with `turnutils_uclient`

### Next Steps:
1. Save config to `/etc/turnserver.conf`
2. Generate secure credentials with `turnadmin`
3. Start service: `sudo systemctl start coturn`
4. Update Flutter app with credentials
5. Test with WebRTC ICE test tool

---

**Need help?** Check these resources:
- Coturn documentation: https://github.com/coturn/coturn
- Your project guide: `TURN_SERVER_CONFIG.md`
- WebRTC samples: https://webrtc.github.io/samples/

