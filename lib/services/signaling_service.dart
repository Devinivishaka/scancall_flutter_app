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

  // Stream controllers for callbacks
  final _onCallStateChanged = StreamController<CallState>.broadcast();
  final _onRemoteStream = StreamController<MediaStream>.broadcast();
  final _onLocalStream = StreamController<MediaStream>.broadcast();
  final _onIncomingCall = StreamController<void>.broadcast();

  // Getters
  Stream<CallState> get onCallStateChanged => _onCallStateChanged.stream;
  Stream<MediaStream> get onRemoteStream => _onRemoteStream.stream;
  Stream<MediaStream> get onLocalStream => _onLocalStream.stream;
  Stream<void> get onIncomingCall => _onIncomingCall.stream;
  MediaStream? get remoteStream => _remoteStream;
  MediaStream? get localStream => _localStream;

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

  /// Connect to the signaling server and wait for incoming calls
  Future<void> connectAndWaitForCalls() async {
    try {
      _onCallStateChanged.add(CallState.waiting);

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

      // Join the room
      _sendMessage({
        'type': 'join',
        'room': _roomName,
      });

      print('Connected to signaling server - Waiting for calls...');
    } catch (e) {
      print('Error connecting to signaling server: $e');
      _onCallStateChanged.add(CallState.error);
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

      switch (type) {
        case 'offer':
          // Incoming call!
          print('📞 INCOMING CALL!');
          _pendingOffer = data['sdp']; // Store the offer
          _onCallStateChanged.add(CallState.incoming);
          _onIncomingCall.add(null); // Notify UI

          // Play ringtone
          await _playRingtone();
          break;
        case 'ice-candidate':
          await _handleIceCandidate(data['candidate']);
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

      // Add local tracks to peer connection BEFORE handling offer
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
        print('✅ Added ${track.kind} track to peer connection');
      });

      // Notify the other side that we accepted
      _sendMessage({
        'type': 'call-accepted',
        'room': _roomName,
      });

      // Now handle the offer and create answer
      await _handleOffer(_pendingOffer!);
      _pendingOffer = null; // Clear pending offer
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
      });

      // Reset to waiting state
      _onCallStateChanged.add(CallState.waiting);

      print('Call rejected');
    } catch (e) {
      print('Error rejecting call: $e');
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
        'room': _roomName,
        'sdp': {
          'type': answer.type,
          'sdp': answer.sdp,
        },
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
          'room': _roomName,
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
