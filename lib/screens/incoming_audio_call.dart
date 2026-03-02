import 'package:flutter/material.dart';

class IncomingAudioCallScreen extends StatelessWidget {
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final String name;
  final String avatar;

  const IncomingAudioCallScreen({
    super.key,
    required this.onAccept,
    required this.onReject,
    required this.name,
    required this.avatar,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8F0D8),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),

            // ---------------- TOP BAR ----------------
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Icon(Icons.arrow_back, size: 22, color: Colors.black87),

                  Text(
                    "Incoming...",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),

                  Icon(
                    Icons.signal_cellular_alt,
                    size: 20,
                    color: Colors.green,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // -------- WHITE INNER CARD ---------
            Expanded(
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // -------- AVATAR ----------
                    CircleAvatar(
                      radius: 45,
                      backgroundImage: NetworkImage(avatar),
                    ),

                    const SizedBox(height: 16),

                    // -------- NAME ----------
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),

                    const SizedBox(height: 6),

                    const Text(
                      "Audio Call",
                      style: TextStyle(color: Colors.black54, fontSize: 14),
                    ),

                    const SizedBox(height: 90),

                    // -------- BUTTONS ----------
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // REJECT
                        GestureDetector(
                          onTap: onReject,
                          child: Container(
                            width: 65,
                            height: 65,
                            decoration: const BoxDecoration(
                              color: Color(0xFFE65A57),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.call_end,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                        ),

                        const SizedBox(width: 50),

                        // ACCEPT
                        GestureDetector(
                          onTap: onAccept,
                          child: Container(
                            width: 65,
                            height: 65,
                            decoration: const BoxDecoration(
                              color: Color(0xFF222A44),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.call,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 60),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
