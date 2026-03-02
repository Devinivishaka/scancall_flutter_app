import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class IncomingCallModern extends StatefulWidget {
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const IncomingCallModern({
    super.key,
    required this.onAccept,
    required this.onReject,
  });

  @override
  State<IncomingCallModern> createState() => _IncomingCallModernState();
}

class _IncomingCallModernState extends State<IncomingCallModern> {
  CameraController? _controller;
  List<CameraDescription> cameras = [];
  int currentCameraIndex = 0;

  bool micMuted = true;
  bool videoPaused = true;
  bool cam = true;

  @override
  void initState() {
    super.initState();
    _initializeCameras();
  }

  Future<void> _initializeCameras() async {
    cameras = await availableCameras();

    // Prefer front camera first
    currentCameraIndex = cameras.indexWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
    );

    if (currentCameraIndex == -1) currentCameraIndex = 0;

    await _startCamera(cameras[currentCameraIndex]);
  }

  Future<void> _startCamera(CameraDescription cam) async {
    _controller = CameraController(
      cam,
      ResolutionPreset.medium,
      enableAudio: true,
    );

    await _controller!.initialize();
    if (mounted) setState(() {});
  }

  Future<void> _switchCamera() async {
    if (cameras.isEmpty) return;

    setState(() {
      currentCameraIndex =
          (currentCameraIndex + 1) % cameras.length; // Toggle between cameras
    });

    await _controller?.dispose();
    await _startCamera(cameras[currentCameraIndex]);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          //Camera Preview as Background
          Positioned.fill(
            child: (_controller == null || !_controller!.value.isInitialized)
                ? Container(color: Colors.black)
                : CameraPreview(_controller!),
          ),

          // BLUR OVERLAY
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 1.5, sigmaY: 1.5),
              child: Container(color: Colors.black.withOpacity(0.35)),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 20),

                // TOP BAR
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(left: 15),
                      child: Icon(
                        Icons.arrow_back,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                    const Text(
                      "Incoming...",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(right: 15),
                      child: Icon(
                        Icons.signal_cellular_alt,
                        color: Colors.greenAccent,
                        size: 22,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 45),

                // NAME
                const Text(
                  "John Doe",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 8),
                const Text(
                  "Video Call",
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),

                const Spacer(),

                // CONTROL BUTTONS (Mute / Pause / Switch Camera)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // MUTE MIC
                    _circleButton(
                      icon: micMuted ? Icons.mic : Icons.mic_off,
                      color: micMuted
                          ? const Color.fromARGB(255, 255, 255, 255)
                          : const Color.fromARGB(255, 255, 255, 255),
                      onTap: () => setState(() => micMuted = !micMuted),
                    ),

                    const SizedBox(width: 20),

                    // PAUSE / RESUME VIDEO
                    _circleButton(
                      icon: videoPaused ? Icons.videocam : Icons.videocam_off,

                      color: videoPaused
                          ? const Color.fromARGB(255, 255, 255, 255)
                          : const Color.fromARGB(255, 255, 255, 255),
                      onTap: () {
                        if (_controller == null) return;

                        setState(() {
                          videoPaused = !videoPaused;
                        });

                        if (videoPaused) {
                          _controller!.pausePreview();
                        } else {
                          _controller!.resumePreview();
                        }
                      },
                    ),

                    const SizedBox(width: 20),

                    // SWITCH CAMERA
                    _circleButton(
                      icon: cam
                          ? Icons.cameraswitch
                          : Icons.cameraswitch_outlined,

                      // icon: Icons.cameraswitch,
                      color: const Color.fromARGB(255, 255, 255, 255),
                      onTap: () async {
                        setState(() => cam = !cam);
                        await _switchCamera();
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 60),

                // ACCEPT / REJECT BUTTONS
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // REJECT
                    GestureDetector(
                      onTap: widget.onReject,
                      child: Container(
                        width: 75,
                        height: 75,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.call_end,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ),

                    // ACCEPT
                    GestureDetector(
                      onTap: widget.onAccept,
                      child: Container(
                        width: 75,
                        height: 75,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.call,
                          color: Colors.black,
                          size: 32,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 70),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 🔵 Reusable button widget
  Widget _circleButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(0.8),
          border: Border.all(color: Colors.white38, width: 1.5),
        ),
        child: Icon(icon, color: const Color.fromARGB(255, 0, 0, 0), size: 26),
      ),
    );
  }
}
