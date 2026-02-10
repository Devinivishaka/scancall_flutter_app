import 'package:flutter/material.dart';
import '../services/signaling_service.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class CallScreen extends StatefulWidget {
  const CallScreen({super.key});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final SignalingService _signalingService = SignalingService();
  CallState _callState = CallState.idle;
  String _statusText = 'Initializing...';
  bool _isInitialized = false;
  bool _showIncomingCallUI = false;

  // Video renderers
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _localVideoInitialized = false;
  bool _remoteVideoInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeRenderers();
    _initializeService();
  }

  Future<void> _initializeRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    setState(() {
      _localVideoInitialized = true;
      _remoteVideoInitialized = true;
    });
  }

  Future<void> _initializeService() async {
    try {
      // Initialize signaling service
      await _signalingService.initialize();

      // Listen to call state changes
      _signalingService.onCallStateChanged.listen((state) {
        setState(() {
          _callState = state;
          _statusText = _getStatusText(state);

          // Hide incoming call UI when call starts or ends
          if (state == CallState.connecting ||
              state == CallState.connected) {
            _showIncomingCallUI = false;
          }

          // Clear video when call ends and we're back to waiting
          if (state == CallState.waiting) {
            _showIncomingCallUI = false;
            // Clear video renderers
            _localRenderer.srcObject = null;
            _remoteRenderer.srcObject = null;
          }
        });
      });

      // Listen for incoming calls
      _signalingService.onIncomingCall.listen((_) {
        setState(() {
          _showIncomingCallUI = true;
          _callState = CallState.incoming;
          _statusText = '📞 Incoming Call!';
        });

        // Show notification or play ringtone here
        print('🔔 INCOMING CALL - Waiting for user to accept...');
      });

      // Listen to remote stream (incoming video)
      _signalingService.onRemoteStream.listen((stream) {
        print('Remote audio/video stream received');
        setState(() {
          _remoteRenderer.srcObject = stream;
        });
      });

      // Listen to local stream (our video)
      _signalingService.onLocalStream.listen((stream) {
        print('Local audio/video stream received');
        setState(() {
          _localRenderer.srcObject = stream;
        });
      });

      setState(() {
        _isInitialized = true;
      });

      // Automatically connect and wait for calls
      await _connectAndWait();

      print('Service initialized successfully - Ready to receive calls');
    } catch (e) {
      print('Error initializing service: $e');
      _showErrorDialog('Failed to initialize: $e');
    }
  }

  Future<void> _acceptCall() async {
    try {
      print('User accepted the call');
      setState(() {
        _showIncomingCallUI = false;
        _statusText = 'Accepting call...';
      });

      await _signalingService.acceptCall();
    } catch (e) {
      print('Error accepting call: $e');
      _showErrorDialog('Failed to accept call: $e');
    }
  }

  Future<void> _rejectCall() async {
    try {
      print('User rejected the call');
      setState(() {
        _showIncomingCallUI = false;
        _statusText = 'Call rejected';
      });

      await _signalingService.rejectCall();

      // Wait a bit then show waiting status again
      await Future.delayed(const Duration(seconds: 2));
      setState(() {
        _statusText = 'Waiting for call...';
      });
    } catch (e) {
      print('Error rejecting call: $e');
      _showErrorDialog('Failed to reject call: $e');
    }
  }

  Future<void> _connectAndWait() async {
    try {
      setState(() {
        _statusText = 'Connecting to server...';
      });

      await _signalingService.connectAndWaitForCalls();

      setState(() {
        _statusText = 'Waiting for call...';
      });
    } catch (e) {
      print('Error connecting: $e');
      _showErrorDialog('Failed to connect: $e');
      setState(() {
        _callState = CallState.error;
        _statusText = 'Connection error';
      });
    }
  }

  String _getStatusText(CallState state) {
    switch (state) {
      case CallState.idle:
        return 'Ready';
      case CallState.waiting:
        return 'Waiting for call...';
      case CallState.incoming:
        return '📞 Incoming Call!';
      case CallState.connecting:
        return 'Connecting...';
      case CallState.connected:
        return '✅ Call connected';
      case CallState.ended:
        return 'Call ended';
      case CallState.error:
        return '❌ Error occurred';
    }
  }

  Future<void> _endCall() async {
    try {
      await _signalingService.endCall();
      setState(() {
        _statusText = 'Call ended - Waiting for next call...';
      });
    } catch (e) {
      print('Error ending call: $e');
      _showErrorDialog('Failed to end call: $e');
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _signalingService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WebRTC Receiver'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    // Show video call UI when connected
    if (_callState == CallState.connected || _callState == CallState.connecting) {
      return _buildVideoCallUI();
    }

    // Show incoming call UI
    if (_showIncomingCallUI) {
      return _buildIncomingCallUI();
    }

    // Show regular status UI
    return _buildStatusUI();
  }

  Widget _buildVideoCallUI() {
    return Stack(
      children: [
        // Remote video (full screen)
        _remoteVideoInitialized
            ? RTCVideoView(_remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
            : Container(
                color: Colors.black,
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),

        // Local video (picture-in-picture)
        Positioned(
          top: 40,
          right: 20,
          child: Container(
            width: 120,
            height: 160,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: _localVideoInitialized
                  ? RTCVideoView(_localRenderer, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                  : Container(color: Colors.black),
            ),
          ),
        ),

        // Controls at bottom
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // End call button
              Container(
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: IconButton(
                  icon: const Icon(Icons.call_end, size: 32),
                  color: Colors.white,
                  onPressed: _endCall,
                  padding: const EdgeInsets.all(16),
                ),
              ),
            ],
          ),
        ),

        // Call status indicator
        if (_callState == CallState.connecting)
          Positioned(
            top: 100,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              margin: const EdgeInsets.symmetric(horizontal: 40),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Connecting...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildIncomingCallUI() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Large phone icon
          Container(
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.phone_in_talk,
              size: 100,
              color: Colors.orange,
            ),
          ),
          const SizedBox(height: 40),

          const Text(
            'Incoming Call',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Web Caller',
            style: TextStyle(
              fontSize: 20,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 80),

          // Accept and Reject buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Reject button
              Column(
                children: [
                  ElevatedButton(
                    onPressed: _rejectCall,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(28),
                      elevation: 8,
                    ),
                    child: const Icon(Icons.call_end, size: 36),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Reject',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),

              // Accept button
              Column(
                children: [
                  ElevatedButton(
                    onPressed: _acceptCall,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(28),
                      elevation: 8,
                    ),
                    child: const Icon(Icons.call, size: 36),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Accept',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusUI() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Status icon
          Icon(
            _getStatusIcon(),
            size: 100,
            color: _getStatusColor(),
          ),
          const SizedBox(height: 40),

          // Status text
          Text(
            _statusText,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),

          // Call state indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: _getStatusColor().withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _getStatusColor(),
                width: 2,
              ),
            ),
            child: Text(
              _callState.toString().split('.').last.toUpperCase(),
              style: TextStyle(
                color: _getStatusColor(),
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(height: 60),

          // Info text
          if (_callState == CallState.waiting && _isInitialized)
            const Text(
              'Listening for incoming calls from web...\nMake sure web caller is using room: "test-call"',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),

          if (!_isInitialized)
            const Column(
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text(
                  'Initializing...',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  IconData _getStatusIcon() {
    switch (_callState) {
      case CallState.idle:
      case CallState.waiting:
        return Icons.phone_in_talk;
      case CallState.incoming:
        return Icons.phone_callback;
      case CallState.connecting:
        return Icons.phone_forwarded;
      case CallState.connected:
        return Icons.call;
      case CallState.ended:
        return Icons.call_end;
      case CallState.error:
        return Icons.error_outline;
    }
  }

  Color _getStatusColor() {
    switch (_callState) {
      case CallState.idle:
      case CallState.waiting:
        return Colors.blue;
      case CallState.incoming:
        return Colors.orange;
      case CallState.connecting:
        return Colors.amber;
      case CallState.connected:
        return Colors.green;
      case CallState.ended:
        return Colors.grey;
      case CallState.error:
        return Colors.red;
    }
  }
}
