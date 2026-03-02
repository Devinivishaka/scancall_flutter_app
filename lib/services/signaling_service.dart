import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:vibration/vibration.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class SignalingService {

  static const String _signalingServerUrl = 'ws://192.168.1.31:8080/ws';
  static const String _backendBaseUrl = 'http://192.168.1.31:8080';

  // Room name equals the device's userId — resolved on first connectAndWaitForCalls() call.
  // Using your own userId as the room name lets the web caller target you directly.
  String _roomName = '';

  // Hard-coded TURN/STUN configuration
  //
  // CONNECTION METHODS (in order of preference):
  // 1. HOST candidates: Direct connection on same local network (NO TURN NEEDED)
  //    - Used when both devices are on same WiFi/LAN
  //    - Fastest and most reliable
  //    - Your current setup is likely using this!
  //
  // 2. SRFLX candidates: Connection via STUN server (NO TURN NEEDED)
  //    - Used when devices can connect directly but need to know public IP
  //    - STUN helps discover the public IP address
  //    - Still a direct peer-to-peer connection
  //
  // 3. RELAY candidates: Connection via TURN server (TURN NEEDED)
  //    - Only used when direct connection is impossible
  //    - Required when behind strict NAT/firewalls
  //    - More latency and uses TURN server bandwidth
  //
  // If your call works without TURN server running, you're using HOST or SRFLX!
  // Check the logs to see which ICE candidate types are being used.
  final Map<String, dynamic> _iceServers = {
    'iceServers': [
      // Local STUN server
      {'urls': 'stun:13.127.40.12:3478'},

      // Local TURN server
      {
        'urls': [
          'turn:13.127.40.12:3478?transport=udp',
          'turn:13.127.40.12:3478?transport=tcp',
        ],
        'username': 'myuser',
        'credential': 'mypassword',
      }
    ]
  };

  // WebSocket channel
  WebSocketChannel? _channel;

  // WebRTC peer connection
  RTCPeerConnection? _peerConnection;

  // Local media stream (our audio/video)
  MediaStream? _localStream;

  // Remote media stream (incoming audio/video)
  MediaStream? _remoteStream;

  // Store pending offer when call comes in
  Map<String, dynamic>? _pendingOffer;

  // Queue for ICE candidates that arrive before remote description is set
  final List<Map<String, dynamic>> _pendingIceCandidates = [];
  bool _remoteDescriptionSet = false;

  // Flag to track if we're currently reconnecting
  bool _isReconnecting = false;

  // Flag to track ringtone state
  bool _isRingtonePlaying = false;

  // Flag to track vibration state
  bool _isVibrating = false;

  // Flag to track if we're in an active call
  bool _isInCall = false;

  // Current call type: 'audio' or 'video'
  String _callType = 'video';

  // Cached RTCRtpSender for the video track.
  // Must be stored explicitly because after replaceTrack(null) the sender's
  // track becomes null, so searching getSenders() by track.kind == 'video'
  // will never find it again — causing a duplicate addTrack on re-enable.
  RTCRtpSender? _videoSender;

  // Stream controllers for callbacks
  final _onCallStateChanged = StreamController<CallState>.broadcast();
  final _onRemoteStream = StreamController<MediaStream>.broadcast();
  final _onLocalStream = StreamController<MediaStream>.broadcast();
  final _onIncomingCall = StreamController<void>.broadcast();
  /// Emits the confirmed new call type ('audio' or 'video') whenever it changes
  final _onCallTypeChanged = StreamController<String>.broadcast();
  /// Emits the requested call type when the remote side asks to switch
  final _onChangeTypeRequest = StreamController<String>.broadcast();

  // Getters
  Stream<CallState> get onCallStateChanged => _onCallStateChanged.stream;
  Stream<MediaStream> get onRemoteStream => _onRemoteStream.stream;
  Stream<MediaStream> get onLocalStream => _onLocalStream.stream;
  Stream<void> get onIncomingCall => _onIncomingCall.stream;
  Stream<String> get onCallTypeChanged => _onCallTypeChanged.stream;
  Stream<String> get onChangeTypeRequest => _onChangeTypeRequest.stream;
  MediaStream? get remoteStream => _remoteStream;
  MediaStream? get localStream => _localStream;
  String get callType => _callType;

  /// Initialize the signaling service
  Future<void> initialize() async {
    try {
      // Log ICE server configuration
      print('🌐 Initializing WebRTC with ICE servers:');
      final servers = _iceServers['iceServers'] as List;
      for (var server in servers) {
        if (server is Map) {
          if (server.containsKey('urls')) {
            final urls = server['urls'];
            if (urls is List) {
              for (var url in urls) {
                print('   - $url');
              }
            } else {
              print('   - $urls');
            }
            if (server.containsKey('username')) {
              print('     Username: ${server['username']}');
            }
          }
        }
      }

      // Create peer connection
      _peerConnection = await createPeerConnection(_iceServers);

      // Set up peer connection callbacks
      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        final candidateStr = candidate.candidate ?? '';
        print('🧊 ICE Candidate generated: $candidateStr');

        // Log candidate type for debugging
        if (candidateStr.contains('typ host')) {
          print('   ✅ Type: HOST - Direct local network connection (no TURN needed!)');
        } else if (candidateStr.contains('typ srflx')) {
          print('   ✅ Type: SRFLX - STUN server reflexive (using public IP, no TURN needed!)');
        } else if (candidateStr.contains('typ relay')) {
          print('   🔄 Type: RELAY - Using TURN server (different networks)');
        } else if (candidateStr.contains('typ prflx')) {
          print('   ✅ Type: PRFLX - Peer reflexive (discovered during connectivity checks)');
        }

        _sendIceCandidate(candidate);
      };

      // Monitor ICE connection state
      _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
        print('🔌 ICE Connection State: $state');
        switch (state) {
          case RTCIceConnectionState.RTCIceConnectionStateNew:
            print('   ICE: New - Starting ICE checks');
            break;
          case RTCIceConnectionState.RTCIceConnectionStateChecking:
            print('   ICE: Checking - Testing connectivity');
            print('   ℹ️  Trying: HOST → SRFLX → RELAY (in order of preference)');
            break;
          case RTCIceConnectionState.RTCIceConnectionStateConnected:
            print('   ✅ ICE: Connected - Media can flow!');
            print('   ℹ️  Connection established using one of: HOST, SRFLX, or RELAY candidates');
            print('   ℹ️  If TURN server is stopped and this works, you\'re using HOST/SRFLX!');
            break;
          case RTCIceConnectionState.RTCIceConnectionStateCompleted:
            print('   ✅ ICE: Completed - All checks done');
            break;
          case RTCIceConnectionState.RTCIceConnectionStateFailed:
            print('   ❌ ICE: Failed - Connection cannot be established');
            print('   ⚠️  None of the connection methods worked (HOST, SRFLX, RELAY)');
            print('   ⚠️  If you need TURN but it\'s down, this will fail!');
            print('   ℹ️  Check: 1) Same network? 2) STUN reachable? 3) TURN needed & running?');
            break;
          case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
            print('   ⚠️ ICE: Disconnected - Temporarily lost connection');
            break;
          case RTCIceConnectionState.RTCIceConnectionStateClosed:
            print('   ICE: Closed');
            break;
          default:
            break;
        }
      };

      // Monitor ICE gathering state
      _peerConnection!.onIceGatheringState = (RTCIceGatheringState state) {
        print('🔍 ICE Gathering State: $state');
        switch (state) {
          case RTCIceGatheringState.RTCIceGatheringStateNew:
            print('   Gathering: New');
            break;
          case RTCIceGatheringState.RTCIceGatheringStateGathering:
            print('   Gathering: In progress...');
            break;
          case RTCIceGatheringState.RTCIceGatheringStateComplete:
            print('   ✅ Gathering: Complete - All candidates found');
            break;
        }
      };

      _peerConnection!.onTrack = (RTCTrackEvent event) {
        print('🎥 Received remote ${event.track.kind} track');
        print('   - Track ID: ${event.track.id}');
        print('   - Track enabled: ${event.track.enabled}');

        if (event.streams.isNotEmpty) {
          // Get the first stream
          final stream = event.streams[0];

          // Enable the track
          event.track.enabled = true;

          // Update or set the remote stream
          if (_remoteStream == null || _remoteStream!.id != stream.id) {
            _remoteStream = stream;
            print('✅ New remote stream: ${stream.id}');
            print('   - Video tracks: ${_remoteStream!.getVideoTracks().length}');
            print('   - Audio tracks: ${_remoteStream!.getAudioTracks().length}');

            // Notify UI about the stream
            _onRemoteStream.add(_remoteStream!);
          } else {
            print('✅ Track added to existing stream');
            // Still notify UI in case it's a new track type
            _onRemoteStream.add(_remoteStream!);
          }
        } else {
          print('⚠️ No streams in track event');
        }
      };

      _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
        print('Connection state: $state');
        switch (state) {
          case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
            _onCallStateChanged.add(CallState.connected);
            break;
          case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
            _onCallStateChanged.add(CallState.ended);
            break;
          case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
            _onCallStateChanged.add(CallState.connecting);
            break;
          default:
            break;
        }
      };

      print('SignalingService initialized (Receiver Mode)');
    } catch (e) {
      print('Error initializing SignalingService: $e');
      rethrow;
    }
  }

  /// Connect to the signaling server and wait for incoming calls.
  /// Uses the device's persisted userId as the room name so the web caller
  /// can target this device by room = userId.
  Future<void> connectAndWaitForCalls() async {
    try {
      _onCallStateChanged.add(CallState.waiting);

      // Resolve userId first — this also ensures a UUID is generated on first run
      final userId = await getUserId();
      _roomName = userId;
      print('📡 Joining room: $_roomName (= userId)');

      _channel = WebSocketChannel.connect(Uri.parse(_signalingServerUrl));

      // Listen for messages from the signaling server
      _channel!.stream.listen(
        (message) {
          _handleSignalingMessage(message);
        },
        onError: (error) {
          print('WebSocket error: $error');
          _onCallStateChanged.add(CallState.error);
        },
        onDone: () {
          print('WebSocket closed');
          // Don't set to ended here - let the app handle reconnection
        },
      );

      // Join the room (room == userId so the web can address us)
      _sendMessage({
        'type': 'join',
        'room': _roomName,
        'calleeId': userId,
      });

      print('Connected to signaling server - Waiting for calls...');
    } catch (e) {
      print('Error connecting to signaling server: $e');
      _onCallStateChanged.add(CallState.error);
      rethrow;
    }
  }

  /// Register/refresh the device FCM token with the backend.
  /// Creates the device record if it does not exist yet.
  Future<void> registerFcmToken(String fcmToken) async {
    try {
      final userId = await getUserId();
      final url = Uri.parse('$_backendBaseUrl/users/$userId/device-token');
      // Use dart:io HttpClient to avoid adding extra dependencies
      final client = HttpClient();
      final request = await client.postUrl(url);
      request.headers.set('Content-Type', 'application/json');
      final body = jsonEncode({'token': fcmToken, 'platform': 'android'});
      request.write(body);
      final response = await request.close();
      final statusCode = response.statusCode;
      if (statusCode == 200 || statusCode == 201) {
        print('✅ FCM token registered with backend for userId=$userId');
      } else {
        print('⚠️ FCM token registration returned HTTP $statusCode for userId=$userId');
      }
      client.close();
    } catch (e) {
      print('⚠️ Could not register FCM token with backend: $e');
      // Non-fatal — app continues; push notifications may not work
    }
  }

  /// Handle incoming signaling messages
  void _handleSignalingMessage(dynamic message) async {
    try {
      final data = jsonDecode(message);
      final type = data['type'];

      print('Received message: $type');

      switch (type) {
        case 'offer':
          if (_isInCall) {
            // This is a renegotiation offer (e.g., after call type change)
            print('🔄 Renegotiation offer received (call type change)');
            final newCallType = (data['callType'] as String?)?.toLowerCase() ?? 'video';
            print('   📱 New call type: $newCallType');

            // Handle the offer for renegotiation (don't show incoming call UI)
            await _handleRenegotiationOffer(data['sdp'], newCallType);
          } else {
            // This is a new incoming call
            print('📞 INCOMING CALL!');
            _pendingOffer = data['sdp']; // Store the offer
            // Parse call type sent by caller (default to video)
            _callType = (data['callType'] as String?)?.toLowerCase() == 'audio' ? 'audio' : 'video';
            print('   📱 Call type: $_callType');
            _onCallStateChanged.add(CallState.incoming);
            _onIncomingCall.add(null); // Notify UI

            // Play ringtone
            await _playRingtone();
          }
          break;
        case 'ice-candidate':
          await _handleIceCandidate(data['candidate']);
          break;
        case 'answer':
          // Remote side sent an answer (to our offer)
          print('📥 Received answer from remote peer');
          await _handleAnswer(data['sdp']);
          break;
        case 'call-accepted':
          // Remote side accepted the call
          print('✅ Remote side accepted the call');
          _onCallStateChanged.add(CallState.connecting);
          break;
        case 'call-ended':
          // Remote side ended the call
          print('📵 Remote side ended the call');
          await _handleRemoteEndCall();
          break;
        case 'call-rejected':
          // Remote side rejected the call
          print('❌ Remote side rejected the call');
          _onCallStateChanged.add(CallState.ended);
          break;
        case 'joined':
          print('Joined room: $_roomName - Ready to receive calls');
          break;
        case 'error':
          print('Signaling error: ${data['message']}');
          _onCallStateChanged.add(CallState.error);
          break;
        case 'change-type':
          // Remote side requests to switch call type
          final requestedType = (data['callType'] as String?)?.toLowerCase() ?? 'audio';
          print('🔄 Remote side requests call type change → $requestedType');
          _onChangeTypeRequest.add(requestedType);
          break;
        case 'change-type-accepted':
          // Remote side (web) confirmed it accepted our type-switch request.
          // Web is always the offerer — it will now send a renegotiation offer.
          // We just update our internal callType and wait for the incoming offer.
          final confirmedType = (data['callType'] as String?)?.toLowerCase() ?? 'audio';
          print('✅ Remote side accepted call type change → $confirmedType');
          _callType = confirmedType;
          print('   ⏳ Waiting for renegotiation offer from web...');
          break;
        default:
          print('Unknown message type: $type');
      }
    } catch (e) {
      print('Error handling signaling message: $e');
    }
  }

  /// Accept incoming call (called when user taps Accept button)
  Future<void> acceptCall() async {
    if (_pendingOffer == null) {
      print('No pending offer to accept');
      return;
    }

    try {
      print('Accepting call...');

      // Stop ringtone
      await _stopRingtone();

      // Get local media (audio and video) FIRST
      print('Requesting camera and microphone access...');

      try {
        // Request audio always. Request video only for video calls.
        // Keep video constraints simple — overly specific constraints
        // (width/height/frameRate max) can make getUserMedia throw on many
        // Android devices.
        final mediaConstraints = <String, dynamic>{
          'audio': {
            'echoCancellation': true,
            'noiseSuppression': true,
          },
          'video': _callType == 'video'
              ? {'facingMode': 'user'}
              : false,
        };

        _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      } catch (e) {
        print('❌ Failed to get camera/microphone: $e');
        print('⚠️ Make sure camera and microphone permissions are granted');
        _onCallStateChanged.add(CallState.error);
        rethrow;
      }

      print('✅ Got local audio/video stream');
      print('   - Video tracks: ${_localStream!.getVideoTracks().length}');
      print('   - Audio tracks: ${_localStream!.getAudioTracks().length}');

      // Enable video tracks
      for (var track in _localStream!.getVideoTracks()) {
        track.enabled = true;
        print('   - Video track enabled: ${track.id}');
      }

      _onLocalStream.add(_localStream!);

      // Add local tracks to peer connection BEFORE handling offer.
      // Store the video sender so we can replaceTrack on it during type switch.
      for (final track in _localStream!.getTracks()) {
        final sender = await _peerConnection!.addTrack(track, _localStream!);
        if (track.kind == 'video') _videoSender = sender;
        print('✅ Added ${track.kind} track to peer connection');
      }

      // Notify the other side that we accepted
      _sendMessage({
        'type': 'call-accepted',
        'room': _roomName,
        'calleeId': getUserId()
      });

      // Now handle the offer and create answer
      await _handleOffer(_pendingOffer!);
      _pendingOffer = null; // Clear pending offer

      // Mark that we're now in an active call
      _isInCall = true;
      print('✅ Call accepted - now in active call');
    } catch (e) {
      print('❌ Error accepting call: $e');
      _onCallStateChanged.add(CallState.error);
    }
  }

  /// Reject incoming call (called when user taps Reject button)
  Future<void> rejectCall() async {
    if (_pendingOffer == null) {
      print('No pending offer to reject');
      return;
    }

    try {
      print('Rejecting call...');

      // Stop ringtone
      await _stopRingtone();

      // Clear pending offer
      _pendingOffer = null;

      // Send rejection message to caller
      _sendMessage({
        'type': 'reject',
        'room': _roomName,
        'calleeId': getUserId()
      });

      // Reset to waiting state
      _onCallStateChanged.add(CallState.waiting);

      print('Call rejected');
    } catch (e) {
      print('Error rejecting call: $e');
    }
  }

  /// Create and send a renegotiation offer after call type change is accepted
  Future<void> _createAndSendRenegotiationOffer(String newCallType) async {
    try {
      print('🔄 Creating renegotiation offer for call type: $newCallType');

      // Apply the new call type locally
      _applyCallTypeLocally(newCallType);

      // No mandatory constraints — let transceivers drive direction.
      RTCSessionDescription offer = await _peerConnection!.createOffer({});

      // Set local description
      await _peerConnection!.setLocalDescription(offer);
      print('✅ Local description (renegotiation offer) set');

      // Send the offer
      _sendMessage({
        'type': 'offer',
        'room': _roomName,
        'sdp': {
          'type': offer.type,
          'sdp': offer.sdp,
        },
        'callType': newCallType,
        'calleeId': getUserId(),
      });

      print('✅ Renegotiation offer sent - call type: $newCallType');
    } catch (e) {
      print('❌ Error creating renegotiation offer: $e');
    }
  }

  /// Locally apply a call type change by enabling/disabling video tracks
  void _applyCallTypeLocally(String newType) {
    if (_localStream == null) return;
    final enable = newType == 'video';
    for (var track in _localStream!.getVideoTracks()) {
      track.enabled = enable;
      print('${enable ? '🎥' : '🔇'} Local video track ${enable ? 'enabled' : 'disabled'}: ${track.id}');
    }
    // Remote video tracks
    if (_remoteStream != null) {
      for (var track in _remoteStream!.getVideoTracks()) {
        track.enabled = enable;
        print('${enable ? '🎥' : '🔇'} Remote video track ${enable ? 'enabled' : 'disabled'}: ${track.id}');
      }
    }
    print('✅ Call type locally applied: $newType');
  }

  /// Request a call-type change (audio ↔ video).
  /// Sends a change-type request. When remote accepts, we'll create and send
  /// a new offer for renegotiation.
  Future<void> requestChangeCallType(String newType) async {
    print('🔄 Requesting call type change → $newType');
    try {
      if (newType == 'video') {
        await _ensureVideoTrack();
      } else {
        await _removeVideoTracks();
      }
    } catch (e) {
      print('⚠️ Could not prepare tracks for type change request: $e');
    }
    _sendMessage({
      'type': 'change-type',
      'room': _roomName,
      'callType': newType,
      'calleeId': getUserId(),
    });
  }

  /// Accept a change-type request from the remote peer.
  /// [pendingType] should be the value received via onChangeTypeRequest.
  /// Sends change-type-accept. The actual media change will happen when we receive
  /// the renegotiation offer from the remote peer.
  Future<void> acceptChangeCallType(String pendingType) async {
    print('✅ Accepting call type change → $pendingType');

    try {
      if (pendingType == 'video') {
        // Switching to video: prepare video track
        await _ensureVideoTrack();
      } else {
        // Switching to audio: prepare to remove video
        await _removeVideoTracks();
      }
    } catch (e) {
      print('⚠️ Error preparing tracks for type switch: $e');
    }

    // Send acceptance - remote will then send a renegotiation offer
    _sendMessage({
      'type': 'change-type-accept',
      'room': _roomName,
      'callType': pendingType,
      'calleeId': getUserId(),
    });

    print('   ⏳ Waiting for renegotiation offer from remote...');
  }

  /// Ensure a live video track exists and is wired to the peer connection.
  Future<void> _ensureVideoTrack() async {
    if (_peerConnection == null) return;

    // Only skip if _localStream already has a live (not-stopped, enabled) track.
    // Stopped tracks are removed from _localStream by _removeVideoTracks, so
    // this check is reliable and won't return early with a dead ghost track.
    final existingVideoTracks = _localStream?.getVideoTracks() ?? [];
    if (existingVideoTracks.isNotEmpty && existingVideoTracks.first.enabled) {
      print('🎥 Video track already live — nothing to do');
      return;
    }

    print('📷 Acquiring new video track...');
    try {
      final videoStream = await navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': {'facingMode': 'user'},
      });

      final newVideoTrack = videoStream.getVideoTracks().first;
      newVideoTrack.enabled = true;

      if (_videoSender != null) {
        // We already have a sender (track was nulled during audio switch).
        // replaceTrack is the correct operation — avoids duplicate m=video sections.
        await _videoSender!.replaceTrack(newVideoTrack);
        // Make the new track visible to the local renderer.
        if (_localStream != null) {
          await _localStream!.addTrack(newVideoTrack);
        }
        print('✅ Replaced video track via _videoSender');
      } else {
        // First time adding video (call started as audio-only).
        if (_localStream != null) {
          await _localStream!.addTrack(newVideoTrack); // must await — track must be in stream before renderer fires
          _videoSender =
              await _peerConnection!.addTrack(newVideoTrack, _localStream!);
        } else {
          _localStream = videoStream;
          _videoSender =
              await _peerConnection!.addTrack(newVideoTrack, _localStream!);
        }
        print('✅ Added new video track and stored _videoSender');
      }

      // Null-then-set forces the native renderer to reinitialize even when
      // the stream object reference hasn't changed (new track was added to it).
      _onLocalStream.add(_localStream!);
    } catch (e) {
      print('❌ Failed to acquire video track: $e');
      rethrow;
    }
  }

  /// Stop and remove local video tracks, null out the sender track.
  Future<void> _removeVideoTracks() async {
    if (_peerConnection == null) return;

    // Stop tracks AND remove them from _localStream.
    // If we only stop() without removeTrack(), _ensureVideoTrack will later
    // find the stopped (but still listed) track, see enabled==false, call
    // _applyCallTypeLocally which sets enabled=true on the dead track, and
    // then skip acquiring a fresh camera — causing a frozen black frame.
    final videoTracks =
        List<MediaStreamTrack>.from(_localStream?.getVideoTracks() ?? []);
    for (final t in videoTracks) {
      t.enabled = false;
      t.stop();
      await _localStream?.removeTrack(t);
      print('🔇 Stopped + removed local video track: ${t.id}');
    }

    // Null out the sender. Prefer the cached _videoSender; fall back to scan.
    if (_videoSender != null) {
      try {
        await _videoSender!.replaceTrack(null);
        print('🔇 Nulled _videoSender track (will reuse sender on re-enable)');
      } catch (e) {
        print('⚠️ Could not null _videoSender: $e');
      }
      // Keep _videoSender reference so replaceTrack works on re-enable.
      return;
    }

    // Fallback: scan all senders (only hit if _videoSender wasn't set)
    final senders = await _peerConnection!.getSenders();
    for (final s in senders) {
      if (s.track?.kind == 'video') {
        try {
          await s.replaceTrack(null);
          _videoSender = s; // cache for next time
          print('🔇 Removed video track from sender (fallback scan)');
        } catch (e) {
          print('⚠️ Could not null video sender track: $e');
        }
      }
    }
  }

  /// Decline a change-type request from the remote peer.
  void declineChangeCallType() {
    print('❌ Declining call type change request');
    // No standard "reject" message in the backend — just ignore.
  }

  /// Handle answer from remote peer (for renegotiation or initial call setup)
  Future<void> _handleAnswer(Map<String, dynamic> sdpMap) async {
    try {
      print('📥 Processing answer from remote peer...');

      RTCSessionDescription answer = RTCSessionDescription(
        sdpMap['sdp'],
        sdpMap['type'],
      );

      // Set remote description (the answer)
      await _peerConnection!.setRemoteDescription(answer);
      print('✅ Remote description (answer) set');

      // If this was for a renegotiation, notify UI
      if (_isInCall) {
        print('✅ Renegotiation answer applied - media tracks updated');
        _onCallTypeChanged.add(_callType);
      }
    } catch (e) {
      print('❌ Error handling answer: $e');
    }
  }

  /// Handle renegotiation offer (e.g., after call type change)
  Future<void> _handleRenegotiationOffer(Map<String, dynamic> sdpMap, String newCallType) async {
    try {
      print('🔄 Processing renegotiation offer...');
      print('   Current call type: $_callType → New call type: $newCallType');

      RTCSessionDescription offer = RTCSessionDescription(
        sdpMap['sdp'],
        sdpMap['type'],
      );

      // Set remote description (the new offer)
      await _peerConnection!.setRemoteDescription(offer);
      print('✅ Remote description (renegotiation offer) set');

      // Update call type
      _callType = newCallType;

      // For video: acquire/replace the camera track FIRST (before any
      // _applyCallTypeLocally call that could re-enable a stopped ghost track
      // and make _ensureVideoTrack think the camera is already live).
      // For audio: just apply locally (stop + remove video tracks).
      if (newCallType == 'video') {
        print('📷 Ensuring video track for renegotiation...');
        await _ensureVideoTrack();
        // Re-emit the stream so VideoCallScreen (which builds after onCallTypeChanged
        // fires below) gets a renderer refresh and shows live camera frames.
        if (_localStream != null) _onLocalStream.add(_localStream!);
      } else {
        _applyCallTypeLocally(newCallType);
      }

      // Create answer — no mandatory constraints (see comment in _handleOffer).
      RTCSessionDescription answer = await _peerConnection!.createAnswer({});

      // Set local description (our answer)
      await _peerConnection!.setLocalDescription(answer);
      print('✅ Local description (renegotiation answer) set');

      // Send answer back
      _sendMessage({
        'type': 'answer',
        'room': _roomName,
        'sdp': {
          'type': answer.type,
          'sdp': answer.sdp,
        },
        'calleeId': getUserId()
      });

      // Notify UI about the call type change
      _onCallTypeChanged.add(newCallType);

      print('✅ Renegotiation complete - call type changed to $newCallType');
    } catch (e) {
      print('❌ Error handling renegotiation offer: $e');
    }
  }

  /// Handle incoming offer from web caller
  Future<void> _handleOffer(Map<String, dynamic> sdpMap) async {
    try {
      print('📥 Processing incoming offer...');
      _onCallStateChanged.add(CallState.connecting);

      RTCSessionDescription offer = RTCSessionDescription(
        sdpMap['sdp'],
        sdpMap['type'],
      );

      // Set remote description (the offer)
      await _peerConnection!.setRemoteDescription(offer);
      print('✅ Remote description (offer) set');
      _remoteDescriptionSet = true;

      // Add any queued ICE candidates
      await _addQueuedIceCandidates();

      // Check if offer contains video
      if (offer.sdp != null) {
        if (offer.sdp!.contains('m=video')) {
          print('✅ Offer contains video track');
          // Count video lines
          final videoLines = offer.sdp!.split('\n').where((line) =>
            line.startsWith('a=rtpmap:') && (line.contains('VP8') || line.contains('VP9') || line.contains('H264'))
          ).length;
          print('   - Video codecs found: $videoLines');
        } else {
          print('⚠️ Offer does NOT contain video track');
        }
      }

      // Create answer — do NOT pass OfferToReceive* mandatory constraints.
      // Those legacy flags override the transceiver direction and on Android/
      // libwebrtc they force the direction to recvonly, meaning the mobile
      // camera track is NEVER sent to the web caller.
      // Leaving constraints empty lets the added tracks set sendrecv correctly.
      RTCSessionDescription answer = await _peerConnection!.createAnswer({});

      // Check if answer contains video
      if (answer.sdp != null) {
        if (answer.sdp!.contains('m=video')) {
          print('✅ Answer contains video track');
          // Count video lines
          final videoLines = answer.sdp!.split('\n').where((line) =>
            line.startsWith('a=rtpmap:') && (line.contains('VP8') || line.contains('VP9') || line.contains('H264'))
          ).length;
          print('   - Video codecs in answer: $videoLines');

          // Check video direction
          if (answer.sdp!.contains('a=sendrecv')) {
            print('   - Video direction: sendrecv ✅');
          } else if (answer.sdp!.contains('a=recvonly')) {
            print('   - Video direction: recvonly (we receive only)');
          } else if (answer.sdp!.contains('a=sendonly')) {
            print('   - Video direction: sendonly (we send only)');
          }
        } else {
          print('⚠️ Answer does NOT contain video track');
        }
      }

      // Set local description (our answer)
      await _peerConnection!.setLocalDescription(answer);
      print('✅ Local description (answer) set');

      // Send answer back to caller
      _sendMessage({
        'type': 'answer',
        'room': _roomName,
        'sdp': {
          'type': answer.type,
          'sdp': answer.sdp,
        },
        'calleeId': getUserId()
      });

      print('✅ Answer sent - Call connecting...');
    } catch (e) {
      print('❌ Error handling offer: $e');
      _onCallStateChanged.add(CallState.error);
    }
  }

  /// Handle ICE candidate from remote peer
  Future<void> _handleIceCandidate(Map<String, dynamic> candidateMap) async {
    try {
      print('🧊 Received ICE candidate from remote peer');

      // If remote description is not set yet, queue the candidate
      if (!_remoteDescriptionSet) {
        print('   ⏳ Queueing candidate (remote description not set yet)');
        _pendingIceCandidates.add(candidateMap);
        return;
      }

      // Add the candidate
      RTCIceCandidate candidate = RTCIceCandidate(
        candidateMap['candidate'],
        candidateMap['sdpMid'],
        candidateMap['sdpMLineIndex'],
      );

      await _peerConnection!.addCandidate(candidate);
      print('   ✅ ICE candidate added successfully');

      // Print candidate type for debugging
      final candidateStr = candidateMap['candidate'] as String;
      if (candidateStr.contains('typ host')) {
        print('   ✅ Type: HOST - Remote is on local network (TURN not needed!)');
      } else if (candidateStr.contains('typ srflx')) {
        print('   ✅ Type: SRFLX - Remote using STUN (TURN not needed!)');
      } else if (candidateStr.contains('typ relay')) {
        print('   🔄 Type: RELAY - Remote using TURN server');
      } else if (candidateStr.contains('typ prflx')) {
        print('   ✅ Type: PRFLX - Peer reflexive candidate');
      }
    } catch (e) {
      print('❌ Error handling ICE candidate: $e');
    }
  }

  /// Add queued ICE candidates after remote description is set
  Future<void> _addQueuedIceCandidates() async {
    if (_pendingIceCandidates.isEmpty) return;

    print('📋 Adding ${_pendingIceCandidates.length} queued ICE candidates');

    for (final candidateMap in _pendingIceCandidates) {
      try {
        RTCIceCandidate candidate = RTCIceCandidate(
          candidateMap['candidate'],
          candidateMap['sdpMid'],
          candidateMap['sdpMLineIndex'],
        );

        await _peerConnection!.addCandidate(candidate);
        print('   ✅ Queued candidate added');
      } catch (e) {
        print('   ❌ Error adding queued candidate: $e');
      }
    }

    _pendingIceCandidates.clear();
    print('✅ All queued candidates processed');
  }

  /// Send ICE candidate to signaling server
  void _sendIceCandidate(RTCIceCandidate candidate) {
    _sendMessage({
      'type': 'ice-candidate',
      'room': _roomName,
      'candidate': {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      },
      'calleeId': getUserId()
    });
  }

  /// Send message to signaling server
  Future<void> _sendMessage(Map<String, dynamic> message) async {
    if (_channel != null) {
      // Resolve any Futures (top-level, nested maps and lists) so jsonEncode doesn't receive a Future
      Future<dynamic> _resolveValue(dynamic value) async {
        if (value is Future) return await value;
        if (value is Map) {
          final Map<String, dynamic> resolvedMap = {};
          for (final entry in value.entries) {
            resolvedMap[entry.key] = await _resolveValue(entry.value);
          }
          return resolvedMap;
        }
        if (value is List) {
          return Future.wait(value.map((v) => _resolveValue(v)));
        }
        return value;
      }

      final Map<String, dynamic> resolved = {};
      for (final entry in message.entries) {
        resolved[entry.key] = await _resolveValue(entry.value);
      }

      _channel!.sink.add(jsonEncode(resolved));
    }
  }

  /// End the call
  Future<void> endCall() async {
    if (_isReconnecting) {
      print('Already reconnecting, skipping...');
      return;
    }

    try {
      _isReconnecting = true;
      print('Ending call...');

      // Reset call state
      _isInCall = false;

      // Notify the other side that we ended the call
      if (_channel != null) {
        _sendMessage({
          'type': 'call-ended',
          'room': _roomName,
          'calleeId': getUserId()
        });
      }

      // Stop and dispose local stream
      _localStream?.getTracks().forEach((track) {
        track.stop();
      });
      _localStream?.dispose();
      _localStream = null;

      // Dispose remote stream
      _remoteStream?.dispose();
      _remoteStream = null;

      // Close peer connection
      await _peerConnection?.close();
      _peerConnection = null;
      _videoSender = null; // Clear stale sender — old PC is gone; next call must re-create it

      // Close WebSocket
      await _channel?.sink.close();
      _channel = null;

      print('Call ended - Reconnecting...');

      // Wait a bit before reconnecting
      await Future.delayed(const Duration(milliseconds: 500));

      // Reinitialize and reconnect
      await initialize();
      await connectAndWaitForCalls();

      _isReconnecting = false;
      print('Ready for next call');
    } catch (e) {
      _isReconnecting = false;
      print('Error ending call: $e');
      _onCallStateChanged.add(CallState.error);
    }
  }

  /// Handle when remote side ends the call
  Future<void> _handleRemoteEndCall() async {
    if (_isReconnecting) {
      print('Already reconnecting, skipping...');
      return;
    }

    try {
      _isReconnecting = true;
      print('Handling remote end call...');

      // Reset call state
      _isInCall = false;

      // Stop and dispose streams
      _localStream?.getTracks().forEach((track) {
        track.stop();
      });
      _localStream?.dispose();
      _localStream = null;

      _remoteStream?.dispose();
      _remoteStream = null;

      // Close peer connection
      await _peerConnection?.close();
      _peerConnection = null;
      _videoSender = null; // Clear stale sender — old PC is gone; next call must re-create it

      // Close WebSocket
      await _channel?.sink.close();
      _channel = null;

      print('Remote end call handled - Reconnecting...');

      // Wait a bit before reconnecting
      await Future.delayed(const Duration(milliseconds: 500));

      // Reinitialize and reconnect
      await initialize();
      await connectAndWaitForCalls();

      _isReconnecting = false;
      print('Ready for next call');
    } catch (e) {
      _isReconnecting = false;
      print('Error handling remote end call: $e');
      _onCallStateChanged.add(CallState.error);
    }
  }

  /// Play ringtone when incoming call arrives
  Future<void> _playRingtone() async {
    try {
      if (_isRingtonePlaying) {
        print('Ringtone already playing');
        return;
      }

      _isRingtonePlaying = true;

      // Play system default ringtone in loop mode
      await FlutterRingtonePlayer().play(
        android: AndroidSounds.ringtone,
        ios: IosSounds.glass,
        looping: true,
        volume: 1.0,
      );

      // Start vibration pattern
      await _startVibration();

      print('🔔 System ringtone and vibration playing');
    } catch (e) {
      print('Error playing ringtone: $e');
      _isRingtonePlaying = false;
      // Don't throw error - app should work without ringtone
    }
  }

  /// Stop ringtone
  Future<void> _stopRingtone() async {
    try {
      if (_isRingtonePlaying) {
        await FlutterRingtonePlayer().stop();
        _isRingtonePlaying = false;
        print('🔕 Ringtone stopped');
      }

      // Stop vibration
      await _stopVibration();
    } catch (e) {
      print('Error stopping ringtone: $e');
    }
  }

  /// Start vibration pattern for incoming call
  Future<void> _startVibration() async {
    try {
      // Check if device supports vibration
      bool? hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator != true) {
        print('Device does not support vibration');
        return;
      }

      if (_isVibrating) {
        print('Vibration already active');
        return;
      }

      _isVibrating = true;

      // Create a repeating vibration pattern: 500ms on, 1000ms off, 500ms on, 1000ms off
      // Pattern: [wait, vibrate, wait, vibrate, ...]
      await Vibration.vibrate(
        pattern: [0, 500, 1000, 500, 1000],
        repeat: 0, // Repeat from index 0 (endless loop)
      );

      print('📳 Vibration started');
    } catch (e) {
      print('Error starting vibration: $e');
      _isVibrating = false;
    }
  }

  /// Stop vibration
  Future<void> _stopVibration() async {
    try {
      if (_isVibrating) {
        await Vibration.cancel();
        _isVibrating = false;
        print('📳 Vibration stopped');
      }
    } catch (e) {
      print('Error stopping vibration: $e');
    }
  }

  /// Dispose resources
  void dispose() {
    _stopRingtone(); // Stop ringtone and vibration if playing
    _localStream?.getTracks().forEach((track) => track.stop());
    _localStream?.dispose();
    _remoteStream?.dispose();
    _peerConnection?.close();
    _channel?.sink.close(status.goingAway);
    _onCallStateChanged.close();
    _onRemoteStream.close();
    _onLocalStream.close();
    _onIncomingCall.close();
    _onCallTypeChanged.close();
    _onChangeTypeRequest.close();
  }
}

/// Returns the persisted user ID, generating and saving a new UUID on first call.
/// The user ID is used as the WebSocket room name so the web caller can target
/// this device and the backend can look up its FCM token for push notifications.
Future<String> getUserId() async {
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  String? userId = prefs.getString('userId');
  if (userId == null || userId.isEmpty) {
    userId = const Uuid().v4();
    await prefs.setString('userId', userId);
    print('Generated new userId: $userId');
  } else {
    print('User ID: $userId');
  }
  return userId;
}

/// Call state enum
enum CallState {
  idle,
  waiting,      // Waiting for incoming calls
  incoming,     // Call is incoming (ringing)
  connecting,   // Answering the call
  connected,    // Call is active
  ended,        // Call ended
  error,        // Error occurred
}
