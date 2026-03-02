import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class VideoCallScreen extends StatefulWidget {
  final RTCVideoRenderer local;
  final RTCVideoRenderer remote;
  final VoidCallback onEnd;
  final String callType;
  final VoidCallback onChangeType;

  const VideoCallScreen({
    super.key,
    required this.local,
    required this.remote,
    required this.onEnd,
    this.callType = 'video',
    required this.onChangeType,
  });

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  bool micEnabled = true;
  bool camEnabled = true;
  bool speakerEnabled = false;
  bool isUnlocked = false;

  bool showMicMutedMessage = false;

  @override
  void initState() {
    super.initState();

    // Listen to renderer changes so the video views rebuild when streams
    // arrive. RTCVideoRenderer extends ChangeNotifier and notifies whenever
    // a new frame is ready or its srcObject changes.
    widget.local.addListener(_onRendererUpdate);
    widget.remote.addListener(_onRendererUpdate);

    widget.remote.onResize = () {
      print(
        "REMOTE VIDEO SIZE: ${widget.remote.videoWidth}x${widget.remote.videoHeight}",
      );
      if (mounted) setState(() {});
    };
  }

  @override
  void didUpdateWidget(VideoCallScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.local != widget.local) {
      oldWidget.local.removeListener(_onRendererUpdate);
      widget.local.addListener(_onRendererUpdate);
    }
    if (oldWidget.remote != widget.remote) {
      oldWidget.remote.removeListener(_onRendererUpdate);
      widget.remote.addListener(_onRendererUpdate);
    }
  }

  @override
  void dispose() {
    widget.local.removeListener(_onRendererUpdate);
    widget.remote.removeListener(_onRendererUpdate);
    super.dispose();
  }

  void _onRendererUpdate() {
    if (mounted) setState(() {});
  }

  // Toggle Microphone
  void toggleMic() {
    var audioTrack = widget.local.srcObject?.getAudioTracks().firstWhere(
      (t) => t.kind == "audio",
    );

    if (audioTrack == null) return;

    audioTrack.enabled = !audioTrack.enabled;

    setState(() {
      micEnabled = audioTrack.enabled;
      showMicMutedMessage = !audioTrack.enabled;
    });
  }

  // Toggle Camera
  void toggleCamera() {
    final tracks = widget.local.srcObject?.getVideoTracks() ?? [];
    if (tracks.isEmpty) return; // no video track yet (e.g. audio-only mode)
    final videoTrack = tracks.first;
    videoTrack.enabled = !videoTrack.enabled;
    setState(() => camEnabled = videoTrack.enabled);
  }

  // Switch Camera
  void switchCamera() async {
    final tracks = widget.local.srcObject?.getVideoTracks() ?? [];
    if (tracks.isEmpty) return;
    final videoTrack = tracks.first;
    try {
      await Helper.switchCamera(videoTrack);
    } catch (_) {}
  }

  // Speaker toggle
  void toggleSpeaker() async {
    setState(() => speakerEnabled = !speakerEnabled);
    await widget.remote.audioOutput(speakerEnabled ? "speaker" : "earpiece");
  }

  // Reusable control button
  Widget controlButton({
    required IconData icon,
    required VoidCallback onTap,
    Color color = Colors.white,
    IconData? activeIcon,
    bool active = true,
  }) {
    return InkWell(
      onTap: onTap,
      child: CircleAvatar(
        radius: 28,
        backgroundColor: color,
        child: Icon(
          active ? (activeIcon ?? icon) : icon,
          color: Colors.black,
          size: 28,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // REMOTE VIDEO
          // RTCVideoRenderer.textureId is always non-null after initialize().
          // Use srcObject to decide whether a stream has arrived yet.
          Positioned.fill(
            child: widget.remote.srcObject == null
                ? const Center(
                    child: Text(
                      "Waiting for Caller...",
                      style: TextStyle(color: Colors.white),
                    ),
                  )
                : RTCVideoView(
                    widget.remote,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
          ),

          // BACK BUTTON
          Positioned(
            top: 75,
            left: 20,
            child: const Icon(Icons.arrow_back, color: Colors.white, size: 26),
          ),

          // MIC MUTED BUBBLE
          if (showMicMutedMessage)
            Positioned(
              bottom: 200,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.mic_off, color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text(
                        "Your mic is muted.",
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // UNLOCK BUTTON
          Positioned(
            bottom: 130,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: () {
                  setState(() => isUnlocked = !isUnlocked);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 36,
                    vertical: 18,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(40),
                    gradient: LinearGradient(
                      colors: isUnlocked
                          ? const [Color(0xFFFFF3D9), Color(0xFFE8C99A)]
                          : const [Color(0xFFE3FFF5), Color(0xFFC4F8E3)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isUnlocked ? Icons.lock_open : Icons.lock_outline,
                        color: const Color(0xFF1B1E3C),
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        isUnlocked ? "UNLOCKED" : "UNLOCK",
                        style: const TextStyle(
                          color: Color(0xFF1B1E3C),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // LOCAL SELF VIEW
          Positioned(
            right: 10,
            top: 50,
            width: 140,
            height: 180,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: RTCVideoView(
                widget.local,
                mirror: true,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),
            ),
          ),

          // CONTROLS
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                controlButton(
                  icon: Icons.mic_off,
                  activeIcon: Icons.mic,
                  active: micEnabled,
                  onTap: toggleMic,
                ),
                controlButton(
                  icon: Icons.videocam_off,
                  activeIcon: Icons.videocam,
                  active: camEnabled,
                  onTap: toggleCamera,
                ),
                controlButton(
                  icon: Icons.volume_up,
                  activeIcon: Icons.volume_mute,
                  active: speakerEnabled,
                  onTap: toggleSpeaker,
                ),
                controlButton(
                  icon: Icons.cameraswitch,
                  activeIcon: Icons.cameraswitch_outlined,
                  active: true,
                  onTap: switchCamera,
                ),

                // Switch call type (audio ↔ video)
                controlButton(
                  icon: widget.callType == 'video'
                      ? Icons.videocam_off
                      : Icons.videocam,
                  active: true,
                  onTap: widget.onChangeType,
                ),

                // END CALL
                controlButton(
                  icon: Icons.call_end,
                  color: Colors.red,
                  onTap: widget.onEnd,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
