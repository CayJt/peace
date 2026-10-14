import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Best-effort uploads from the reader app to the backend so the admin console has data:
/// heartbeat (realtime users), murajaah session summaries (leaderboard) and feedback.
/// Nothing here may ever break reading, so every call swallows network errors.
class UserTelemetry {
  UserTelemetry({
    http.Client? client,
    required this.baseUrl,
    required this.tokenProvider,
    this.appVersion = '',
    this.heartbeatEvery = const Duration(minutes: 2),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  final Future<String?> Function() tokenProvider;
  final String appVersion;
  final Duration heartbeatEvery;
  Timer? _timer;

  Future<Map<String, String>?> _auth() async {
    final t = await tokenProvider();
    return t == null ? null : {'Authorization': 'Bearer $t', 'Content-Type': 'application/json'};
  }

  void start() {
    _timer?.cancel();
    heartbeat();
    _timer = Timer.periodic(heartbeatEvery, (_) => heartbeat());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<bool> heartbeat() async {
    try {
      final h = await _auth();
      if (h == null) return false;
      return (await _client.post(Uri.parse('$baseUrl/api/v1/heartbeat'), headers: h)).statusCode == 204;
    } on Exception {
      return false;
    }
  }

  Future<bool> uploadSession({
    required int page,
    required int durationSec,
    required int lettersEvaluated,
    required double score,
    required int khatamCount,
  }) async {
    try {
      final h = await _auth();
      if (h == null) return false;
      final r = await _client.post(Uri.parse('$baseUrl/api/v1/murajaah/sessions'),
          headers: h,
          body: jsonEncode({
            'page': page,
            'duration_sec': durationSec,
            'letters_evaluated': lettersEvaluated,
            'score': score.clamp(0.0, 1.0),
            'khatam_count': khatamCount,
          }));
      return r.statusCode == 201;
    } on Exception {
      return false;
    }
  }

  /// Returns null on success, else a user-facing error message.
  Future<String?> sendFeedback(String category, String message) async {
    try {
      final h = await _auth() ?? {'Content-Type': 'application/json'};
      final r = await _client.post(Uri.parse('$baseUrl/api/v1/feedback'),
          headers: h, body: jsonEncode({'category': category, 'message': message, 'app_version': appVersion}));
      if (r.statusCode == 201) return null;
      if (r.statusCode == 429) return 'Terlalu banyak kiriman, coba lagi nanti';
      return 'Gagal mengirim (${r.statusCode})';
    } on Exception {
      return 'Tidak dapat terhubung ke server';
    }
  }
}
