import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'call_ended_screen.dart';

class AudioCallScreen extends StatefulWidget {
  final String name;
  final String avatar;
  final RTCVideoRenderer local;
  final RTCVideoRenderer remote;
  final VoidCallback onEnd;

  const AudioCallScreen({
    super.key,
    required this.name,
    required this.avatar,
    required this.local,
    required this.remote,
    required this.onEnd,
  });

  @override
  State<AudioCallScreen> createState() => _AudioCallScreenState();
}

class _AudioCallScreenState extends State<AudioCallScreen> {
  bool micEnabled = true;
  bool speakerEnabled = false;

  String duration = "00:00";
  Timer? timer;
  int seconds = 0;

  @override
  void initState() {
    super.initState();
    startTimer();
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  void startTimer() {
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        seconds++;
        final m = (seconds ~/ 60).toString().padLeft(2, '0');
        final s = (seconds % 60).toString().padLeft(2, '0');
        duration = "$m:$s";
      });
    });
  }

  void endCall() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => CallEndedScreen(
          callerName: "John Doe",
          duration: "1:02",
          avatarUrl: "https://randomuser.me/api/portraits/men/32.jpg",
        ),
      ),
    );
  }

  void toggleMic() {
    var audioTrack = widget.local.srcObject?.getAudioTracks().first;
    if (audioTrack != null) {
      audioTrack.enabled = !audioTrack.enabled;
      setState(() => micEnabled = audioTrack.enabled);
    }
  }

  void toggleSpeaker() async {
    setState(() => speakerEnabled = !speakerEnabled);
    await widget.remote.audioOutput(speakerEnabled ? "speaker" : "earpiece");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8F0D8),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Icon(Icons.arrow_back, color: Colors.black87, size: 22),
                  Text(
                    "In Call",
                    style: TextStyle(
                      color: Colors.black87,
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Icon(
                    Icons.signal_cellular_alt,
                    color: Colors.green,
                    size: 20,
                  ),
                ],
              ),
            ),

            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 50),

                    // Avatar
                    CircleAvatar(
                      radius: 45,
                      backgroundImage: NetworkImage(widget.avatar),
                    ),

                    const SizedBox(height: 16),

                    // Name
                    Text(
                      widget.name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1B1E3C),
                      ),
                    ),

                    const SizedBox(height: 6),

                    // Timer
                    Text(
                      duration,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                      ),
                    ),

                    const Spacer(),

                    Padding(
                      padding: const EdgeInsets.only(bottom: 40),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _bottomButton(
                            icon: micEnabled ? Icons.mic : Icons.mic_off,
                            active: true,
                            onTap: toggleMic,
                          ),
                          _bottomButton(
                            icon: speakerEnabled
                                ? Icons.volume_up
                                : Icons.volume_mute,
                            active: true,
                            onTap: toggleSpeaker,
                          ),
                          _bottomButton(
                            icon: Icons.videocam_off,
                            active: false,
                            onTap: () {},
                          ),
                          _bottomButton(
                            icon: Icons.call_end,
                            color: Colors.red,
                            active: true,
                            iconColor: Colors.white,
                            onTap: widget.onEnd,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomButton({
    required IconData icon,
    required VoidCallback onTap,
    bool active = true,
    Color color = const Color(0xFF1B1E3C),
    Color iconColor = Colors.white,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 53,
        height: 53,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? color : Colors.grey.shade300,
        ),
        child: Icon(
          icon,
          color: active ? iconColor : Colors.grey.shade600,
          size: 26,
        ),
      ),
    );
  }
}
