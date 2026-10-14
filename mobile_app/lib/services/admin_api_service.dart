import 'dart:convert';

import 'package:http/http.dart' as http;

class AdminApiException implements Exception {
  final int statusCode;
  final String message;
  AdminApiException(this.statusCode, this.message);

  bool get unauthorized => statusCode == 401;
  bool get forbidden => statusCode == 403;

  @override
  String toString() => message;
}

class AdminProfile {
  final int id;
  final String username, email, fullName, role;
  final bool isActive, isPrimary;
  final Set<String> permissions;
  final String? createdAt;

  const AdminProfile({
    required this.id,
    required this.username,
    required this.email,
    required this.fullName,
    required this.role,
    required this.isActive,
    required this.permissions,
    this.isPrimary = false,
    this.createdAt,
  });

  bool get isSuper => role == 'super_admin';
  bool can(String key) => isSuper || permissions.contains(key);

  factory AdminProfile.fromJson(Map<String, dynamic> j) => AdminProfile(
        id: j['id'] as int,
        username: j['username'] as String,
        email: j['email'] as String,
        fullName: j['full_name'] as String,
        role: j['role'] as String,
        isActive: j['is_active'] as bool,
        isPrimary: (j['is_primary'] as bool?) ?? false,
        permissions: {...(j['permissions'] as List).cast<String>()},
        createdAt: j['created_at'] as String?,
      );
}

class FeedbackItem {
  final int id;
  final String userId, category, message, appVersion, status, adminNotes, createdAt;
  const FeedbackItem(this.id, this.userId, this.category, this.message, this.appVersion, this.status,
      this.adminNotes, this.createdAt);

  factory FeedbackItem.fromJson(Map<String, dynamic> j) => FeedbackItem(
      j['id'], j['user_id'], j['category'], j['message'], j['app_version'], j['status'], j['admin_notes'], j['created_at']);
}

class Permission {
  final String key, label;
  const Permission(this.key, this.label);
}

/// REST client for `/api/v1/admin/*`. Token is supplied lazily so the auth bloc owns the session.
class AdminApiService {
  AdminApiService({required this.baseUrl, http.Client? client, this.tokenProvider})
      : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  String? Function()? tokenProvider;

  Uri _u(String path, [Map<String, String?>? q]) => Uri.parse('$baseUrl/api/v1/admin$path').replace(
      queryParameters: {for (final e in (q ?? {}).entries) if (e.value != null) e.key: e.value!});

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (tokenProvider?.call() != null) 'Authorization': 'Bearer ${tokenProvider!.call()}',
      };

  Future<dynamic> _send(Future<http.Response> Function() f) async {
    final http.Response r;
    try {
      r = await f();
    } on http.ClientException catch (e) {
      throw AdminApiException(0, 'Tidak dapat terhubung ke server (${e.message})');
    }
    if (r.statusCode == 204) return null;
    dynamic body;
    try {
      body = r.body.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
    } on FormatException {
      body = null;
    }
    if (r.statusCode >= 200 && r.statusCode < 300) return body;
    var msg = 'Permintaan gagal (${r.statusCode})';
    if (body is Map && body['detail'] is String) {
      msg = body['detail'] as String;
    } else if (body is Map && body['detail'] is List && (body['detail'] as List).isNotEmpty) {
      final d = (body['detail'] as List).first;
      msg = d is Map ? '${d['msg']}'.replaceFirst('Value error, ', '') : '$d';
    }
    throw AdminApiException(r.statusCode, msg);
  }

  Future<dynamic> _get(String p, [Map<String, String?>? q]) => _send(() => _client.get(_u(p, q), headers: _headers));
  Future<dynamic> _post(String p, [Object? b]) =>
      _send(() => _client.post(_u(p), headers: _headers, body: b == null ? null : jsonEncode(b)));
  Future<dynamic> _put(String p, Object b) => _send(() => _client.put(_u(p), headers: _headers, body: jsonEncode(b)));
  Future<dynamic> _patch(String p, Object b) => _send(() => _client.patch(_u(p), headers: _headers, body: jsonEncode(b)));
  Future<dynamic> _delete(String p) => _send(() => _client.delete(_u(p), headers: _headers));

  // ---- auth
  /// Returns (token, profile).
  Future<(String, AdminProfile)> login(String username, String password) async {
    final j = await _post('/auth/login', {'username': username.trim(), 'password': password}) as Map<String, dynamic>;
    return (j['token'] as String, AdminProfile.fromJson(j['admin'] as Map<String, dynamic>));
  }

  Future<AdminProfile> me() async => AdminProfile.fromJson(await _get('/auth/me') as Map<String, dynamic>);

  Future<List<Permission>> permissionsList() async => [
        for (final p in (await _get('/permissions-list'))['permissions'] as List) Permission(p['key'], p['label']),
      ];

  // ---- analytics
  Future<Map<String, dynamic>> realtime() async => await _get('/analytics/realtime') as Map<String, dynamic>;
  Future<Map<String, dynamic>> userStats({int days = 30}) async =>
      await _get('/users/stats', {'days': '$days'}) as Map<String, dynamic>;
  Future<Map<String, dynamic>> leaderboard({String sort = 'score'}) async =>
      await _get('/analytics/leaderboard', {'sort': sort}) as Map<String, dynamic>;
  Future<Map<String, dynamic>> murajaahSessions({int limit = 50}) async =>
      await _get('/murajaah/sessions', {'limit': '$limit'}) as Map<String, dynamic>;

  // ---- config
  Future<Map<String, dynamic>> quranProvider() async => await _get('/config/quran-provider') as Map<String, dynamic>;
  Future<Map<String, dynamic>> setQuranProvider(String p) async =>
      await _put('/config/quran-provider', {'provider': p}) as Map<String, dynamic>;
  Future<Map<String, dynamic>> providerHealth() async =>
      await _get('/config/quran-provider/health') as Map<String, dynamic>;
  Future<int> clearCache() async => (await _post('/config/cache/clear'))['cleared_entries'] as int;

  // ---- chats / feedback
  Future<Map<String, dynamic>> chatHistory({bool guardrailOnly = false, String? q, int offset = 0}) async =>
      await _get('/chats/history', {
        'guardrail_only': guardrailOnly ? 'true' : null,
        'q': (q == null || q.isEmpty) ? null : q,
        'offset': '$offset',
      }) as Map<String, dynamic>;

  Future<({Map<String, int> counts, List<FeedbackItem> items})> feedback() async {
    final j = await _get('/feedback') as Map<String, dynamic>;
    return (
      counts: (j['counts'] as Map).map((k, v) => MapEntry(k as String, v as int)),
      items: [for (final i in j['items'] as List) FeedbackItem.fromJson(i as Map<String, dynamic>)],
    );
  }

  Future<FeedbackItem> patchFeedback(int id, {String? status, String? notes}) async => FeedbackItem.fromJson(
      await _patch('/feedback/$id', {if (status != null) 'status': status, if (notes != null) 'admin_notes': notes})
          as Map<String, dynamic>);

  // ---- administrators
  Future<List<AdminProfile>> administrators() async => [
        for (final a in (await _get('/administrators'))['administrators'] as List)
          AdminProfile.fromJson(a as Map<String, dynamic>)
      ];

  Future<AdminProfile> createAdmin({
    required String username,
    required String email,
    required String fullName,
    required String password,
    required String role,
    List<String>? permissions,
  }) async =>
      AdminProfile.fromJson(await _post('/administrators', {
        'username': username.trim(),
        'email': email.trim(),
        'full_name': fullName.trim(),
        'password': password,
        'role': role,
        if (permissions != null) 'permissions': permissions,
      }) as Map<String, dynamic>);

  Future<AdminProfile> updateAdmin(int id, {String? fullName, String? email, String? role, bool? isActive, List<String>? permissions}) async =>
      AdminProfile.fromJson(await _put('/administrators/$id', {
        if (fullName != null) 'full_name': fullName,
        if (email != null) 'email': email,
        if (role != null) 'role': role,
        if (isActive != null) 'is_active': isActive,
        if (permissions != null) 'permissions': permissions,
      }) as Map<String, dynamic>);

  Future<void> setPassword(int id, String newPassword, {String? currentPassword}) =>
      _put('/administrators/$id/password', {
        'new_password': newPassword,
        if (currentPassword != null) 'current_password': currentPassword,
      });

  Future<void> deleteAdmin(int id) => _delete('/administrators/$id');
}
