import 'package:flutter/material.dart';
import '../services/missed_call_service.dart';

/// Displays the full list of missed calls for the current user.
///
/// On open it:
///  1. Fetches missed calls from the backend.
///  2. Immediately marks all as seen (PATCH mark-seen).
///  3. Notifies the caller via [onSeenCountChanged] so the badge can be cleared.
class MissedCallsScreen extends StatefulWidget {
  /// Called after the screen successfully marks calls as seen.
  /// The parent widget should use this to update the unseen badge count.
  final VoidCallback? onSeenCountChanged;

  const MissedCallsScreen({super.key, this.onSeenCountChanged});

  @override
  State<MissedCallsScreen> createState() => _MissedCallsScreenState();
}

class _MissedCallsScreenState extends State<MissedCallsScreen> {
  final MissedCallService _service = MissedCallService();

  List<MissedCall> _calls = [];
  bool _isLoading = true;
  String? _errorMessage;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadAndMarkSeen();
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  // ── Data loading ───────────────────────────────────────────────────────────

  Future<void> _loadAndMarkSeen() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Fetch and mark-seen concurrently to minimise total wait time.
      final results = await Future.wait([
        _service.getMissedCalls(),
        _service.markAllSeen(),
      ]);

      final calls = results[0] as List<MissedCall>;

      if (mounted) {
        setState(() {
          _calls = calls;
          _isLoading = false;
        });
        // Notify parent to reset badge
        widget.onSeenCountChanged?.call();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    return '${dt.day}/${dt.month}/${dt.year}';
  }

  String _formatFullTime(DateTime dt) =>
      '${dt.day}/${dt.month}/${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  IconData _callTypeIcon(String callType) =>
      callType == 'VIDEO' ? Icons.videocam_rounded : Icons.phone_missed_rounded;

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8F0D8),
      appBar: AppBar(
        backgroundColor: const Color(0xFFE8F0D8),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Color(0xFF0F1B3F)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Missed Calls',
          style: TextStyle(
            color: Color(0xFF0F1B3F),
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF0F1B3F)),
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadAndMarkSeen,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF0F1B3F)),
      );
    }

    if (_errorMessage != null) {
      return _ErrorView(
        message: _errorMessage!,
        onRetry: _loadAndMarkSeen,
      );
    }

    if (_calls.isEmpty) {
      return const _EmptyView();
    }

    return RefreshIndicator(
      color: const Color(0xFF0F1B3F),
      onRefresh: _loadAndMarkSeen,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: _calls.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) =>
            _MissedCallTile(call: _calls[index], formatTime: _formatTime, formatFullTime: _formatFullTime, callTypeIcon: _callTypeIcon),
      ),
    );
  }
}

// ── Tile ─────────────────────────────────────────────────────────────────────

class _MissedCallTile extends StatelessWidget {
  final MissedCall call;
  final String Function(DateTime) formatTime;
  final String Function(DateTime) formatFullTime;
  final IconData Function(String) callTypeIcon;

  const _MissedCallTile({
    required this.call,
    required this.formatTime,
    required this.formatFullTime,
    required this.callTypeIcon,
  });

  @override
  Widget build(BuildContext context) {
    // Unseen calls get a subtle highlight
    final bool isNew = call.isUnseen;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isNew
            ? Border.all(color: const Color(0xFFEF4444), width: 1.5)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showDetails(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                // Avatar circle
                Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFEE2E2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    callTypeIcon(call.callType),
                    color: const Color(0xFFEF4444),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),

                // Caller info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.phone_missed_rounded,
                              color: Color(0xFFEF4444), size: 14),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              call.callerId,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: isNew
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: const Color(0xFF0F1B3F),
                              ),
                            ),
                          ),
                          if (isNew) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEF4444),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'NEW',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${call.callType == 'VIDEO' ? 'Video' : 'Audio'} • ${call.missedReason}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ),

                // Timestamp
                Text(
                  formatTime(call.createdAt),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDetails(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _CallDetailSheet(
        call: call,
        formatFullTime: formatFullTime,
        callTypeIcon: callTypeIcon,
      ),
    );
  }
}

// ── Detail bottom sheet ───────────────────────────────────────────────────────

class _CallDetailSheet extends StatelessWidget {
  final MissedCall call;
  final String Function(DateTime) formatFullTime;
  final IconData Function(String) callTypeIcon;

  const _CallDetailSheet({
    required this.call,
    required this.formatFullTime,
    required this.callTypeIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFE5E7EB),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),

          // Icon
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: Color(0xFFFEE2E2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              callTypeIcon(call.callType),
              color: const Color(0xFFEF4444),
              size: 36,
            ),
          ),
          const SizedBox(height: 16),

          // Caller ID
          Text(
            call.callerId,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F1B3F),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Missed call',
            style: TextStyle(color: Color(0xFFEF4444), fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            call.missedReason,
            style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
          ),
          const SizedBox(height: 24),

          // Details rows
          _DetailRow(
            icon: Icons.access_time_rounded,
            label: 'Time',
            value: formatFullTime(call.createdAt),
          ),
          const SizedBox(height: 12),
          _DetailRow(
            icon: call.callType == 'VIDEO'
                ? Icons.videocam_rounded
                : Icons.phone_rounded,
            label: 'Type',
            value: call.callType == 'VIDEO' ? 'Video call' : 'Audio call',
          ),
          const SizedBox(height: 12),
          _DetailRow(
            icon: Icons.visibility_rounded,
            label: 'Status',
            value: call.seenAt != null
                ? 'Seen at ${formatFullTime(call.seenAt!)}'
                : 'Not yet seen',
          ),
          const SizedBox(height: 12),
          _DetailRow(
            icon: Icons.tag_rounded,
            label: 'Call ID',
            value: call.callId,
            small: true,
          ),
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F1B3F),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool small;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: const Color(0xFF6B7280)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF9CA3AF),
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: small ? 11 : 14,
                  color: const Color(0xFF0F1B3F),
                  fontWeight: FontWeight.w500,
                  fontFamily: small ? 'monospace' : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.phone_missed_rounded,
                size: 48,
                color: Color(0xFFD1D5DB),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No missed calls',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0F1B3F),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "You're all caught up!",
              style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Error state ───────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.cloud_off_rounded,
                size: 48,
                color: Color(0xFFEF4444),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Could not load calls',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0F1B3F),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F1B3F),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try Again'),
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
