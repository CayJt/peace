import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quran_app/bloc/admin/admin_auth_bloc.dart';
import 'package:quran_app/services/admin_api_service.dart';

const allPerms = ['analytics.view', 'users.view', 'config.manage', 'chats.view', 'murajaah.view', 'feedback.manage', 'admins.manage'];

class FakeSessionStore implements AdminSessionStore {
  String? token;
  @override
  Future<String?> read() async => token;
  @override
  Future<void> write(String t) async => token = t;
  @override
  Future<void> clear() async => token = null;
}

/// In-memory stand-in for the FastAPI admin backend (just enough behaviour for UI flows).
class FakeAdminBackend {
  FakeAdminBackend() {
    admins = [
      _admin(1, 'admin', 'super_admin', allPerms, 'Super Admin'),
      _admin(2, 'editor1', 'custom', ['feedback.manage', 'analytics.view'], 'Editor Satu'),
      _admin(3, 'auditor1', 'auditor', ['chats.view', 'users.view', 'murajaah.view', 'analytics.view'], 'Auditor Satu'),
    ];
  }

  late List<Map<String, dynamic>> admins;
  final passwords = {'admin': 'SuperSecret1', 'editor1': 'EditorPass1', 'auditor1': 'AuditorPass1'};
  String provider = 'quran.com';
  final calls = <String>[]; // "METHOD /path"
  Map<String, dynamic>? lastBody;
  int unauthorizedAfter = -1; // force 401 on every call after N calls (-1 = never)
  bool kemenagReachable = true;

  List<Map<String, dynamic>> feedbacks = [
    _fb(1, 'bug', 'Tombol mic tidak berfungsi', 'open'),
    _fb(2, 'suggestion', 'Tambah mode malam', 'in_progress'),
    _fb(3, 'content', 'Terjemahan ayat 2:3 terpotong', 'resolved'),
  ];

  static Map<String, dynamic> _admin(int id, String u, String role, List<String> perms, String name) => {
        'id': id, 'username': u, 'email': '$u@x.co', 'full_name': name, 'role': role, 'is_active': true,
        'is_primary': id == 1, 'permissions': perms, 'created_at': '2026-01-01T00:00:00Z', 'updated_at': '2026-01-01T00:00:00Z',
      };

  static Map<String, dynamic> _fb(int id, String cat, String msg, String status) => {
        'id': id, 'user_id': id == 1 ? 'anonymous' : '$id', 'category': cat, 'message': msg, 'app_version': '1.0.0',
        'status': status, 'admin_notes': '', 'created_at': '2026-02-01T10:00:00Z', 'updated_at': '2026-02-01T10:00:00Z',
      };

  Map<String, dynamic>? _me(http.Request r) {
    final h = r.headers['Authorization'];
    if (h == null || !h.startsWith('Bearer tok-')) return null;
    final id = int.tryParse(h.substring(11));
    return admins.where((a) => a['id'] == id).firstOrNull;
  }

  http.Response _json(Object body, [int code = 200]) =>
      http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

  late final MockClient client = MockClient((req) async {
    final path = req.url.path.replaceFirst('/api/v1/admin', '');
    calls.add('${req.method} $path');
    lastBody = req.body.isEmpty ? null : jsonDecode(req.body) as Map<String, dynamic>;
    final body = lastBody;

    if (path == '/auth/login') {
      final u = body!['username'] as String;
      final a = admins.where((x) => x['username'] == u && x['is_active'] == true).firstOrNull;
      if (a == null || passwords[u] != body['password']) return _json({'detail': 'invalid credentials'}, 401);
      return _json({'token': 'tok-${a['id']}', 'token_type': 'bearer', 'admin': a, 'permissions': a['permissions']});
    }
    final me = _me(req);
    if (me == null || (unauthorizedAfter >= 0 && calls.length > unauthorizedAfter)) {
      return _json({'detail': 'invalid or expired token'}, 401);
    }
    bool has(String k) => me['role'] == 'super_admin' || (me['permissions'] as List).contains(k);
    http.Response guard(String k, http.Response Function() ok) => has(k) ? ok() : _json({'detail': 'missing permission: $k'}, 403);

    switch ((req.method, path)) {
      case ('GET', '/auth/me'):
        return _json(me);
      case ('GET', '/permissions-list'):
        return _json({'permissions': [for (final k in allPerms) {'key': k, 'label': 'Izin $k'}]});
      case ('GET', '/analytics/realtime'):
        return guard('analytics.view', () => _json({'active_users': 7, 'active_ws_connections': 2, 'window_seconds': 300, 'pending_feedback': feedbacks.where((f) => f['status'] == 'open').length}));
      case ('GET', '/users/stats'):
        return guard('users.view', () => _json({
              'total_users': 120, 'new_last_7d': 9, 'new_last_30d': 30,
              'trend': [for (var i = 0; i < 30; i++) {'date': '2026-03-${(i + 1).toString().padLeft(2, '0')}', 'count': i % 4}],
            }));
      case ('GET', '/analytics/leaderboard'):
        return guard('users.view', () => _json({'sort': 'score', 'entries': [
              {'rank': 1, 'user_id': 5, 'name': 'Aisyah', 'email': 'ai***@x.co', 'avg_score': 0.93, 'letters_evaluated': 900, 'sessions': 12, 'khatam_count': 1, 'last_active': '2026-03-01T00:00:00Z'},
              {'rank': 2, 'user_id': 6, 'name': 'Budi', 'email': 'bu***@x.co', 'avg_score': 0.81, 'letters_evaluated': 400, 'sessions': 5, 'khatam_count': 0, 'last_active': '2026-03-01T00:00:00Z'},
            ]}));
      case ('GET', '/murajaah/sessions'):
        return guard('murajaah.view', () => _json({'total': 1, 'items': [
              {'id': 1, 'user_id': 5, 'name': 'Aisyah', 'page': 3, 'duration_sec': 61, 'letters_evaluated': 120, 'score': 0.9, 'created_at': '2026-03-01T08:00:00Z'},
            ]}));
      case ('GET', '/config/quran-provider'):
        return guard('config.manage', () => _json({'provider': provider, 'available': ['quran.com', 'kemenag'], 'adapter_implemented': {'quran.com': true, 'kemenag': false}}));
      case ('PUT', '/config/quran-provider'):
        return guard('config.manage', () {
          provider = body!['provider'] as String;
          return _json({'provider': provider, 'available': ['quran.com', 'kemenag'], 'adapter_implemented': {'quran.com': true, 'kemenag': false}});
        });
      case ('GET', '/config/quran-provider/health'):
        return guard('config.manage', () => _json({'providers': {
              'quran.com': {'ok': true, 'status_code': 200, 'latency_ms': 120, 'error': null},
              'kemenag': kemenagReachable
                  ? {'ok': true, 'status_code': 200, 'latency_ms': 1500, 'error': null}
                  : {'ok': false, 'status_code': null, 'latency_ms': null, 'error': 'ConnectError'},
            }}));
      case ('POST', '/config/cache/clear'):
        return guard('config.manage', () => _json({'cleared_entries': 4}));
      case ('GET', '/chats/history'):
        return guard('chats.view', () => _json({'total': 2, 'guardrail_total': 1, 'all_total': 2, 'items': [
              {'id': 2, 'user_id': 'anonymous', 'question': 'Harga bitcoin?', 'answer': 'Maaf, saya hanya dapat menjawab …', 'referenced_verses': [], 'is_guardrail_triggered': true, 'created_at': '2026-03-01T09:00:00Z'},
              {'id': 1, 'user_id': '5', 'question': 'Makna Al-Fatihah 1:1', 'answer': 'Pembuka kitab.', 'referenced_verses': [
                {'verse_key': '1:1', 'text': 'بِسْمِ ٱللَّهِ', 'translation': 'Dengan nama Allah'}], 'is_guardrail_triggered': false, 'created_at': '2026-03-01T08:00:00Z'},
            ]}));
    }
    if (req.method == 'GET' && path == '/feedback') {
      return guard('feedback.manage', () {
        final counts = {'open': 0, 'in_progress': 0, 'resolved': 0, 'discarded': 0};
        for (final f in feedbacks) {
          counts[f['status'] as String] = counts[f['status']]! + 1;
        }
        return _json({'counts': counts, 'items': feedbacks});
      });
    }
    final fb = RegExp(r'^/feedback/(\d+)$').firstMatch(path);
    if (req.method == 'PATCH' && fb != null) {
      return guard('feedback.manage', () {
        final f = feedbacks.firstWhere((x) => x['id'] == int.parse(fb.group(1)!));
        if (body!.containsKey('status')) f['status'] = body['status'];
        if (body.containsKey('admin_notes')) f['admin_notes'] = body['admin_notes'];
        return _json(f);
      });
    }
    if (path == '/administrators' || path.startsWith('/administrators/')) {
      if (!has('admins.manage') && !path.endsWith('/password')) return _json({'detail': 'missing permission: admins.manage'}, 403);
      if (req.method == 'GET') return _json({'administrators': admins});
      if (req.method == 'POST') {
        if (admins.any((a) => a['username'] == body!['username'])) return _json({'detail': 'username or email already exists'}, 409);
        final a = _admin(admins.length + 1, body!['username'], body['role'], (body['permissions'] as List?)?.cast<String>() ?? [], body['full_name']);
        admins.add(a);
        return _json(a, 201);
      }
      final m = RegExp(r'^/administrators/(\d+)(/password)?$').firstMatch(path)!;
      final id = int.parse(m.group(1)!);
      final a = admins.firstWhere((x) => x['id'] == id);
      if (m.group(2) != null) {
        if (me['role'] != 'super_admin' && me['id'] != id) return _json({'detail': 'only a super admin or the account owner can set this password'}, 403);
        if (me['id'] == id && passwords[a['username']] != body!['current_password']) return _json({'detail': 'current password is incorrect'}, 403);
        passwords[a['username'] as String] = body!['new_password'] as String;
        return http.Response('', 204);
      }
      if (req.method == 'PUT') {
        body!.forEach((k, v) => a[k] = v);
        return _json(a);
      }
      if (req.method == 'DELETE') {
        if (a['is_primary'] == true) return _json({'detail': 'the primary super admin cannot be deleted'}, 403);
        admins.remove(a);
        return http.Response('', 204);
      }
    }
    return _json({'detail': 'not found'}, 404);
  });

  AdminApiService api() => AdminApiService(baseUrl: 'http://fake', client: client);
}
