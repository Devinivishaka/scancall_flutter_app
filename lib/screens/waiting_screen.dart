import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/signaling_service.dart';
import '../services/missed_call_service.dart';
import 'missed_calls_screen.dart';

class WaitingScreen extends StatefulWidget {
  const WaitingScreen({super.key});

  @override
  State<WaitingScreen> createState() => _WaitingScreenState();
}

class _WaitingScreenState extends State<WaitingScreen> {
  String _userId = '…';
  int _unseenMissedCallCount = 0;

  final MissedCallService _missedCallService = MissedCallService();

  @override
  void initState() {
    super.initState();
    _loadUserId();
    _loadUnseenCount();
  }

  @override
  void dispose() {
    _missedCallService.dispose();
    super.dispose();
  }

  Future<void> _loadUserId() async {
    final id = await getUserId();
    if (mounted) setState(() => _userId = id);
  }

  /// Fetch the unseen missed-call badge count from the backend.
  Future<void> _loadUnseenCount() async {
    try {
      final count = await _missedCallService.getUnseenCount();
      if (mounted) setState(() => _unseenMissedCallCount = count);
    } catch (_) {
      // Non-fatal – badge simply stays at 0
    }
  }

  /// Opens the missed-calls screen. On return the badge count is refreshed.
  Future<void> _openMissedCalls() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MissedCallsScreen(
          onSeenCountChanged: () {
            if (mounted) setState(() => _unseenMissedCallCount = 0);
          },
        ),
      ),
    );
    // Re-fetch in case new missed calls arrived while we were in the screen.
    await _loadUnseenCount();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8F0D8),

      body: SafeArea(
        child: Column(
          children: [
            SizedBox(height: 20),
            Row(
              children: [
                SizedBox(width: 20),
                Text(
                  "ScanCall",
                  style: TextStyle(
                    color: Color(0xFF0F1B3F),
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const Spacer(),
                // ── Missed calls badge button ──────────────────────────────
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: GestureDetector(
                    onTap: _openMissedCalls,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: _unseenMissedCallCount > 0
                            ? const Color(0xFFEF4444)
                            : const Color(0xFF0F1B3F),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.phone_missed_rounded,
                              color: Colors.white, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            _unseenMissedCallCount > 0
                                ? 'Missed ($_unseenMissedCallCount)'
                                : 'Missed Calls',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    padding: const EdgeInsets.symmetric(
                      vertical: 40,
                      horizontal: 20,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          "Waiting for Calls",
                          style: TextStyle(
                            color: Color(0xFF0F1B3F),
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          "Your Room ID",
                          style: TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: _userId));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Room ID copied!')),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Color(0xFFD1D5DB)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    _userId,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 13,
                                      color: Color(0xFF0F1B3F),
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(Icons.copy,
                                    size: 18, color: Color(0xFF6B7280)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          "Share this ID with the web caller.\nOpen the web app with ?room=<ID>",
                          style: TextStyle(
                            color: Color(0xFF9CA3AF),
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
