import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quran_app/app.dart';
import 'package:quran_app/bloc/reader_settings_cubit.dart';
import 'package:quran_app/bloc/reading_tracker_bloc.dart';
import 'package:quran_app/bloc/tajweed_assessment_bloc.dart';
import 'package:quran_app/database/quran_database.dart';
import 'package:quran_app/screens/history/history_dashboard_screen.dart';
import 'package:quran_app/screens/mushaf/mushaf_page_screen.dart';
import 'package:quran_app/screens/settings/settings_screen.dart';
import 'package:quran_app/services/auth_service.dart';
import 'package:quran_app/services/notification_service.dart';
import 'package:quran_app/services/quran_api_service.dart';
import 'package:quran_app/services/quran_chat_service.dart';
import 'package:quran_app/services/quran_sync_manager.dart';
import 'package:quran_app/theme/app_theme.dart';
import 'package:quran_app/widgets/uthmani_page_view.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'fixtures/api_fixtures.dart';
import 'helpers.dart';

void main() {
  sqfliteFfiInit();
  setUpAll(() => AppTheme.useGoogleFonts = false);

  late QuranDatabase db;
  late SharedPreferences prefs;
  late FakeMic mic;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = await QuranDatabase.open(path: inMemoryDatabasePath, factory: databaseFactoryFfi);
    mic = FakeMic();
  });
  tearDown(() => db.close());

  QuranSyncManager syncFor(Map<String, dynamic> pageJson) => QuranSyncManager(
        QuranApiService(
          client: MockClient((req) async => req.url.path.contains('chapter_recitations')
              ? http.Response('{}', 404)
              : http.Response(jsonEncode(pageJson), 200, headers: {'content-type': 'application/json; charset=utf-8'})),
        ),
        db,
      );

  Widget providers(Widget child) => MultiBlocProvider(providers: [
        BlocProvider(create: (_) => ReaderSettingsCubit(prefs)),
        BlocProvider(create: (_) => ReadingTrackerBloc(prefs)..add(const TrackerLoaded())),
        BlocProvider(create: (_) => TajweedAssessmentBloc(db: db, wsBase: 'ws://h', channelFactory: (_) => FakeChannel())),
      ], child: MaterialApp(theme: AppTheme.light(), home: child));

  /// Real async (sqflite isolate, http mock) needs real time between pumps.
  Future<void> settle(WidgetTester tester, Finder until) async {
    for (var i = 0; i < 100 && until.evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
  }

  MockLocalAuth noBiometrics() {
    final m = MockLocalAuth();
    when(() => m.canCheckBiometrics).thenAnswer((_) async => false);
    when(() => m.isDeviceSupported()).thenAnswer((_) async => false);
    return m;
  }

  Widget mushaf(QuranSyncManager s) => providers(MushafPageScreen(
        sync: s, db: db, mic: mic, onOpenHistory: () {}, onOpenChat: () {}, onOpenSettings: () {}));

  group('mushaf screen', () {
    testWidgets('loads page 1 from the API, caches to SQLite, shows header/footer', (tester) async {
      await tester.pumpWidget(mushaf(syncFor(pageOf([fatihah1]))));
      await settle(tester, find.byKey(const ValueKey('page-number')));
      expect(find.byKey(const ValueKey('page-number')), findsOneWidget);
      expect(find.text('سورة الفاتحة'), findsNWidgets(2)); // header + banner
      expect(find.byKey(const ValueKey('floating-pill')), findsOneWidget);
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      expect(await tester.runAsync(() => db.hasPage(1)), isTrue);
    });

    testWidgets('tap toggles the pill; toggles flip settings', (tester) async {
      await tester.pumpWidget(mushaf(syncFor(pageOf([fatihah1]))));
      await settle(tester, find.byType(UthmaniPageView));
      final pill = find.byType(AnimatedOpacity).first;
      expect(tester.widget<AnimatedOpacity>(pill).opacity, 1);

      await tester.tap(find.byKey(const ValueKey('pill-translation')));
      await tester.pump();
      expect(find.byKey(const ValueKey('translation-1:1')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pill-tajweed')));
      await tester.tap(find.byKey(const ValueKey('pill-tahfidz')));
      await tester.pump();
      expect(prefs.getBool('tajweed'), isFalse);

      await tester.tapAt(const Offset(200, 300)); // empty area -> hide
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.widget<AnimatedOpacity>(pill).opacity, 0);
      await tester.tapAt(const Offset(200, 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.widget<AnimatedOpacity>(pill).opacity, 1);
    });

    testWidgets('scrolling down hides the pill, scrolling up shows it', (tester) async {
      await tester.pumpWidget(mushaf(syncFor(pageOf([longVerse(key: '1:1', page: 1, surah: 1)]))));
      await settle(tester, find.byType(UthmaniPageView));
      final pill = find.byType(AnimatedOpacity).first;
      await tester.drag(find.byType(ListView).first, const Offset(0, -200)); // finger up = scroll down
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.widget<AnimatedOpacity>(pill).opacity, 0);
      await tester.drag(find.byType(ListView).first, const Offset(0, 120));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.widget<AnimatedOpacity>(pill).opacity, 1);
    });

    testWidgets('mic without permission shows a message and stays off', (tester) async {
      mic.permission = false;
      await tester.pumpWidget(mushaf(syncFor(pageOf([fatihah1]))));
      await settle(tester, find.byType(UthmaniPageView));
      await tester.tap(find.byKey(const ValueKey('pill-mic')));
      await tester.pump();
      await tester.pump();
      expect(find.text('Izin mikrofon diperlukan'), findsOneWidget);
      expect(prefs.getBool('mic'), isNull);
    });

    testWidgets('load failure offers retry', (tester) async {
      final s = QuranSyncManager(
          QuranApiService(client: MockClient((_) async => http.Response('x', 500))), db);
      await tester.pumpWidget(mushaf(s));
      await settle(tester, find.text('Gagal memuat halaman'));
      expect(find.text('Gagal memuat halaman'), findsOneWidget);
    });
  });

  group('settings', () {
    testWidgets('logout asks for confirmation; cancel keeps session, confirm logs out', (tester) async {
      final store = FakeSecureStorage()..data['auth_token'] = 't';
      var out = 0;
      final auth = AuthService(baseUrl: 'http://x', storage: store, localAuth: noBiometrics(),
          client: MockClient((_) async => http.Response('', 204)));
      await tester.pumpWidget(providers(SettingsScreen(
          auth: auth, user: const AuthUser('a@b.co', 'Ali'), onLoggedOut: () => out++)));
      await tester.pumpAndSettle();
      expect(find.text('Ali'), findsOneWidget);
      expect(find.byKey(const ValueKey('khatam-badge')), findsOneWidget);

      await tester.ensureVisible(find.byKey(const ValueKey('logout-button')));
      await tester.tap(find.byKey(const ValueKey('logout-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('logout-cancel')));
      await tester.pumpAndSettle();
      expect(out, 0);
      expect(store.data['auth_token'], 't');

      await tester.tap(find.byKey(const ValueKey('logout-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('logout-confirm')));
      await tester.pumpAndSettle();
      expect(out, 1);
      expect(store.data, isEmpty);
    });

    testWidgets('theme switch persists the choice', (tester) async {
      final auth = AuthService(baseUrl: 'http://x', storage: FakeSecureStorage(), localAuth: noBiometrics());
      await tester.pumpWidget(providers(SettingsScreen(
          auth: auth, user: const AuthUser('a@b.co', 'Ali'), onLoggedOut: () {})));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gelap'));
      await tester.pumpAndSettle();
      expect(prefs.getString('theme'), 'dark');
    });
  });

  group('history', () {
    testWidgets('shows summary cards, chart and recent sessions', (tester) async {
      await tester.runAsync(() async {
        await db.recordLetterScore('ب', 0.9);
        await db.recordLetterScore('س', 0.7);
        await db.recordReadingSession(3, 45, 2, 0.8);
      });
      await tester.pumpWidget(providers(HistoryDashboardScreen(db: db)));
      await settle(tester, find.byKey(const ValueKey('stat-avg')));
      expect(tester.widget<Text>(find.byKey(const ValueKey('stat-avg'))).data, '80%');
      expect(tester.widget<Text>(find.byKey(const ValueKey('stat-letters'))).data, '2');
      expect(tester.widget<Text>(find.byKey(const ValueKey('stat-khatam'))).data, '0');
      expect(find.text('Halaman 3'), findsOneWidget);
      expect(find.text('80%'), findsWidgets);
    });
  });

  group('notifications', () {
    test('message adapts to reading habit and always carries a reference', () {
      final lapsed = composeReminder(const ReadingHabit(daysSinceLastRead: 5, lastPage: 42));
      expect(lapsed.body, contains('5 hari'));
      expect(lapsed.body, contains('halaman 42'));
      final streak = composeReminder(const ReadingHabit(streakDays: 4, lastPage: 7));
      expect(streak.body, contains('4 hari berturut-turut'));
      expect(composeReminder(const ReadingHabit()).body, matches(RegExp(r'\d+:\d+')));
    });

    test('snippet rotates by day', () {
      final a = composeReminder(const ReadingHabit(), now: DateTime(2026, 1, 1)).body;
      final b = composeReminder(const ReadingHabit(), now: DateTime(2026, 1, 2)).body;
      expect(a, isNot(b));
    });

    test('next instance is today if still ahead, else tomorrow', () {
      tzdata.initializeTimeZones();
      final loc = tz.getLocation('Asia/Jakarta');
      final now = tz.TZDateTime(loc, 2026, 3, 10, 6, 0);
      expect(NotificationService.nextInstance(5, 0, now), tz.TZDateTime(loc, 2026, 3, 11, 5, 0));
      expect(NotificationService.nextInstance(18, 30, now), tz.TZDateTime(loc, 2026, 3, 10, 18, 30));
    });
  });

  testWidgets('app boots to the login screen when signed out', (tester) async {
    await tester.pumpWidget(QuranApp(
      deps: AppDeps(
        prefs: prefs,
        db: db,
        auth: AuthService(baseUrl: 'http://x', storage: FakeSecureStorage(), localAuth: noBiometrics()),
        sync: syncFor(pageOf([fatihah1])),
        chat: QuranChatService(baseUrl: 'http://x'),
        mic: mic,
        wsBase: 'ws://x',
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('login-submit')), findsOneWidget);
  });
}
