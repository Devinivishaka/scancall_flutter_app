import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// Keep this in sync with SignalingService._backendBaseUrl
const String _kBackendBaseUrl = 'http://192.168.1.31:8080';

/// A lightweight data class representing a single missed call entry.
class MissedCall {
  final String callId;
  final String callerId;
  final String callType; // 'AUDIO' or 'VIDEO'
  final DateTime createdAt;
  final DateTime? seenAt; // null = not yet seen by the user

  /// Why the call was missed:
  ///  - 'MISSED'           → ring timed out, callee never answered
  ///  - 'CALLER_CANCELLED' → caller hung up before callee could answer
  final String endReason;

  const MissedCall({
    required this.callId,
    required this.callerId,
    required this.callType,
    required this.createdAt,
    this.seenAt,
    required this.endReason,
  });

  bool get isUnseen => seenAt == null;

  /// Human-readable label for why the call was not answered.
  String get missedReason {
    switch (endReason) {
      case 'CALLER_CANCELLED':
        return 'Caller hung up';
      case 'MISSED':
      default:
        return 'No answer';
    }
  }

  factory MissedCall.fromJson(Map<String, dynamic> json) {
    return MissedCall(
      callId: json['callId'] as String,
      callerId: json['callerId'] as String,
      callType: (json['callType'] as String?)?.toUpperCase() ?? 'AUDIO',
      createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
      seenAt: json['seenAt'] != null
          ? DateTime.parse(json['seenAt'] as String).toLocal()
          : null,
      endReason: (json['endReason'] as String?) ?? 'MISSED',
    );
  }
}

/// HTTP service that talks to /api/calls/missed/* on the backend.
class MissedCallService {
  final http.Client _client;

  MissedCallService({http.Client? client}) : _client = client ?? http.Client();

  // ── Public API ────────────────────────────────────────────────────────────

  /// Fetches the full list of missed calls for the current user.
  Future<List<MissedCall>> getMissedCalls() async {
    final userId = await _currentUserId();
    final uri = Uri.parse('$_kBackendBaseUrl/api/calls/missed/$userId');

    final response = await _client
        .get(uri, headers: _jsonHeaders)
        .timeout(const Duration(seconds: 10));

    _assertOk(response, 'Failed to fetch missed calls');

    final jsonList = jsonDecode(response.body) as List<dynamic>;
    return jsonList
        .map((e) => MissedCall.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Returns how many missed calls are still unseen for the current user.
  Future<int> getUnseenCount() async {
    final userId = await _currentUserId();
    final uri =
        Uri.parse('$_kBackendBaseUrl/api/calls/missed/$userId/count');

    final response = await _client
        .get(uri, headers: _jsonHeaders)
        .timeout(const Duration(seconds: 10));

    _assertOk(response, 'Failed to fetch unseen count');

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (body['unseenCount'] as num).toInt();
  }

  /// Marks all unseen missed calls as seen on the backend.
  /// Call this when the user opens the missed-calls screen.
  Future<void> markAllSeen() async {
    final userId = await _currentUserId();
    final uri =
        Uri.parse('$_kBackendBaseUrl/api/calls/missed/$userId/mark-seen');

    final response = await _client
        .patch(uri, headers: _jsonHeaders)
        .timeout(const Duration(seconds: 10));

    _assertOk(response, 'Failed to mark missed calls as seen');
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static const Map<String, String> _jsonHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  Future<String> _currentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('userId');
    if (id == null || id.isEmpty) {
      throw StateError('userId not found in SharedPreferences');
    }
    return id;
  }

  void _assertOk(http.Response response, String message) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        '$message — HTTP ${response.statusCode}: ${response.body}',
      );
    }
  }

  void dispose() => _client.close();
}
