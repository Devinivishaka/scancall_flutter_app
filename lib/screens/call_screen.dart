import 'package:flutter/material.dart';
import '../services/signaling_service.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

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
  String? _errorMessage;

  // Call type: 'audio' or 'video'
  String _callType = 'video';
  // Pending change-type request from remote peer
  String? _pendingChangeTypeRequest;
  // Local control state
  bool _isMuted = false;
  bool _isCameraOff = false;

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
    try {
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();

      print('✅ Video renderers initialized');
      print('   - Local renderer ready: ${_localRenderer.renderVideo}');
      print('   - Remote renderer ready: ${_remoteRenderer.renderVideo}');

      setState(() {
        _localVideoInitialized = true;
        _remoteVideoInitialized = true;
      });
    } catch (e) {
      print('❌ Error initializing renderers: $e');
      setState(() {
        _errorMessage = 'Failed to initialize video renderers: $e';
        _callState = CallState.error;
      });
    }
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
          _callType = _signalingService.callType; // sync call type from offer
          _statusText = '📞 Incoming Call!';
        });

        // Show notification or play ringtone here
        print('🔔 INCOMING CALL - Waiting for user to accept...');
      });

      // Listen to remote stream (incoming video)
      _signalingService.onRemoteStream.listen((stream) {
        print('🎥 Remote stream received in UI');
        print('   - Video tracks: ${stream.getVideoTracks().length}');
        print('   - Audio tracks: ${stream.getAudioTracks().length}');

        // Ensure video tracks are enabled
        for (var track in stream.getVideoTracks()) {
          print('   - Remote video track: ${track.id}, enabled: ${track.enabled}');
          track.enabled = true;
        }

        setState(() {
          _remoteRenderer.srcObject = stream;
          print('   ✅ Remote renderer updated with stream');
        });

        // Force a rebuild after a short delay to ensure video shows
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            setState(() {});
          }
        });
      });

      // Listen to local stream (our video)
      _signalingService.onLocalStream.listen((stream) {
        print('📹 Local stream received in UI');
        print('   - Video tracks: ${stream.getVideoTracks().length}');
        print('   - Audio tracks: ${stream.getAudioTracks().length}');

        // Ensure video tracks are enabled
        for (var track in stream.getVideoTracks()) {
          print('   - Local video track: ${track.id}, enabled: ${track.enabled}');
          track.enabled = true;
        }

        setState(() {
          _localRenderer.srcObject = stream;
          print('   ✅ Local renderer updated with stream');
        });

        // Force a rebuild after a short delay to ensure video shows
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            setState(() {});
          }
        });
      });

      // Listen to call type changes (confirmed switch)
      _signalingService.onCallTypeChanged.listen((newType) {
        print('🔄 Call type changed → $newType');
        if (mounted) {
          setState(() {
            _callType = newType;
            // Reset camera-off state when switching modes
            if (newType == 'audio') _isCameraOff = true;
            if (newType == 'video') _isCameraOff = false;
          });
        }
      });

      // Listen to incoming change-type requests from the remote peer
      _signalingService.onChangeTypeRequest.listen((requestedType) {
        print('🔔 Remote requests type change → $requestedType');
        if (mounted) {
          setState(() {
            _pendingChangeTypeRequest = requestedType;
          });
          _showChangeTypeRequestDialog(requestedType);
        }
      });

      setState(() {
        _isInitialized = true;
      });

      // Automatically connect and wait for calls
      await _connectAndWait();

      print('Service initialized successfully - Ready to receive calls');
    } catch (e) {
      print('Error initializing service: $e');
      setState(() {
        _errorMessage = 'Failed to initialize service: $e';
        _callState = CallState.error;
        _statusText = 'Initialization error';
      });
    }
  }

  Future<void> _acceptCall() async {
    try {
      print('User accepted the call');

      // Check and request permissions
      print('Checking camera and microphone permissions...');
      Map<Permission, PermissionStatus> statuses = await [
        Permission.camera,
        Permission.microphone,
      ].request();

      if (statuses[Permission.camera] != PermissionStatus.granted) {
        print('❌ Camera permission denied');
        _showErrorDialog('Camera permission is required for video calls');
        return;
      }

      if (statuses[Permission.microphone] != PermissionStatus.granted) {
        print('❌ Microphone permission denied');
        _showErrorDialog('Microphone permission is required for calls');
        return;
      }

      print('✅ Permissions granted');

      setState(() {
        _showIncomingCallUI = false;
        _statusText = 'Accepting call...';
      });

      await _signalingService.acceptCall();
    } catch (e) {
      print('Error accepting call: $e');
      setState(() {
        _errorMessage = 'Failed to accept call: $e';
        _callState = CallState.error;
        _showIncomingCallUI = false;
      });
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
      setState(() {
        _errorMessage = 'Failed to reject call: $e';
        _callState = CallState.error;
        _showIncomingCallUI = false;
      });
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
      setState(() {
        _errorMessage = 'Failed to connect: $e';
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
      setState(() {
        _errorMessage = 'Failed to end call: $e';
        _callState = CallState.error;
      });
    }
  }

  void _toggleMute() {
    final stream = _signalingService.localStream;
    if (stream == null) return;
    setState(() {
      _isMuted = !_isMuted;
    });
    for (var track in stream.getAudioTracks()) {
      track.enabled = !_isMuted;
    }
    print(_isMuted ? '🔇 Microphone muted' : '🎙️ Microphone unmuted');
  }

  void _toggleCamera() {
    final stream = _signalingService.localStream;
    if (stream == null) return;
    setState(() {
      _isCameraOff = !_isCameraOff;
    });
    for (var track in stream.getVideoTracks()) {
      track.enabled = !_isCameraOff;
    }
    print(_isCameraOff ? '📷 Camera off' : '🎥 Camera on');
  }

  void _switchCallType() {
    final targetType = _callType == 'video' ? 'audio' : 'video';
    print('🔄 Requesting call type switch → $targetType');
    _signalingService.requestChangeCallType(targetType);
  }

  void _showChangeTypeRequestDialog(String requestedType) {
    final label = requestedType == 'video' ? 'Video Call' : 'Audio-only Call';
    final icon = requestedType == 'video' ? Icons.videocam : Icons.mic;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(icon, color: Colors.blue),
            const SizedBox(width: 8),
            const Text('Call Type Change'),
          ],
        ),
        content: Text('The other side wants to switch to $label. Do you accept?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _signalingService.declineChangeCallType();
              setState(() => _pendingChangeTypeRequest = null);
            },
            child: const Text('Decline', style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _signalingService.acceptChangeCallType(requestedType);
              setState(() {
                _pendingChangeTypeRequest = null;
                _callType = requestedType;
                if (requestedType == 'audio') _isCameraOff = true;
                if (requestedType == 'video') _isCameraOff = false;
              });
            },
            child: const Text('Accept'),
          ),
        ],
      ),
    );
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
        // Remote media area (full screen)
        _callType == 'video'
            ? Container(
                color: Colors.black,
                child: Center(
                  child: _remoteVideoInitialized && _remoteRenderer.srcObject != null
                      ? RTCVideoView(
                          _remoteRenderer,
                          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                          mirror: false,
                          filterQuality: FilterQuality.medium,
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CircularProgressIndicator(color: Colors.white),
                            const SizedBox(height: 20),
                            Text(
                              _remoteRenderer.srcObject == null
                                  ? 'Waiting for video...'
                                  : 'Loading video...',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                ),
              )
            : _buildAudioOnlyBackground(),

        // Local video (picture-in-picture) — only in video mode
        if (_callType == 'video')
          Positioned(
            top: 40,
            right: 20,
            child: Container(
              width: 120,
              height: 160,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(12),
                color: Colors.black,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: _isCameraOff
                    ? const Center(child: Icon(Icons.videocam_off, color: Colors.white54, size: 36))
                    : (_localVideoInitialized && _localRenderer.srcObject != null
                        ? RTCVideoView(
                            _localRenderer,
                            mirror: true,
                            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                            filterQuality: FilterQuality.medium,
                          )
                        : const Center(child: Icon(Icons.person, color: Colors.white54, size: 40))),
              ),
            ),
          ),

        // Call type badge
        Positioned(
          top: 16,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: _callType == 'video'
                    ? Colors.blue.withValues(alpha: 0.8)
                    : Colors.green.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _callType == 'video' ? Icons.videocam : Icons.mic,
                    color: Colors.white,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _callType == 'video' ? 'Video Call' : 'Audio Call',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Controls at bottom
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: Column(
            children: [
              // Secondary controls row (mute, camera, switch type)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Mute microphone
                  _buildControlButton(
                    icon: _isMuted ? Icons.mic_off : Icons.mic,
                    color: _isMuted ? Colors.red.shade700 : Colors.white24,
                    iconColor: Colors.white,
                    onTap: _toggleMute,
                    tooltip: _isMuted ? 'Unmute' : 'Mute',
                  ),
                  const SizedBox(width: 16),

                  // Toggle camera (video mode only)
                  if (_callType == 'video')
                    _buildControlButton(
                      icon: _isCameraOff ? Icons.videocam_off : Icons.videocam,
                      color: _isCameraOff ? Colors.red.shade700 : Colors.white24,
                      iconColor: Colors.white,
                      onTap: _toggleCamera,
                      tooltip: _isCameraOff ? 'Turn Camera On' : 'Turn Camera Off',
                    ),
                  if (_callType == 'video') const SizedBox(width: 16),

                  // Switch call type
                  _buildControlButton(
                    icon: _callType == 'video' ? Icons.mic : Icons.videocam,
                    color: Colors.white24,
                    iconColor: Colors.white,
                    onTap: _switchCallType,
                    tooltip: _callType == 'video' ? 'Switch to Audio' : 'Switch to Video',
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // End call button
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
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
            ],
          ),
        ),

        // Connecting overlay
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
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          ),

        // Error message during call
        if (_errorMessage != null)
          Positioned(
            bottom: 140,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.white, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => setState(() => _errorMessage = null),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// Audio-only background — dark gradient with avatar and waveform icon
  Widget _buildAudioOnlyBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A237E), Color(0xFF0D1B3E)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person, size: 70, color: Colors.white70),
            ),
            const SizedBox(height: 24),
            const Text(
              'Audio Call',
              style: TextStyle(color: Colors.white70, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            // Animated mic icon to indicate audio activity
            const Icon(Icons.graphic_eq, color: Colors.greenAccent, size: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required Color color,
    required Color iconColor,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 26),
        ),
      ),
    );
  }

  Widget _buildIncomingCallUI() {
    final isVideo = _callType == 'video';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Large call icon
          Container(
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isVideo ? Icons.videocam : Icons.phone_in_talk,
              size: 100,
              color: Colors.orange,
            ),
          ),
          const SizedBox(height: 40),

          Text(
            isVideo ? 'Incoming Video Call' : 'Incoming Audio Call',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Web Caller',
            style: TextStyle(fontSize: 20, color: Colors.grey),
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
                  const Text('Reject', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.red)),
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
                    child: Icon(isVideo ? Icons.videocam : Icons.call, size: 36),
                  ),
                  const SizedBox(height: 12),
                  const Text('Accept', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.green)),
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

          // Error message display
          if (_errorMessage != null)
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.red,
                  width: 2,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Colors.red,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Error',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.red),
                        onPressed: () {
                          setState(() {
                            _errorMessage = null;
                            if (_callState == CallState.error) {
                              _callState = CallState.idle;
                              _connectAndWait();
                            }
                          });
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.red,
                    ),
                    textAlign: TextAlign.left,
                  ),
                ],
              ),
            ),

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
