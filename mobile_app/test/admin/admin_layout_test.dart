import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'admin_test_helpers.dart';
import 'fake_backend.dart';

void main() {
  late FakeAdminBackend be;
  setUp(() => be = FakeAdminBackend());

  group('responsive shell', () {
    testWidgets('desktop (>=1024): fixed sidebar + breadcrumb, no app bar or rail', (tester) async {
      await pumpAdmin(tester, be, size: desktop);
      expect(find.byKey(const ValueKey('admin-sidebar')), findsOneWidget);
      expect(find.byKey(const ValueKey('admin-rail')), findsNothing);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byKey(const ValueKey('breadcrumb')), findsOneWidget);
      expect(find.text('Ringkasan'), findsWidgets);
    });

    testWidgets('tablet (600-1023): navigation rail instead of sidebar', (tester) async {
      await pumpAdmin(tester, be, size: tablet);
      expect(find.byKey(const ValueKey('admin-rail')), findsOneWidget);
      expect(find.byKey(const ValueKey('admin-sidebar')), findsNothing);
    });

    testWidgets('mobile (<600): sidebar is hidden; app bar + drawer navigation', (tester) async {
      await pumpAdmin(tester, be, size: mobile);
      expect(find.byKey(const ValueKey('admin-sidebar')), findsNothing);
      expect(find.byKey(const ValueKey('admin-rail')), findsNothing);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byTooltip('Open navigation menu'), findsOneWidget);

      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('admin-drawer')), findsOneWidget);
      expect(nav('rbac'), findsOneWidget);

      await tester.tap(nav('feedback'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await until(tester, find.byKey(const ValueKey('col-open')));
      expect(find.byKey(const ValueKey('admin-drawer')), findsNothing, reason: 'drawer closes after choosing');
    });

    testWidgets('resizing from desktop to phone swaps the layout live', (tester) async {
      await pumpAdmin(tester, be, size: desktop);
      expect(find.byKey(const ValueKey('admin-sidebar')), findsOneWidget);
      setSize(tester, 390, 844);
      await frames(tester);
      expect(find.byKey(const ValueKey('admin-sidebar')), findsNothing);
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('no overflow errors at any breakpoint on the busiest screens', (tester) async {
      for (final size in [desktop, tablet, mobile, const Size(320, 640)]) {
        await pumpAdmin(tester, be, size: size);
        for (final id in ['dashboard', 'leaderboard', 'provider', 'chats', 'feedback', 'rbac']) {
          if (size.width < 600) {
            await tester.tap(find.byTooltip('Open navigation menu'));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 400));
          }
          final label = const {'dashboard': 'Ringkasan', 'leaderboard': 'Leaderboard', 'provider': "Provider Qur'an", 'chats': 'Audit Chat AI', 'feedback': 'Kotak Saran', 'rbac': 'Administrator'}[id]!;
          final target = size.width >= 1024 || size.width < 600
              ? nav(id)
              : find.descendant(of: find.byKey(const ValueKey('admin-rail')), matching: find.text(label));
          await tester.tap(target);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          await frames(tester, 8);
          expect(tester.takeException(), isNull, reason: '$id at ${size.width}px');
        }
      }
    });
  });

  group('permission-aware navigation', () {
    testWidgets('super admin sees every section', (tester) async {
      await pumpAdmin(tester, be);
      for (final id in ['dashboard', 'leaderboard', 'provider', 'chats', 'feedback', 'rbac']) {
        expect(nav(id), findsOneWidget, reason: id);
      }
    });

    testWidgets('auditor sees only what the permissions allow', (tester) async {
      await pumpAdmin(tester, be, token: 'tok-3');
      expect(nav('dashboard'), findsOneWidget);
      expect(nav('leaderboard'), findsOneWidget);
      expect(nav('chats'), findsOneWidget);
      expect(nav('provider'), findsNothing);
      expect(nav('feedback'), findsNothing);
      expect(nav('rbac'), findsNothing);
    });

    testWidgets('editor sees dashboard and feedback only', (tester) async {
      await pumpAdmin(tester, be, token: 'tok-2');
      expect(nav('feedback'), findsOneWidget);
      expect(nav('rbac'), findsNothing);
      expect(nav('chats'), findsNothing);
      expect(nav('leaderboard'), findsNothing);
    });

    testWidgets('breadcrumb follows navigation', (tester) async {
      await pumpAdmin(tester, be);
      await openNav(tester, 'chats');
      expect(tester.widget<Text>(find.byKey(const ValueKey('breadcrumb'))).data, 'Audit Chat AI');
    });
  });

  group('session', () {
    testWidgets('unauthenticated -> login form; wrong password shows an error; success enters the shell', (tester) async {
      final store = await pumpAdmin(tester, be, token: null);
      expect(find.byKey(const ValueKey('admin-login-submit')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('admin-login-submit')));
      await tester.pump();
      expect(find.text('Wajib diisi'), findsNWidgets(2));

      await tester.enterText(find.byKey(const ValueKey('admin-username')), 'admin');
      await tester.enterText(find.byKey(const ValueKey('admin-password')), 'wrong');
      await tester.tap(find.byKey(const ValueKey('admin-login-submit')));
      await until(tester, find.byKey(const ValueKey('admin-login-error')));
      expect(find.text('Username atau kata sandi salah'), findsOneWidget);
      expect(store.token, isNull);

      await tester.enterText(find.byKey(const ValueKey('admin-password')), 'SuperSecret1');
      await tester.tap(find.byKey(const ValueKey('admin-login-submit')));
      await until(tester, find.byKey(const ValueKey('admin-sidebar')));
      expect(store.token, 'tok-1');
    });

    testWidgets('logout returns to login and wipes the stored token', (tester) async {
      final store = await pumpAdmin(tester, be);
      await tester.tap(find.byKey(const ValueKey('admin-logout')));
      await until(tester, find.byKey(const ValueKey('admin-login-submit')));
      expect(store.token, isNull);
    });

    testWidgets('an expired token mid-session sends the user back to login with a message', (tester) async {
      await pumpAdmin(tester, be);
      be.unauthorizedAfter = be.calls.length;
      await openNav(tester, 'feedback');
      await until(tester, find.byKey(const ValueKey('admin-login-submit')));
      expect(find.text('Sesi berakhir, silakan masuk kembali'), findsOneWidget);
    });

    testWidgets('invalid stored token is discarded and the login form appears', (tester) async {
      final store = await pumpAdmin(tester, be, token: 'bad-token');
      expect(find.byKey(const ValueKey('admin-login-submit')), findsOneWidget);
      expect(store.token, isNull);
    });
  });

  testWidgets('theme surface menu switches between the three modes', (tester) async {
    await pumpAdmin(tester, be);
    Color bg() => Theme.of(tester.element(find.byKey(const ValueKey('breadcrumb')))).scaffoldBackgroundColor;
    expect(bg(), const Color(0xFFFAF8F5));
    for (final (label, color) in [('OLED Charcoal', const Color(0xFF121212)), ('Pure White', const Color(0xFFFFFFFF)), ('Warm Paper', const Color(0xFFFAF8F5))]) {
      await tester.tap(find.byKey(const ValueKey('surface-menu')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text(label).last);
      await frames(tester, 4);
      expect(bg(), color, reason: label);
    }
  });
}
