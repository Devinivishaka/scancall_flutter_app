import 'dart:async';
import 'dart:convert';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

/// Signaling service for WebRTC communication - RECEIVER MODE
/// This app waits for incoming calls from web clients
class SignalingService {
  // Hard-coded WebSocket server URL
  // TODO: Replace with your actual signaling server URL
  static const String _signalingServerUrl = 'ws://192.168.1.31:8080';

  // Hard-coded room name
  static const String _roomName = 'test-call';

  // Hard-coded TURN/STUN configuration
  // For LOCAL testing (same WiFi): Only STUN is needed
  // For PRODUCTION (different networks): Add TURN server
  final Map<String, dynamic> _iceServers = {
    'iceServers': [
      // Public STUN servers (free to use)
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},

      // Local TURN server (running on WSL/local machine)
      // Uncomment after setting up local Coturn server
      /*
      {
        'urls': [
          'turn:192.168.1.31:3478?transport=udp',
          'turn:192.168.1.31:3478?transport=tcp',
        ],
        'username': 'testuser',
        'credential': 'testpass123',
      }
      */

      // Production TURN server
      // Uncomment for production with cloud TURN server
      /*
      {
        'urls': [
          'turn:YOUR_TURN_SERVER_IP:3478?transport=udp',
          'turn:YOUR_TURN_SERVER_IP:3478?transport=tcp',
        ],
        'username': 'your_turn_username',
        'credential': 'your_turn_password',
      }
      */
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

  // Flag to track if we're currently reconnecting
  bool _isReconnecting = false;

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
      // Create peer connection
      _peerConnection = await createPeerConnection(_iceServers);

      // Set up peer connection callbacks
      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        _sendIceCandidate(candidate);
      };

      _peerConnection!.onTrack = (RTCTrackEvent event) {
        print('Received remote track');
        if (event.streams.isNotEmpty) {
          _remoteStream = event.streams[0];
          _onRemoteStream.add(_remoteStream!);
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
          print('WebSocket error: $error');
          _onCallStateChanged.add(CallState.error);
        },
        onDone: () {
          print('WebSocket closed');
          // Don't set to ended here - let the app handle reconnection
        },
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
      final type = data['type'];

      print('Received message: $type');

      switch (type) {
        case 'offer':
          // Incoming call!
          print('📞 INCOMING CALL!');
          _pendingOffer = data['sdp']; // Store the offer
          _onCallStateChanged.add(CallState.incoming);
          _onIncomingCall.add(null); // Notify UI
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
          print('Signaling error: ${data['message']}');
          _onCallStateChanged.add(CallState.error);
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

      // Notify the other side that we accepted
      _sendMessage({
        'type': 'call-accepted',
        'room': _roomName,
      });

      // Get local media (audio and video)
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': {
          'facingMode': 'user', // Front camera
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
        }
      });

      print('Got local audio/video stream');
      _onLocalStream.add(_localStream!);

      // Add local tracks to peer connection
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
        print('Added ${track.kind} track to peer connection');
      });

      // Now handle the offer and create answer
      await _handleOffer(_pendingOffer!);
      _pendingOffer = null; // Clear pending offer
    } catch (e) {
      print('Error accepting call: $e');
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
      print('Processing incoming offer...');
      _onCallStateChanged.add(CallState.connecting);

      RTCSessionDescription offer = RTCSessionDescription(
        sdpMap['sdp'],
        sdpMap['type'],
      );

      // Set remote description (the offer)
      await _peerConnection!.setRemoteDescription(offer);
      print('Remote description (offer) set');

      // Create answer
      RTCSessionDescription answer = await _peerConnection!.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': true, // Enable video
      });

      // Set local description (our answer)
      await _peerConnection!.setLocalDescription(answer);
      print('Local description (answer) set');

      // Send answer back to caller
      _sendMessage({
        'type': 'answer',
        'room': _roomName,
        'sdp': {
          'type': answer.type,
          'sdp': answer.sdp,
        },
      });

      print('Answer sent - Call connecting...');
    } catch (e) {
      print('Error handling offer: $e');
      _onCallStateChanged.add(CallState.error);
    }
  }

  /// Handle ICE candidate from remote peer
  Future<void> _handleIceCandidate(Map<String, dynamic> candidateMap) async {
    try {
      RTCIceCandidate candidate = RTCIceCandidate(
        candidateMap['candidate'],
        candidateMap['sdpMid'],
        candidateMap['sdpMLineIndex'],
      );

      await _peerConnection!.addCandidate(candidate);
      print('ICE candidate added');
    } catch (e) {
      print('Error handling ICE candidate: $e');
    }
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

  /// Dispose resources
  void dispose() {
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
