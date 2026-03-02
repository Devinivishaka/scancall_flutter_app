import 'package:flutter/material.dart';
import 'package:scancall_mobile_app/screens/waiting_screen.dart';

class CallEndedScreen extends StatelessWidget {
  final String callerName;
  final String duration;
  final String avatarUrl;

  const CallEndedScreen({
    super.key,
    required this.callerName,
    required this.duration,
    required this.avatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8F0D8),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Icon(Icons.arrow_back, color: Colors.black87),
                  Text(
                    "Call Ended",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1B1E3C),
                    ),
                  ),
                  Icon(Icons.signal_cellular_alt, color: Colors.black87),
                ],
              ),
            ),

            const SizedBox(height: 10),

            Expanded(
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 60),

                    // PROFILE IMAGE
                    CircleAvatar(
                      radius: 48,
                      backgroundImage: NetworkImage(avatarUrl),
                    ),

                    const SizedBox(height: 20),

                    // TITLE
                    const Text(
                      "Call Ended",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1B1E3C),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // CALLER NAME
                    Text(
                      callerName,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.black54,
                      ),
                    ),

                    const SizedBox(height: 12),

                    // DURATION
                    Text(
                      duration,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black45,
                      ),
                    ),

                    const Spacer(),

                    // BACK BUTTON
                    Padding(
                      padding: const EdgeInsets.only(bottom: 40),
                      child: GestureDetector(
                        onTap: () => Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const WaitingScreen(),
                          ),
                          (route) => false,
                        ),

                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 40,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1B1E3C),
                            borderRadius: BorderRadius.circular(50),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(
                                Icons.arrow_back,
                                color: Colors.white,
                                size: 18,
                              ),
                              SizedBox(width: 10),
                              Text(
                                "Back to Home",
                                style: TextStyle(
                                  fontSize: 15,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
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
}
