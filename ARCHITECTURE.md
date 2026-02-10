# 📚 Code Architecture & Explanation

This document explains how the WebRTC call application works under the hood.

## 🏗️ Architecture Overview

The application follows a clean, layered architecture:

```
┌─────────────────────────────────────────┐
│          UI Layer (Screens)              │
│         call_screen.dart                 │
└─────────────────┬───────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│       Service Layer (Business Logic)     │
│       signaling_service.dart             │
└─────────────────┬───────────────────────┘
                  │
         ┌────────┴────────┐
         ▼                 ▼
┌─────────────────┐  ┌──────────────────┐
│  flutter_webrtc │  │ web_socket       │
│  (WebRTC SDK)   │  │ (Signaling)      │
└─────────────────┘  └──────────────────┘
```

## 📂 File Structure Explained

### 1. `lib/main.dart`
**Purpose:** Application entry point

```dart
void main() {
  runApp(const MyApp()); // Starts the Flutter app
}
```

- Initializes the Flutter app
- Sets up MaterialApp with theme
- Routes to CallScreen

**Key Components:**
- `MyApp` widget: Root application widget
- Material design theme configuration
- Navigation setup

---

### 2. `lib/screens/call_screen.dart`
**Purpose:** User interface and user interaction logic

**Responsibilities:**
- Display call UI (buttons, status indicators)
- Handle user actions (call button, end call)
- Request permissions (microphone)
- Listen to call state changes
- Update UI based on call state

**Key Methods:**

```dart
_initializeService()      // Set up SignalingService and listeners
_requestPermissions()     // Ask for microphone access
_startCall()              // Initiate a call
_endCall()                // Terminate the call
_getStatusText()          // Convert state to user-friendly text
```

**State Management:**
- Uses `StatefulWidget` for reactive UI
- Streams for real-time updates
- Call state enum tracking

---

### 3. `lib/services/signaling_service.dart`
**Purpose:** Core WebRTC and signaling logic

**Responsibilities:**
- Manage WebRTC peer connection
- Handle WebSocket signaling
- Media stream management
- ICE candidate exchange
- SDP offer/answer handling

**Key Components:**

#### A. WebSocket Communication
```dart
connectToSignalingServer()  // Establish WebSocket connection
_handleSignalingMessage()   // Process incoming messages
_sendMessage()              // Send messages to server
```

#### B. WebRTC Peer Connection
```dart
initialize()                // Create RTCPeerConnection
startCall()                 // Create offer and get media
_handleAnswer()             // Process remote SDP answer
_handleIceCandidate()       // Add remote ICE candidates
```

#### C. Media Management
```dart
getUserMedia()              // Get microphone/camera access
addTrack()                  // Add local media to peer connection
onTrack()                   // Receive remote media
```

**Call State Enum:**
```dart
enum CallState {
  idle,        // Ready to call
  connecting,  // Establishing connection
  connected,   // Active call
  ended,       // Call terminated
  error        // Something went wrong
}
```

---

## 🔄 Call Flow Deep Dive

### Phase 1: Initialization
```
User Opens App
    ↓
SignalingService.initialize()
    ↓
Create RTCPeerConnection with ICE servers
    ↓
Set up event listeners (onIceCandidate, onTrack, onConnectionState)
    ↓
UI shows "Ready to call"
```

### Phase 2: Starting a Call
```
User Taps "Call Web"
    ↓
Request Microphone Permission
    ↓
Connect to WebSocket Server
    ↓
Send "join" message with room name
    ↓
getUserMedia() - Get local audio stream
    ↓
addTrack() - Add audio to peer connection
    ↓
createOffer() - Generate SDP offer
    ↓
setLocalDescription() - Set own SDP
    ↓
Send "offer" message via WebSocket
```

### Phase 3: Signaling Exchange
```
Web Client Receives Offer
    ↓
Web Client Creates Answer
    ↓
Web Client Sends Answer
    ↓
Mobile Receives "answer" message
    ↓
setRemoteDescription() - Set remote SDP
    ↓
Both sides exchange ICE candidates
    ↓
addCandidate() - Add remote ICE candidates
```

### Phase 4: Connection Establishment
```
ICE Negotiation
    ↓
STUN Server queries for public IP
    ↓
TURN Server relay if needed
    ↓
Find best connection path
    ↓
onConnectionState: "connected"
    ↓
Audio flows directly between peers
```

### Phase 5: Ending a Call
```
User Taps "End Call"
    ↓
Stop all media tracks
    ↓
Close peer connection
    ↓
Send "leave" message
    ↓
Close WebSocket
    ↓
Update UI to "Call ended"
```

---

## 🌐 Signaling Server (`signaling_server/server.js`)

**Purpose:** Relay signaling messages between peers

**Key Features:**
- Room-based connections
- Message forwarding
- Connection management

**Message Types:**
| Type | Direction | Purpose |
|------|-----------|---------|
| `join` | Client → Server | Join a call room |
| `joined` | Server → Client | Confirm room joined |
| `offer` | Mobile → Server → Web | Send SDP offer |
| `answer` | Web → Server → Mobile | Send SDP answer |
| `ice-candidate` | Both → Server → Other | Exchange ICE |
| `leave` | Client → Server | Leave room |
| `error` | Server → Client | Error notification |

**Room Management:**
```javascript
rooms = Map {
  'test-call': Set [ws1, ws2, ...]
}
```

---

## 🎨 Web Client (`web_client/index.html`)

**Purpose:** Receive and answer calls from mobile

**Key Features:**
- Auto-answer incoming calls
- Display connection status
- Show real-time logs
- Audio playback

**WebRTC Setup:**
```javascript
1. Connect to signaling server
2. Join room "test-call"
3. Wait for offer
4. Create RTCPeerConnection
5. setRemoteDescription(offer)
6. createAnswer()
7. setLocalDescription(answer)
8. Send answer
9. Exchange ICE candidates
10. Play remote audio stream
```

---

## 🔐 Permissions (Android)

**Manifest Permissions:**
```xml
INTERNET           - WebSocket and WebRTC
RECORD_AUDIO       - Microphone access
CAMERA             - Video calls (optional)
MODIFY_AUDIO       - Audio routing
ACCESS_NETWORK     - Connection monitoring
```

**Runtime Permissions:**
Handled by `permission_handler` package in `call_screen.dart`:
```dart
await Permission.microphone.request();
```

---

## 🧩 Key Technologies Explained

### WebRTC (Web Real-Time Communication)
- **Peer-to-peer** audio/video streaming
- **Low latency** (<200ms)
- **NAT traversal** via STUN/TURN
- **Built-in** codec negotiation

### ICE (Interactive Connectivity Establishment)
- Discovers connection paths
- Tests multiple routes
- Selects optimal path
- Handles NAT/firewall issues

### STUN (Session Traversal Utilities for NAT)
- Discovers public IP address
- Maps local/public ports
- Enables direct connections

### TURN (Traversal Using Relays around NAT)
- Relay server for difficult networks
- Fallback when P2P fails
- Ensures call always works

### SDP (Session Description Protocol)
- Describes media capabilities
- Lists supported codecs
- Defines network parameters
- Exchanged in offer/answer

---

## 📊 State Management Flow

```
CallState.idle
    ↓ (user taps "Call Web")
CallState.connecting
    ↓ (WebRTC negotiation)
CallState.connected
    ↓ (user taps "End Call" OR remote hangs up)
CallState.ended
    ↓ (can call again)
CallState.idle

    (any time)
    ↓ (error occurs)
CallState.error
```

**State Changes Trigger:**
- UI updates (button states, colors, icons)
- Status text changes
- Audio playback start/stop
- Permission requests

---

## 🔍 Debugging Tips

### Enable Verbose Logging

**In Flutter:**
```dart
print('Debug: $message');
```

**In Browser:**
```javascript
console.log('Debug:', data);
```

### Check WebRTC Stats
```dart
peerConnection.getStats().then((stats) {
  print(stats);
});
```

### Monitor ICE Candidates
```dart
peerConnection.onIceCandidate = (candidate) {
  print('ICE Candidate: ${candidate.candidate}');
};
```

### WebSocket Messages
All messages are logged in:
- Signaling server console
- Web client log panel
- Flutter debug console

---

## 🎯 Design Decisions

### Why Hard-Coded Room Name?
**Decision:** Use single room "test-call"
**Reason:** Simplifies MVP, no room management needed
**Production:** Use QR codes or dynamic room generation

### Why Audio-Only Default?
**Decision:** Video disabled by default
**Reason:** Simpler permissions, lower bandwidth, easier testing
**Enable:** Change `'video': false` to `true`

### Why WebSocket for Signaling?
**Decision:** Use WebSocket instead of HTTP polling
**Reason:** Real-time, bidirectional, efficient
**Alternative:** Could use Firebase, Socket.io, or HTTP long-polling

### Why Separate Signaling Server?
**Decision:** Node.js WebSocket server
**Reason:** Simple, minimal, no external dependencies
**Production:** Use scalable service (Firebase, AWS, etc.)

---

## 🚀 Performance Considerations

### Bandwidth Usage
- **Audio only:** ~50-100 Kbps
- **With video (720p):** ~1-2 Mbps
- **TURN relay:** +10-20% overhead

### Latency Sources
- Network RTT: 20-100ms
- Audio encoding: 20-40ms
- Jitter buffer: 20-200ms
- Total: 60-340ms typical

### Connection Quality
Best to worst:
1. **Direct P2P** (same network)
2. **STUN-assisted P2P** (different networks)
3. **TURN relay** (fallback)

---

## 📝 Code Conventions

### Naming
- **Classes:** PascalCase (`SignalingService`)
- **Variables:** camelCase (`_localStream`)
- **Constants:** SCREAMING_SNAKE_CASE (`ROOM_NAME`)
- **Private:** Leading underscore (`_handleMessage`)

### File Organization
- One class per file
- Related logic grouped
- Public methods first
- Private methods last

### Comments
- Explain **why**, not **what**
- Document complex logic
- Add TODO for improvements

---

## 🧪 Testing Strategy

### Unit Tests
Test individual methods:
```dart
test('SignalingService creates offer', () async {
  final service = SignalingService();
  await service.initialize();
  // Test offer creation
});
```

### Integration Tests
Test complete flow:
```dart
testWidgets('Call flow end-to-end', (tester) async {
  // Simulate full call lifecycle
});
```

### Manual Testing
1. Local network test
2. Different networks test
3. Slow connection test
4. Permission denial test
5. Mid-call interruption test

---

## 🔄 Future Enhancements

### Short Term
- [ ] Add call duration timer
- [ ] Show network quality indicators
- [ ] Implement reconnection logic
- [ ] Add mute/unmute button

### Medium Term
- [ ] Video calling support
- [ ] Screen sharing
- [ ] Chat during call
- [ ] Call recording

### Long Term
- [ ] Group calling (3+ participants)
- [ ] End-to-end encryption
- [ ] AI noise cancellation
- [ ] Virtual backgrounds

---

## 📖 Further Reading

- [WebRTC API Documentation](https://webrtc.org/)
- [Flutter WebRTC Plugin](https://pub.dev/packages/flutter_webrtc)
- [MDN WebRTC Guide](https://developer.mozilla.org/en-US/docs/Web/API/WebRTC_API)
- [STUN/TURN Server Setup](https://github.com/coturn/coturn)

---

**Questions?** Check the main README.md or open an issue!
