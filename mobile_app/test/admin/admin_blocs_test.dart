import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app/bloc/admin/admin_analytics_bloc.dart';
import 'package:quran_app/bloc/admin/admin_auth_bloc.dart';
import 'package:quran_app/bloc/admin/admin_config_bloc.dart';
import 'package:quran_app/bloc/admin/admin_feedback_bloc.dart';
import 'package:quran_app/bloc/admin/admin_management_bloc.dart';

import 'fake_backend.dart';

void main() {
  late FakeAdminBackend be;
  late FakeSessionStore store;
  late AdminAuthBloc auth;

  setUp(() {
    be = FakeAdminBackend();
    store = FakeSessionStore();
    auth = AdminAuthBloc(api: be.api(), store: store);
  });
  tearDown(() => auth.close());

  group('AdminAuthBloc', () {
    test('login success stores the token and exposes permissions', () async {
      auth.add(const AdminLoginRequested('admin', 'SuperSecret1'));
      await expectLater(auth.stream, emitsThrough(predicate<AdminAuthState>((s) => s.status == AdminAuthStatus.authenticated)));
      expect(store.token, 'tok-1');
      expect(auth.state.can('admins.manage'), isTrue);
      expect(auth.state.profile!.isSuper, isTrue);
    });

    test('wrong password shows a friendly error and stores nothing', () async {
      auth.add(const AdminLoginRequested('admin', 'nope'));
      await expectLater(auth.stream, emitsThrough(predicate<AdminAuthState>((s) => s.error == 'Username atau kata sandi salah')));
      expect(store.token, isNull);
      expect(auth.state.status, AdminAuthStatus.unauthenticated);
    });

    test('restores a valid session; drops an invalid one', () async {
      store.token = 'tok-3';
      auth.add(const AdminSessionRestoreRequested());
      await expectLater(auth.stream, emitsThrough(predicate<AdminAuthState>((s) => s.status == AdminAuthStatus.authenticated && s.profile!.username == 'auditor1')));
      expect(auth.state.can('chats.view'), isTrue);
      expect(auth.state.can('config.manage'), isFalse);

      final bad = AdminAuthBloc(api: be.api(), store: FakeSessionStore()..token = 'garbage');
      bad.add(const AdminSessionRestoreRequested());
      await expectLater(bad.stream, emitsThrough(predicate<AdminAuthState>((s) => s.status == AdminAuthStatus.unauthenticated)));
      await bad.close();
    });

    test('no stored token => unauthenticated without calling the server', () async {
      auth.add(const AdminSessionRestoreRequested());
      await expectLater(auth.stream, emits(predicate<AdminAuthState>((s) => s.status == AdminAuthStatus.unauthenticated)));
      expect(be.calls, isEmpty);
    });

    test('logout and expiry clear the stored token', () async {
      auth.add(const AdminLoginRequested('admin', 'SuperSecret1'));
      await expectLater(auth.stream, emitsThrough(predicate<AdminAuthState>((s) => s.status == AdminAuthStatus.authenticated)));
      auth.add(const AdminSessionExpired());
      await expectLater(auth.stream, emits(predicate<AdminAuthState>((s) => s.error != null && s.status == AdminAuthStatus.unauthenticated)));
      expect(store.token, isNull);
    });
  });

  Future<void> signIn(String u, String p) async {
    auth.add(AdminLoginRequested(u, p));
    await auth.stream.firstWhere((s) => s.status == AdminAuthStatus.authenticated);
  }

  group('analytics', () {
    test('loads only what the permissions allow', () async {
      await signIn('editor1', 'EditorPass1');
      final bloc = AdminAnalyticsBloc(auth.api, pollInterval: Duration.zero);
      bloc.add(const AnalyticsStarted(analytics: true, users: false, leaderboard: false, murajaah: false));
      await bloc.stream.firstWhere((s) => !s.loading && s.updates > 0);
      expect(bloc.state.realtime!['active_users'], 7);
      expect(be.calls.any((c) => c.contains('/users/stats')), isFalse);
      await bloc.close();
    });

    test('403 for a section surfaces an error but keeps other data', () async {
      await signIn('editor1', 'EditorPass1');
      final bloc = AdminAnalyticsBloc(auth.api, pollInterval: Duration.zero);
      bloc.add(const AnalyticsStarted(analytics: true, users: true, leaderboard: false, murajaah: false)); // editor lacks users.view
      await bloc.stream.firstWhere((s) => !s.loading && s.updates > 0);
      expect(bloc.state.error, contains('users.view'));
      expect(bloc.state.realtime, isNotNull);
      await bloc.close();
    });

    test('polling refreshes realtime data on a timer', () async {
      await signIn('admin', 'SuperSecret1');
      final bloc = AdminAnalyticsBloc(auth.api, pollInterval: const Duration(milliseconds: 30));
      bloc.add(const AnalyticsStarted(users: false, leaderboard: false, murajaah: false));
      await bloc.stream.firstWhere((s) => s.updates >= 3);
      expect(be.calls.where((c) => c == 'GET /analytics/realtime').length, greaterThanOrEqualTo(3));
      await bloc.close();
      final n = be.calls.length;
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(be.calls.length, n, reason: 'timer must stop on close');
    });

    test('401 triggers the session-expired callback', () async {
      await signIn('admin', 'SuperSecret1');
      be.unauthorizedAfter = be.calls.length;
      var expired = 0;
      final bloc = AdminAnalyticsBloc(auth.api, pollInterval: Duration.zero, onUnauthorized: () => expired++);
      bloc.add(const AnalyticsStarted(users: false, leaderboard: false, murajaah: false));
      await bloc.stream.firstWhere((s) => s.error != null);
      expect(expired, greaterThan(0));
      await bloc.close();
    });

    test('sort change reloads the leaderboard', () async {
      await signIn('admin', 'SuperSecret1');
      final bloc = AdminAnalyticsBloc(auth.api, pollInterval: Duration.zero);
      bloc.add(const AnalyticsStarted(analytics: false, users: false, murajaah: false));
      await bloc.stream.firstWhere((s) => s.updates > 0);
      bloc.add(const LeaderboardSortChanged('khatam'));
      await bloc.stream.firstWhere((s) => s.sort == 'khatam');
      await pumpEventQueue();
      expect(be.calls.where((c) => c == 'GET /analytics/leaderboard').length, 2);
      await bloc.close();
    });
  });

  group('config', () {
    test('switching provider persists on the server and announces it', () async {
      await signIn('admin', 'SuperSecret1');
      final bloc = AdminConfigBloc(auth.api);
      bloc.add(const ConfigLoaded());
      await bloc.stream.firstWhere((s) => s.provider == 'quran.com' && !s.loading && s.health.isNotEmpty && !s.checking);
      bloc.add(const ProviderSelected('kemenag'));
      await bloc.stream.firstWhere((s) => s.provider == 'kemenag' && s.notice != null);
      expect(be.provider, 'kemenag');
      expect(bloc.state.adapters['kemenag'], isFalse);
      await bloc.close();
    });

    test('health keeps per-provider latency and failure', () async {
      await signIn('admin', 'SuperSecret1');
      be.kemenagReachable = false;
      final bloc = AdminConfigBloc(auth.api);
      bloc.add(const HealthCheckRequested());
      await bloc.stream.firstWhere((s) => s.health.isNotEmpty && !s.checking);
      expect(bloc.state.health['quran.com']!['latency_ms'], 120);
      expect(bloc.state.health['kemenag']!['ok'], false);
      await bloc.close();
    });

    test('a viewer without config.manage gets a 403 message, not a crash', () async {
      await signIn('auditor1', 'AuditorPass1');
      final bloc = AdminConfigBloc(auth.api);
      bloc.add(const ConfigLoaded());
      await bloc.stream.firstWhere((s) => s.error != null);
      expect(bloc.state.error, contains('config.manage'));
      await bloc.close();
    });
  });

  group('feedback', () {
    test('moving a card updates the server and recomputes counts', () async {
      await signIn('editor1', 'EditorPass1');
      final bloc = AdminFeedbackBloc(auth.api);
      bloc.add(const FeedbackLoaded());
      await bloc.stream.firstWhere((s) => s.items.length == 3);
      expect(bloc.state.counts['open'], 1);
      bloc.add(const FeedbackStatusChanged(1, 'resolved'));
      await bloc.stream.firstWhere((s) => s.counts['resolved'] == 2);
      expect(bloc.state.byStatus('open'), isEmpty);
      expect(be.feedbacks.first['status'], 'resolved');
      await bloc.close();
    });

    test('notes are saved without changing the status', () async {
      await signIn('editor1', 'EditorPass1');
      final bloc = AdminFeedbackBloc(auth.api);
      bloc.add(const FeedbackLoaded());
      await bloc.stream.firstWhere((s) => s.items.isNotEmpty);
      bloc.add(const FeedbackNotesSaved(2, 'Dikerjakan sprint depan'));
      await bloc.stream.firstWhere((s) => s.items.any((i) => i.adminNotes.isNotEmpty));
      expect(be.feedbacks[1]['status'], 'in_progress');
      await bloc.close();
    });
  });

  group('management', () {
    test('create adds the admin and refreshes the list; duplicates show the server error', () async {
      await signIn('admin', 'SuperSecret1');
      final bloc = AdminManagementBloc(auth.api);
      bloc.add(const ManagementLoaded());
      await bloc.stream.firstWhere((s) => s.admins.length == 3 && s.permissions.isNotEmpty && !s.loading);
      bloc.add(const AdminCreateRequested(username: 'newbie', email: 'n@x.co', fullName: 'New', password: 'Passw0rd!x', role: 'custom', permissions: ['chats.view']));
      await bloc.stream.firstWhere((s) => s.admins.length == 4 && s.notice != null);
      bloc.add(const AdminCreateRequested(username: 'newbie', email: 'n@x.co', fullName: 'New', password: 'Passw0rd!x', role: 'custom'));
      await bloc.stream.firstWhere((s) => s.error != null);
      expect(bloc.state.error, contains('already exists'));
      await bloc.close();
    });

    test('delete the protected primary admin is refused by the server and surfaced', () async {
      await signIn('admin', 'SuperSecret1');
      final bloc = AdminManagementBloc(auth.api);
      bloc.add(const ManagementLoaded());
      await bloc.stream.firstWhere((s) => s.admins.isNotEmpty && !s.loading);
      bloc.add(const AdminDeleteRequested(1));
      await bloc.stream.firstWhere((s) => s.error != null);
      expect(bloc.state.error, contains('primary'));
      expect(bloc.state.admins.length, 3);
      await bloc.close();
    });

    test('password reset sends the current password only when provided', () async {
      await signIn('admin', 'SuperSecret1');
      final bloc = AdminManagementBloc(auth.api);
      bloc.add(const AdminPasswordResetRequested(2, 'Another#12345'));
      await bloc.stream.firstWhere((s) => s.notice != null);
      expect(be.lastBody, isNot(contains('current_password')).or(isNull));
      expect(be.passwords['editor1'], 'Another#12345');
      bloc.add(const AdminPasswordResetRequested(1, 'Whatever#1234', currentPassword: 'wrong'));
      await bloc.stream.firstWhere((s) => s.error != null);
      expect(bloc.state.error, contains('incorrect'));
      await bloc.close();
    });
  });
}

extension on Matcher {
  Matcher or(Matcher other) => anyOf(this, other);
}
