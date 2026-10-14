import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'admin_test_helpers.dart';
import 'fake_backend.dart';

String text(WidgetTester t, String key) => t.widget<Text>(find.byKey(ValueKey(key))).data!;

void main() {
  late FakeAdminBackend be;
  setUp(() => be = FakeAdminBackend());

  group('dashboard', () {
    testWidgets('shows realtime, user and pending-feedback metrics with a pulsing dot', (tester) async {
      await pumpAdmin(tester, be);
      await until(tester, find.byKey(const ValueKey('metric-active')));
      await frames(tester, 6);
      expect(text(tester, 'metric-active'), '7');
      expect(text(tester, 'metric-total'), '120');
      expect(text(tester, 'metric-pending'), '1');
      expect(find.text('Koneksi WS: 2'), findsOneWidget);
      expect(find.text('Tren registrasi'), findsOneWidget);
    });

    testWidgets('an editor only gets the cards their permissions allow', (tester) async {
      await pumpAdmin(tester, be, token: 'tok-2');
      await until(tester, find.byKey(const ValueKey('metric-active')));
      expect(find.byKey(const ValueKey('metric-total')), findsNothing);
      expect(find.text('Tren registrasi'), findsNothing);
      expect(be.calls.any((c) => c.contains('/users/stats')), isFalse, reason: 'must not even request forbidden data');
    });

    testWidgets('refresh button reloads', (tester) async {
      await pumpAdmin(tester, be);
      await frames(tester, 8);
      final before = be.calls.where((c) => c == 'GET /analytics/realtime').length;
      await tester.tap(find.byKey(const ValueKey('dashboard-refresh')));
      await frames(tester, 8);
      expect(be.calls.where((c) => c == 'GET /analytics/realtime').length, before + 1);
    });
  });

  group('leaderboard', () {
    testWidgets('ranks users and lists murajaah sessions; sort switch refetches', (tester) async {
      await pumpAdmin(tester, be);
      await openNav(tester, 'leaderboard');
      await until(tester, find.byKey(const ValueKey('lb-5')));
      expect(find.text('Aisyah'), findsWidgets);
      expect(find.text('93%'), findsOneWidget);
      expect(find.byKey(const ValueKey('ms-1')), findsOneWidget);
      await tester.tap(find.text('Khatam'));
      await frames(tester, 8);
      expect(be.calls.where((c) => c == 'GET /analytics/leaderboard').length, 2);
    });
  });

  group('provider switcher', () {
    testWidgets('shows latency per provider and the active one', (tester) async {
      await pumpAdmin(tester, be);
      await openNav(tester, 'provider');
      await until(tester, find.byKey(const ValueKey('latency-quran.com')));
      expect(find.text('120 ms'), findsOneWidget);
      expect(find.text('1500 ms'), findsOneWidget);
      expect(find.text('Aktif'), findsOneWidget);
    });

    testWidgets('unreachable provider is flagged', (tester) async {
      be.kemenagReachable = false;
      await pumpAdmin(tester, be);
      await openNav(tester, 'provider');
      await until(tester, find.text('Tidak terjangkau'));
    });

    testWidgets('picking Kemenag warns that no adapter exists, then persists on confirm', (tester) async {
      await pumpAdmin(tester, be);
      await openNav(tester, 'provider');
      await until(tester, find.byKey(const ValueKey('provider-kemenag')));
      await tester.tap(find.byKey(const ValueKey('provider-kemenag')));
      await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
      expect(find.text('Adapter belum tersedia'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('confirm-cancel')));
      await frames(tester);
      expect(be.provider, 'quran.com', reason: 'cancel changes nothing');

      await tester.tap(find.byKey(const ValueKey('provider-kemenag')));
      await frames(tester, 8);
      await tester.tap(find.byKey(const ValueKey('confirm-ok')));
      await frames(tester, 10);
      expect(be.provider, 'kemenag');
      expect(find.text('Provider diganti ke kemenag'), findsOneWidget);
    });

    testWidgets('selecting Quran.com needs no warning', (tester) async {
      be.provider = 'kemenag';
      await pumpAdmin(tester, be);
      await openNav(tester, 'provider');
      await until(tester, find.byKey(const ValueKey('provider-quran.com')));
      await tester.tap(find.byKey(const ValueKey('provider-quran.com')));
      await frames(tester, 10);
      expect(be.provider, 'quran.com');
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('cache clear asks first, then reports the count', (tester) async {
      await pumpAdmin(tester, be);
      await openNav(tester, 'provider');
      await tester.tap(find.byKey(const ValueKey('cache-clear')));
      await frames(tester, 8);
      await tester.tap(find.byKey(const ValueKey('confirm-ok')));
      await frames(tester, 8);
      expect(be.calls, contains('POST /config/cache/clear'));
      expect(find.text('Cache dibersihkan (4 entri)'), findsOneWidget);
    });
  });

  group('AI audit logs', () {
    testWidgets('lists chats, flags guardrail hits and opens the verse-reference audit modal', (tester) async {
      await pumpAdmin(tester, be);
      await openNav(tester, 'chats');
      await until(tester, find.byKey(const ValueKey('chat-1')));
      expect(find.text('Guardrail aktif (1)'), findsOneWidget);
      expect(find.byIcon(Icons.shield_outlined), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('chat-1')));
      await frames(tester, 8);
      expect(find.byKey(const ValueKey('chat-audit-dialog')), findsOneWidget);
      expect(find.text('Dijawab'), findsOneWidget);
      expect(find.text('1:1'), findsOneWidget);
      expect(find.text('Dengan nama Allah'), findsOneWidget);
    });

    testWidgets('guardrail filter and search go to the server', (tester) async {
      await pumpAdmin(tester, be);
      await openNav(tester, 'chats');
      await until(tester, find.byKey(const ValueKey('chat-2')));
      await tester.tap(find.byKey(const ValueKey('chat-guardrail-filter')));
      await frames(tester, 8);
      await tester.enterText(find.byKey(const ValueKey('chat-search')), 'bitcoin');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await frames(tester, 8);
      expect(be.calls.where((c) => c == 'GET /chats/history').length, 3);
    });
  });

  group('feedback kanban', () {
    testWidgets('columns hold the right cards with counts', (tester) async {
      await pumpAdmin(tester, be);
      await openNav(tester, 'feedback');
      await until(tester, find.byKey(const ValueKey('fb-1')));
      expect(find.descendant(of: find.byKey(const ValueKey('col-open')), matching: find.text('Tombol mic tidak berfungsi')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('col-in_progress')), matching: find.text('Tambah mode malam')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('col-resolved')), matching: find.byKey(const ValueKey('fb-3'))), findsOneWidget);
      expect(find.byKey(const ValueKey('col-discarded')), findsNothing);
      expect(text(tester, 'count-open'), '1');
    });

    testWidgets('moving a card via its menu updates the server and the board', (tester) async {
      await pumpAdmin(tester, be);
      await openNav(tester, 'feedback');
      await until(tester, find.byKey(const ValueKey('fb-1')));
      await tester.tap(find.byKey(const ValueKey('fb-menu-1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Pindahkan ke Resolved'));
      await frames(tester, 10);
      expect(be.feedbacks.first['status'], 'resolved');
      expect(find.descendant(of: find.byKey(const ValueKey('col-resolved')), matching: find.byKey(const ValueKey('fb-1'))), findsOneWidget);
      expect(text(tester, 'count-open'), '0');
      expect(text(tester, 'count-resolved'), '2');
    });

    testWidgets('admin notes can be saved and are displayed on the card', (tester) async {
      await pumpAdmin(tester, be);
      await openNav(tester, 'feedback');
      await until(tester, find.byKey(const ValueKey('fb-2')));
      await tester.tap(find.byKey(const ValueKey('fb-menu-2')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Catatan…'));
      await frames(tester, 8);
      await tester.enterText(find.byKey(const ValueKey('notes-field')), 'Masuk sprint 12');
      await tester.tap(find.byKey(const ValueKey('notes-save')));
      await frames(tester, 10);
      expect(be.feedbacks[1]['admin_notes'], 'Masuk sprint 12');
      expect(find.text('Masuk sprint 12'), findsOneWidget);
    });

    testWidgets('discarded column is hidden until requested', (tester) async {
      await pumpAdmin(tester, be);
      await openNav(tester, 'feedback');
      await until(tester, find.byKey(const ValueKey('fb-1')));
      await tester.tap(find.byKey(const ValueKey('show-discarded')));
      await frames(tester);
      expect(find.byKey(const ValueKey('col-discarded')), findsOneWidget);
    });

    testWidgets('works on a phone (horizontally scrolling board)', (tester) async {
      await pumpAdmin(tester, be, size: mobile);
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(nav('feedback'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await until(tester, find.byKey(const ValueKey('fb-1')));
      expect(tester.takeException(), isNull);
    });
  });

  group('administrators & RBAC matrix', () {
    testWidgets('desktop shows the matrix; checkboxes reflect permissions; implicit rows are locked', (tester) async {
      await pumpAdmin(tester, be);
      await openNav(tester, 'rbac');
      await until(tester, find.byKey(const ValueKey('rbac-matrix')));
      bool value(int id, String k) => tester.widget<Checkbox>(find.byKey(ValueKey('perm-$id-$k'))).value!;
      expect(value(2, 'feedback.manage'), isTrue);
      expect(value(2, 'chats.view'), isFalse);
      expect(value(1, 'config.manage'), isTrue);
      expect(tester.widget<Checkbox>(find.byKey(const ValueKey('perm-1-config.manage'))).onChanged, isNull, reason: 'primary/super admin is locked');
      expect(tester.widget<IconButton>(find.byKey(const ValueKey('delete-1'))).onPressed, isNull, reason: 'primary admin cannot be deleted');
      expect(tester.widget<Switch>(find.byKey(const ValueKey('active-1'))).onChanged, isNull);
    });

    testWidgets('toggling a checkbox sends the new permission set', (tester) async {
      await pumpAdmin(tester, be);
      await openNav(tester, 'rbac');
      await until(tester, find.byKey(const ValueKey('perm-2-chats.view')));
      await tapVisible(tester, find.byKey(const ValueKey('perm-2-chats.view')));
      await frames(tester, 10);
      expect(be.calls, contains('PUT /administrators/2'));
      expect(be.admins[1]['permissions'], containsAll(['chats.view', 'feedback.manage', 'analytics.view']));
      expect(find.text('Perubahan disimpan'), findsOneWidget);
    });

    testWidgets('Tambah Admin: fill the modal and the new admin appears', (tester) async {
      await pumpAdmin(tester, be);
      await openNav(tester, 'rbac');
      await until(tester, find.byKey(const ValueKey('perm-2-chats.view')));
      await tester.tap(find.byKey(const ValueKey('add-admin')));
      await frames(tester, 8);
      await tester.enterText(find.byKey(const ValueKey('add-username')), 'brandnew');
      await tester.enterText(find.byKey(const ValueKey('add-fullname')), 'Brand New');
      await tester.enterText(find.byKey(const ValueKey('add-email')), 'bn@x.co');
      await tester.enterText(find.byKey(const ValueKey('add-password')), 'Passw0rd!x');
      await tester.enterText(find.byKey(const ValueKey('add-confirm')), 'Passw0rd!x');
      await tester.tap(find.byKey(const ValueKey('add-perm-chats.view')));
      await tester.tap(find.byKey(const ValueKey('add-submit')));
      await frames(tester, 12);
      expect(be.admins.last['username'], 'brandnew');
      expect(be.admins.last['permissions'], ['chats.view']);
      expect(find.text('Administrator ditambahkan'), findsOneWidget);
      expect(find.text('Brand New'), findsOneWidget);
    });

    testWidgets('reset password dialog from the row posts the new password', (tester) async {
      await pumpAdmin(tester, be);
      await openNav(tester, 'rbac');
      await until(tester, find.byKey(const ValueKey('reset-2')));
      await tapVisible(tester, find.byKey(const ValueKey('reset-2')));
      await frames(tester, 8);
      await tester.enterText(find.byKey(const ValueKey('pw-new')), 'Another#12345');
      await tester.enterText(find.byKey(const ValueKey('pw-confirm')), 'Another#12345');
      await tester.tap(find.byKey(const ValueKey('pw-submit')));
      await frames(tester, 10);
      expect(be.passwords['editor1'], 'Another#12345');
      expect(find.text('Kata sandi diperbarui'), findsOneWidget);
    });

    testWidgets('deleting asks for confirmation first', (tester) async {
      await pumpAdmin(tester, be);
      await openNav(tester, 'rbac');
      await until(tester, find.byKey(const ValueKey('delete-2')));
      await tapVisible(tester, find.byKey(const ValueKey('delete-2')));
      await frames(tester, 8);
      await tester.tap(find.byKey(const ValueKey('confirm-cancel')));
      await frames(tester, 6);
      expect(be.admins.length, 3);
      await tapVisible(tester, find.byKey(const ValueKey('delete-2')));
      await frames(tester, 8);
      await tester.tap(find.byKey(const ValueKey('confirm-ok')));
      await frames(tester, 10);
      expect(be.admins.length, 2);
      expect(find.text('Administrator dihapus'), findsOneWidget);
    });

    testWidgets('mobile uses per-admin cards with permission chips instead of the matrix', (tester) async {
      await pumpAdmin(tester, be, size: mobile);
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(nav('rbac'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await until(tester, find.byKey(const ValueKey('card-2')));
      expect(find.byKey(const ValueKey('rbac-matrix')), findsNothing);
      expect(find.byKey(const ValueKey('perm-2-chats.view')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('server-side duplicate username error is shown to the user', (tester) async {
      await pumpAdmin(tester, be);
      await openNav(tester, 'rbac');
      await until(tester, find.byKey(const ValueKey('add-admin')));
      await tester.tap(find.byKey(const ValueKey('add-admin')));
      await frames(tester, 8);
      await tester.enterText(find.byKey(const ValueKey('add-username')), 'editor1');
      await tester.enterText(find.byKey(const ValueKey('add-fullname')), 'Dup');
      await tester.enterText(find.byKey(const ValueKey('add-email')), 'dup@x.co');
      await tester.enterText(find.byKey(const ValueKey('add-password')), 'Passw0rd!x');
      await tester.enterText(find.byKey(const ValueKey('add-confirm')), 'Passw0rd!x');
      await tester.tap(find.byKey(const ValueKey('add-submit')));
      await frames(tester, 12);
      expect(find.text('username or email already exists'), findsOneWidget);
    });
  });
}
