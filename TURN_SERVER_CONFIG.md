# 🔧 TURN Server Configuration Guide

## 📋 Understanding STUN vs TURN

### STUN (Session Traversal Utilities for NAT)
- **Purpose:** Discovers your public IP address
- **When needed:** Almost always
- **Cost:** Free (public servers available)
- **Use case:** Works for most scenarios on same/similar networks

### TURN (Traversal Using Relays around NAT)
- **Purpose:** Relays traffic when direct connection fails
- **When needed:** Different networks, strict firewalls, corporate networks
- **Cost:** Bandwidth costs (relays all traffic)
- **Use case:** Production apps, guaranteed connectivity

## 🏠 For Local Testing (Same WiFi)

**You DON'T need TURN!** STUN is sufficient.

### Current Configuration (Already Set)

```dart
final Map<String, dynamic> _iceServers = {
  'iceServers': [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
  ]
};
```

**This works when:**
- ✅ Mobile device and web browser on same WiFi
- ✅ No strict firewall blocking UDP
- ✅ Testing/development environment

**Test it:**
```powershell
# 1. Start signaling server
cd signaling_server
npm start

# 2. Run mobile app
flutter run

# 3. Open web caller
# Open web_client/caller.html

# 4. Make a call - should work without TURN!
```

---

## 🌐 For Production (Different Networks)

If you need calls to work across different networks, you need a TURN server.

## Option 1: Install Your Own TURN Server (Coturn)

### Step 1: Install Coturn on Ubuntu/Debian Server

```bash
# Update system
sudo apt update
sudo apt install coturn -y

# Enable coturn
sudo systemctl enable coturn
```

### Step 2: Configure Coturn

Edit `/etc/turnserver.conf`:

```bash
sudo nano /etc/turnserver.conf
```

Add this configuration:

```conf
# Listening port
listening-port=3478
tls-listening-port=5349

# External IP (your server's public IP)
external-ip=YOUR_PUBLIC_IP

# Relay IP (usually same as external IP)
relay-ip=YOUR_PUBLIC_IP

# Realm (your domain or IP)
realm=yourdomain.com

# Authentication
lt-cred-mech
user=myuser:mypassword

# Logging
verbose
log-file=/var/log/turnserver.log

# Security
fingerprint
no-multicast-peers

# Ports
min-port=49152
max-port=65535
```

### Step 3: Start Coturn

```bash
# Start the service
sudo systemctl start coturn

# Check status
sudo systemctl status coturn

# View logs
sudo tail -f /var/log/turnserver.log
```

### Step 4: Update Flutter App

```dart
final Map<String, dynamic> _iceServers = {
  'iceServers': [
    {'urls': 'stun:stun.l.google.com:19302'},
    {
      'urls': [
        'turn:YOUR_PUBLIC_IP:3478?transport=udp',
        'turn:YOUR_PUBLIC_IP:3478?transport=tcp',
      ],
      'username': 'myuser',
      'credential': 'mypassword',
    }
  ]
};
```

### Step 5: Update Web Client

Edit `web_client/caller.html` (line ~162):

```javascript
const ICE_SERVERS = {
  iceServers: [
    { urls: 'stun:stun.l.google.com:19302' },
    {
      urls: [
        'turn:YOUR_PUBLIC_IP:3478?transport=udp',
        'turn:YOUR_PUBLIC_IP:3478?transport=tcp'
      ],
      username: 'myuser',
      credential: 'mypassword'
    }
  ]
};
```

---

## Option 2: Use Free TURN Server (Testing Only)

**Warning:** These are public test servers - NOT for production!

### Metered.ca (Free Tier Available)

1. Visit https://www.metered.ca/tools/openrelay/
2. Get free TURN server credentials

```dart
final Map<String, dynamic> _iceServers = {
  'iceServers': [
    {'urls': 'stun:stun.relay.metered.ca:80'},
    {
      'urls': 'turn:a.relay.metered.ca:80',
      'username': 'provided_by_metered',
      'credential': 'provided_by_metered',
    },
  ]
};
```

### Xirsys (Free Trial)

1. Sign up at https://xirsys.com/
2. Get credentials from dashboard

```dart
final Map<String, dynamic> _iceServers = {
  'iceServers': [
    {'urls': 'stun:stun.l.google.com:19302'},
    {
      'urls': 'turn:global.turn.twilio.com:3478?transport=udp',
      'username': 'your_xirsys_username',
      'credential': 'your_xirsys_credential',
    }
  ]
};
```

---

## Option 3: Cloud TURN Services (Production)

### Twilio Network Traversal Service

**Best for production apps**

1. Sign up at https://www.twilio.com/
2. Get Network Traversal Service credentials
3. Pricing: Pay per GB of relayed traffic

```dart
// Get credentials dynamically from your backend
final response = await http.post('https://your-backend.com/get-turn-credentials');
final iceServers = jsonDecode(response.body);
```

### AWS CloudFront + Custom TURN

Host your own TURN server on AWS EC2 with CloudFront for global distribution.

---

## 🧪 Testing Your TURN Server

### Test from Command Line

```bash
# Install turnutils
sudo apt install coturn-utils

# Test TURN server
turnutils_uclient -v -u myuser -w mypassword YOUR_PUBLIC_IP
```

### Test in Browser

Visit: https://webrtc.github.io/samples/src/content/peerconnection/trickle-ice/

1. Add your TURN server details
2. Click "Gather candidates"
3. Look for `relay` type candidates (means TURN is working)

### Check Flutter App Logs

```dart
peerConnection!.onIceCandidate = (candidate) {
  print('ICE Candidate Type: ${candidate.type}');
  // Look for "relay" type - means TURN is being used
  _sendIceCandidate(candidate);
};
```

---

## 🔒 Security Best Practices

### 1. Use Long-Term Credentials

Don't hardcode passwords in app! Generate temporary credentials:

```dart
// Backend API generates time-limited credentials
Future<Map<String, dynamic>> getTurnCredentials() async {
  final response = await http.get('https://your-api.com/turn-credentials');
  return jsonDecode(response.body);
}

// Use in app
final credentials = await getTurnCredentials();
_iceServers = {
  'iceServers': [
    {'urls': 'stun:stun.l.google.com:19302'},
    credentials['turnServer'], // Includes username, credential, urls
  ]
};
```

### 2. Restrict Access

In coturn config:

```conf
# Only allow specific users
user=user1:password1
user=user2:password2

# Limit by IP range
allowed-peer-ip=192.168.1.0-192.168.1.255

# Set quota
max-bps=1000000
```

### 3. Use TLS

```conf
# In coturn
tls-listening-port=5349
cert=/path/to/certificate.pem
pkey=/path/to/private-key.pem
```

```dart
// In Flutter app
{
  'urls': 'turns:YOUR_SERVER:5349', // Note: 'turns' not 'turn'
  'username': 'user',
  'credential': 'pass',
}
```

---

## 📊 When TURN is Actually Used

```
Scenario 1: Same WiFi
Mobile ←──────────────→ Web
     (Direct P2P via STUN)
     ✅ TURN NOT used

Scenario 2: Different Networks, Good NAT
Mobile ←─────STUN─────→ Web
     (Direct P2P hole punching)
     ✅ TURN NOT used

Scenario 3: Strict Firewall
Mobile ──→ TURN Server ──→ Web
     (Traffic relayed through TURN)
     🔄 TURN USED (costs bandwidth)
```

---

## 🎯 Quick Setup for Your Current Project

### For Local Testing (NOW)

**No changes needed!** Your app is already configured correctly:

```dart
// Already set in signaling_service.dart
'iceServers': [
  {'urls': 'stun:stun.l.google.com:19302'},
  {'urls': 'stun:stun1.l.google.com:19302'},
]
```

Just run:
```powershell
cd signaling_server ; npm start
flutter run
# Open web_client/caller.html
```

### For Production (LATER)

1. Set up Coturn on a server (follow Option 1 above)
2. Get public IP and credentials
3. Uncomment TURN section in `signaling_service.dart`
4. Replace placeholders with actual values

---

## ❓ FAQ

### Q: Do I need TURN for local testing?
**A:** No! STUN is enough when devices are on the same WiFi.

### Q: Why is TURN expensive?
**A:** Because ALL media (audio/video) flows through the server, using bandwidth.

### Q: Can I use free public TURN servers?
**A:** For testing only. They're unreliable and shared with others.

### Q: How do I know if TURN is being used?
**A:** Check ICE candidates - look for `type: "relay"` in logs.

### Q: My call works locally but not remotely?
**A:** You need TURN! One or both sides are behind strict NAT/firewall.

---

## 📞 Support

**Current Status:** ✅ Your app is configured for local testing
**Next Step:** Test locally first, add TURN only if needed for production

---

**Summary:** For your current local testing with `ws://192.168.1.31:8080`, the Google STUN servers are perfect. You don't need TURN unless you're deploying to production!
