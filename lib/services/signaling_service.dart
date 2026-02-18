import 'dart:async';
import 'dart:convert';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:vibration/vibration.dart';
class SignalingService {

  static const String _signalingServerUrl = 'ws://10.0.2.2:8080/ws';

  // Hard-coded room name
  static const String _roomName = 'test-call';
  
  // Dynamic room name (overrides _roomName if set)
  String? _dynamicRoom;
  
  // User/Device ID for signaling (can be FCM token or unique device ID)
  String? _userId;
  
  // Flag to control reconnection behavior (false for FCM calls)
  bool _shouldReconnectAfterEnd = true;
  
  // Flag to control ringtone (false for FCM calls where user already accepted)
  bool _shouldPlayRingtone = true;
  
  // Get the current room name (dynamic or default)
  String get currentRoom => _dynamicRoom ?? _roomName;

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

  // Track whether service is disposed to avoid adding events to closed streams
  bool _isDisposed = false;

  // Stream controllers for callbacks
  final _onCallStateChanged = StreamController<CallState>.broadcast();
  final _onRemoteStream = StreamController<MediaStream>.broadcast();
  final _onLocalStream = StreamController<MediaStream>.broadcast();
  final _onIncomingCall = StreamController<void>.broadcast();

  // Safe emit helpers
  void _emitCallState(CallState state) {
    if (_isDisposed) return;
    if (!_onCallStateChanged.isClosed) _onCallStateChanged.add(state);
  }

  void _emitRemoteStream(MediaStream stream) {
    if (_isDisposed) return;
    if (!_onRemoteStream.isClosed) _onRemoteStream.add(stream);
  }

  void _emitLocalStream(MediaStream stream) {
    if (_isDisposed) return;
    if (!_onLocalStream.isClosed) _onLocalStream.add(stream);
  }

  void _emitIncomingCall() {
    if (_isDisposed) return;
    if (!_onIncomingCall.isClosed) _onIncomingCall.add(null);
  }

  // Getters
  Stream<CallState> get onCallStateChanged => _onCallStateChanged.stream;
  Stream<MediaStream> get onRemoteStream => _onRemoteStream.stream;
  Stream<MediaStream> get onLocalStream => _onLocalStream.stream;
  Stream<void> get onIncomingCall => _onIncomingCall.stream;
  MediaStream? get remoteStream => _remoteStream;
  MediaStream? get localStream => _localStream;

  // Setter for userId (e.g., FCM token)
  void setUserId(String userId) {
    _userId = userId;
    print('🆔 User ID set: ${userId.substring(0, 20)}...');
  }

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
        if (_isDisposed) return;
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
            _emitRemoteStream(_remoteStream!);
          } else {
            print('✅ Track added to existing stream');
            // Still notify UI in case it's a new track type
            _emitRemoteStream(_remoteStream!);
          }
        } else {
          print('⚠️ No streams in track event');
        }
      };

      _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
        print('Connection state: $state');
        switch (state) {
          case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
            _emitCallState(CallState.connected);
            break;
          case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
            _emitCallState(CallState.ended);
            break;
          case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
            _emitCallState(CallState.connecting);
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

  /// Connect to the signaling server and wait for incoming calls
  /// [room] - Optional room/call ID to join. If null, uses default room.
  Future<void> connectAndWaitForCalls({String? room}) async {
    if (_isDisposed) {
      print('connectAndWaitForCalls called after dispose - ignoring');
      return;
    }
    try {
      // Set the dynamic room if provided
      if (room != null) {
        _dynamicRoom = room;
        _shouldReconnectAfterEnd = false; // FCM call - don't reconnect after end
        _shouldPlayRingtone = false; // FCM call - don't play ringtone (user already accepted)
        print('🏠 Using dynamic room: $room (FCM mode - no auto-reconnect, no ringtone)');
      } else {
        _dynamicRoom = null;
        _shouldReconnectAfterEnd = true; // Standard mode - reconnect after end
        _shouldPlayRingtone = true; // Standard mode - play ringtone on incoming call
        print('🏠 Using default room: $_roomName (Standard mode - auto-reconnect, with ringtone)');
      }

      _emitCallState(CallState.waiting);

      _channel = WebSocketChannel.connect(Uri.parse(_signalingServerUrl));

      // Listen for messages from the signaling server
      _channel!.stream.listen(
        (message) {
          _handleSignalingMessage(message);
        },
        onError: (error) {
          print('❌ WebSocket error: $error');
          // Don't immediately set to error state - try to recover
          if (!_isReconnecting) {
            print('   Will attempt to reconnect...');
            _attemptReconnect();
          }
        },
        onDone: () {
          print('🔌 WebSocket connection closed');
          // Attempt to reconnect when connection closes unexpectedly
          if (!_isReconnecting) {
            print('   Attempting to reconnect...');
            _attemptReconnect();
          }
        },
        cancelOnError: false, // Don't cancel the stream on error
      );

      // Join the room with userId
      _sendMessage({
        'type': 'join',
        'room': currentRoom,
        'user': _userId ?? 'mobile-${DateTime.now().millisecondsSinceEpoch}', // Generate unique ID if not set
      });

      print('Connected to signaling server - Waiting for calls in room: $currentRoom (user: ${_userId ?? "auto-generated"})');
    } catch (e) {
      print('Error connecting to signaling server: $e');
      _emitCallState(CallState.error);
      rethrow;
    }
  }

  /// Handle incoming signaling messages
  void _handleSignalingMessage(dynamic message) async {
    try {
      final data = jsonDecode(message);

      // Validate message structure
      if (data is! Map<String, dynamic>) {
        print('⚠️ Invalid message format (not a JSON object): $message');
        return;
      }

      final type = data['type'];

      if (type == null) {
        print('⚠️ Message missing "type" field: $data');
        return;
      }

      print('Received message: $type');

      // Normalize type so we can support both backend uppercase notifier messages
      // (e.g. INCOMING_CALL, CALL_ACCEPTED) and the existing lowercase signaling messages
      final normalized = type.toString().replaceAll('-', '_').replaceAll(' ', '_').toLowerCase();

      // Handle backend notifier-style messages first (normalized)
      if (normalized == 'incoming_call') {
        // Backend notifier tells us a call is incoming and provides a callId (room)
        final callId = data['callId'] ?? data['room'];
        final callType = data['callType'] ?? 'AUDIO';
        print('📞 INCOMING_CALL from server - callId: $callId, callType: $callType');

        // Configure dynamic room (join this call room to receive offer/ice from caller)
        if (callId != null) {
          _dynamicRoom = callId;
          _shouldReconnectAfterEnd = false; // FCM/Notifier-style incoming call: don't auto-reconnect after end
          _shouldPlayRingtone = true; // user hasn't accepted yet, so play ringtone

          _emitCallState(CallState.incoming);
          _emitIncomingCall(); // Notify UI

          // Play ringtone
          if (_shouldPlayRingtone) {
            await _playRingtone();
          }

          // If we're not connected to the WS, create connection and join the dynamic room.
          if (_channel == null) {
            print('Not connected to WS - connecting and joining dynamic room: $callId');
            await connectAndWaitForCalls(room: callId);
          } else {
            // If already connected, send a join for the dynamic room so caller can send offer
            print('Already connected - joining dynamic room: $callId');
            _sendMessage({
              'type': 'join',
              'room': currentRoom,
              'user': _userId ?? 'mobile-${DateTime.now().millisecondsSinceEpoch}',
            });
          }
        } else {
          print('⚠️ INCOMING_CALL missing callId');
        }

        return;
      }

      if (normalized == 'call_accepted') {
        print('CALL_ACCEPTED received');
        _emitCallState(CallState.connecting);
        return;
      }

      if (normalized == 'call_rejected') {
        print('CALL_REJECTED received');
        _emitCallState(CallState.ended);
        return;
      }

      if (normalized == 'call_ended') {
        print('CALL_ENDED received');
        await _handleRemoteEndCall();
        return;
      }

      if (normalized == 'call_cancelled') {
        print('CALL_CANCELLED received');
        await _handleRemoteEndCall();
        return;
      }

      if (normalized == 'user_busy') {
        print('USER_BUSY received');
        // Caller was informed that callee is busy. Treat as ended/error for UI.
        _emitCallState(CallState.error);
        return;
      }

      if (normalized == 'call_missed') {
        print('CALL_MISSED received');
        _emitCallState(CallState.ended);
        return;
      }

      // Fallback to existing signaling protocol messages (offer/ice-candidate, call-accepted, etc.)
      switch (type) {
        case 'offer':
          // Incoming call!
          print('📞 INCOMING CALL!');
          _pendingOffer = data['sdp']; // Store the offer
          _emitCallState(CallState.incoming);
          _emitIncomingCall(); // Notify UI

          // Play ringtone only if enabled (not for FCM calls where user already accepted)
          if (_shouldPlayRingtone) {
            await _playRingtone();
          } else {
            print('🔇 Skipping ringtone (FCM mode - user already accepted via CallKit)');
          }
          break;
        case 'ice-candidate':
          await _handleIceCandidate(data['candidate']);
          break;
        case 'call-accepted':
          // Remote side accepted the call
          print('✅ Remote side accepted the call');
          _emitCallState(CallState.connecting);
          break;
        case 'call-ended':
          // Remote side ended the call
          print('📵 Remote side ended the call');
          await _handleRemoteEndCall();
          break;
        case 'call-rejected':
          // Remote side rejected the call
          print('❌ Remote side rejected the call');
          _emitCallState(CallState.ended);
          break;
        case 'joined':
          print('✅ Joined room: $currentRoom - Ready to receive calls');
          break;
        case 'error':
          final errorMsg = data['message'] ?? data['error'] ?? 'Unknown error occurred';
          print('Signaling error: $errorMsg');
          print('   Full error data: $data');
          // Don't change state to error immediately - could be a non-critical error
          // Only log it and continue waiting for calls
          break;
        default:
          print('Unknown message type: $type');
      }
    } catch (e, stackTrace) {
      print('❌ Error handling signaling message: $e');
      print('   Message: $message');
      print('   Stack trace: $stackTrace');
      // Don't crash - just log and continue
    }
  }

  /// Called when an incoming call is received via FCM (or other push) and no WS message will arrive
  /// This configures the service to use the provided callId as the dynamic room and not require
  /// a server 'incoming_call' websocket message.
  void handleFcmIncomingCall({required String callId, String? callerName, String? callType}) {
    if (_isDisposed) return;

    print('handleFcmIncomingCall - callId: $callId, callerName: $callerName, callType: $callType');

    // Use the provided callId as dynamic room so later connect/join will use it
    _dynamicRoom = callId;

    // In FCM flow we usually do not want to auto-reconnect after the call ends and
    // we might skip playing ringtone because CallKit already played it.
    _shouldReconnectAfterEnd = false;
    _shouldPlayRingtone = false;

    // Notify UI about the incoming call
    _emitCallState(CallState.incoming);
    _emitIncomingCall();
  }

  /// Accept incoming call (called when user taps Accept button)
  Future<void> acceptCall() async {
    // Note: in FCM flow the remote offer may not have arrived yet. We allow accepting
    // even when _pendingOffer is null: prepare local media and peer connection, add
    // tracks and wait for the remote offer to arrive later.

    try {
      print('Accepting call...');

      // Stop ringtone
      await _stopRingtone();

      // Get local media (audio and video) FIRST
      print('Requesting camera and microphone access...');

      try {
        _localStream = await navigator.mediaDevices.getUserMedia({
          'audio': {
            'echoCancellation': true,
            'noiseSuppression': true,
          },
          'video': {
            'facingMode': 'user', // Front camera
            'width': {'ideal': 1280, 'max': 1920},
            'height': {'ideal': 720, 'max': 1080},
            'frameRate': {'ideal': 30, 'max': 30},
          }
        });
      } catch (e) {
        print('❌ Failed to get camera/microphone: $e');
        print('⚠️ Make sure camera and microphone permissions are granted');
        _emitCallState(CallState.error);
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

      // Emit local stream to UI
      _emitLocalStream(_localStream!);

      // Add local tracks to peer connection BEFORE handling offer (works even if offer not yet arrived)
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
        print('✅ Added ${track.kind} track to peer connection');
      });

      // Notify the other side that we accepted if WebSocket is connected
      if (_channel != null) {
        _sendMessage({
          'type': 'call-accepted',
          'room': currentRoom,
        });
      } else {
        print('No WS channel; will send call-accepted when/if connected');
      }

      // If we already have an offer queued, handle it immediately
      if (_pendingOffer != null) {
        await _handleOffer(_pendingOffer!);
        _pendingOffer = null; // Clear pending offer
      } else {
        // No offer yet - set state to connecting and wait for offer to arrive
        _emitCallState(CallState.connecting);
        print('No pending offer yet; waiting for remote offer...');
      }
    } catch (e) {
      print('❌ Error accepting call: $e');
      _emitCallState(CallState.error);
    }
  }

  /// Reject incoming call (called when user taps Reject button)
  Future<void> rejectCall() async {
    if (_pendingOffer == null && _channel == null) {
      // If we have neither an offer nor a WS channel, treat this as cancel from local
      print('No pending offer and no WS channel - rejecting locally');
    }

    try {
      print('Rejecting call...');

      // Stop ringtone
      await _stopRingtone();

      // Clear pending offer
      _pendingOffer = null;

      // Send rejection message to caller if connected
      if (_channel != null) {
        _sendMessage({
          'type': 'reject',
          'room': currentRoom,
        });
      }

      // Reset to waiting state
      _emitCallState(CallState.waiting);

      print('Call rejected');
    } catch (e) {
      print('Error rejecting call: $e');
    }
  }

  /// Handle incoming offer from web caller
  Future<void> _handleOffer(Map<String, dynamic> sdpMap) async {
    try {
      print('📥 Processing incoming offer...');
      _emitCallState(CallState.connecting);

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

      // Create answer with proper video/audio constraints
      RTCSessionDescription answer = await _peerConnection!.createAnswer({
        'mandatory': {
          'OfferToReceiveAudio': true,
          'OfferToReceiveVideo': true,
        },
      });

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
        'room': currentRoom,
        'sdp': {
          'type': answer.type,
          'sdp': answer.sdp,
        },
      });

      print('✅ Answer sent - Call connecting...');
    } catch (e) {
      print('❌ Error handling offer: $e');
      _emitCallState(CallState.error);
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
      'room': currentRoom,
      'candidate': {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      },
    });
  }

  /// Send message to signaling server
  void _sendMessage(Map<String, dynamic> message) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode(message));
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

      // Notify the other side that we ended the call
      if (_channel != null) {
        _sendMessage({
          'type': 'call-ended',
          'room': currentRoom,
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

      // Close WebSocket
      await _channel?.sink.close();
      _channel = null;

      // Check if we should reconnect (standard mode) or just clean up (FCM mode)
      if (_shouldReconnectAfterEnd) {
        print('Call ended - Reconnecting (standard mode)...');

        // Wait a bit before reconnecting
        await Future.delayed(const Duration(milliseconds: 500));

        // Reinitialize and reconnect
        await initialize();
        await connectAndWaitForCalls();

        _isReconnecting = false;
        print('Ready for next call');
      } else {
        print('Call ended - Not reconnecting (FCM mode)');
        _emitCallState(CallState.ended);
        _isReconnecting = false;
      }
    } catch (e) {
      _isReconnecting = false;
      print('Error ending call: $e');
      _emitCallState(CallState.error);
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

      // Close WebSocket
      await _channel?.sink.close();
      _channel = null;

      // Check if we should reconnect (standard mode) or just clean up (FCM mode)
      if (_shouldReconnectAfterEnd) {
        print('Remote end call handled - Reconnecting (standard mode)...');

        // Wait a bit before reconnecting
        await Future.delayed(const Duration(milliseconds: 500));

        // Reinitialize and reconnect
        await initialize();
        await connectAndWaitForCalls();

        _isReconnecting = false;
        print('Ready for next call');
      } else {
        print('Remote end call handled - Not reconnecting (FCM mode)');
        _emitCallState(CallState.ended);
        _isReconnecting = false;
      }
    } catch (e) {
      _isReconnecting = false;
      print('Error handling remote end call: $e');
      _emitCallState(CallState.error);
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

  /// Attempt to reconnect to signaling server
  Future<void> _attemptReconnect() async {
    if (_isReconnecting) {
      print('Already reconnecting, skipping...');
      return;
    }

    try {
      _isReconnecting = true;
      print('🔄 Attempting to reconnect to signaling server...');

      // Close existing WebSocket if any
      try {
        await _channel?.sink.close();
      } catch (e) {
        print('   Error closing old connection: $e');
      }
      _channel = null;

      // Wait before reconnecting
      await Future.delayed(const Duration(seconds: 2));

      // Reconnect to signaling server
      await connectAndWaitForCalls();

      _isReconnecting = false;
      print('✅ Reconnected successfully');
    } catch (e) {
      _isReconnecting = false;
      print('❌ Reconnection failed: $e');
      print('   Will retry in 5 seconds...');

      // Retry after a longer delay
      await Future.delayed(const Duration(seconds: 5));
      if (!_isReconnecting) {
        _attemptReconnect();
      }
    }
  }

  /// Dispose resources
  void dispose() {
    // Mark disposed first to prevent any further events from being emitted
    _isDisposed = true;

    // Stop ringtone/vibration
    _stopRingtone(); // Stop ringtone and vibration if playing

    // Stop and dispose local stream
    _localStream?.getTracks().forEach((track) => track.stop());
    _localStream?.dispose();
    _localStream = null;

    // Dispose remote stream
    _remoteStream?.dispose();
    _remoteStream = null;

    // Remove peer connection callbacks to avoid them firing after dispose
    try {
      if (_peerConnection != null) {
        _peerConnection!.onIceCandidate = null;
        _peerConnection!.onIceConnectionState = null;
        _peerConnection!.onIceGatheringState = null;
        _peerConnection!.onTrack = null;
        _peerConnection!.onConnectionState = null;
        awaitClosePeerConnection();
      }
    } catch (e) {
      // ignore
    }

    // Close WebSocket
    try {
      _channel?.sink.close(status.goingAway);
    } catch (e) {
      // ignore
    }
    _channel = null;

    // Close StreamControllers if not already closed
    if (!_onCallStateChanged.isClosed) _onCallStateChanged.close();
    if (!_onRemoteStream.isClosed) _onRemoteStream.close();
    if (!_onLocalStream.isClosed) _onLocalStream.close();
    if (!_onIncomingCall.isClosed) _onIncomingCall.close();
  }

  // Helper to close peer connection asynchronously
  void awaitClosePeerConnection() {
    // Close without awaiting heavy operations here; schedule close microtask
    Future.microtask(() async {
      try {
        await _peerConnection?.close();
      } catch (e) {
        // ignore
      }
      _peerConnection = null;
    });
  }

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
