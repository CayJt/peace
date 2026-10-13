import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quran_app/screens/auth/login_screen.dart';
import 'package:quran_app/screens/auth/register_screen.dart';
import 'package:quran_app/services/auth_service.dart';
import 'package:quran_app/theme/app_theme.dart';

import 'helpers.dart';

http.Response json(Object body, [int code = 200]) =>
    http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json'});

void main() {
  setUpAll(() {
    AppTheme.useGoogleFonts = false;
    registerFallbackValue(const AuthenticationOptions());
  });

  late FakeSecureStorage store;
  late MockLocalAuth bio;
  late List<http.Request> calls;

  AuthService svc({int status = 200, Object? body}) {
    calls = [];
    return AuthService(
      baseUrl: 'http://x',
      storage: store,
      localAuth: bio,
      client: MockClient((req) async {
        calls.add(req);
        return json(body ?? {'token': 'tok', 'user': {'email': 'a@b.co', 'full_name': 'Ali'}}, status);
      }),
    );
  }

  setUp(() {
    store = FakeSecureStorage();
    bio = MockLocalAuth();
    when(() => bio.canCheckBiometrics).thenAnswer((_) async => true);
    when(() => bio.isDeviceSupported()).thenAnswer((_) async => true);
  });

  group('validators', () {
    test('email', () {
      expect(AuthValidators.email('a@b.co'), isNull);
      expect(AuthValidators.email('nope'), isNotNull);
      expect(AuthValidators.email(''), isNotNull);
    });
    test('password length and confirmation', () {
      expect(AuthValidators.password('1234567'), isNotNull);
      expect(AuthValidators.password('12345678'), isNull);
      expect(AuthValidators.confirm('a', 'b'), isNotNull);
      expect(AuthValidators.confirm('a', 'a'), isNull);
    });
    test('full name', () {
      expect(AuthValidators.fullName('  '), isNotNull);
      expect(AuthValidators.fullName('Ali'), isNull);
    });
  });

  group('AuthService', () {
    test('login stores token + user in secure storage and sends credentials', () async {
      final u = await svc().login(' a@b.co ', 'pw12345678');
      expect(u.fullName, 'Ali');
      expect(store.data['auth_token'], 'tok');
      expect(jsonDecode(calls.single.body), {'username': 'a@b.co', 'password': 'pw12345678'});
      expect((await svc().currentUser())?.email, 'a@b.co');
    });

    test('failed login surfaces the server message and stores nothing', () async {
      final s = svc(status: 401, body: {'detail': 'invalid credentials'});
      await expectLater(s.login('a', 'b'), throwsA(isA<AuthException>().having((e) => e.message, 'm', 'invalid credentials')));
      expect(store.data, isEmpty);
    });

    test('register posts email, full_name and password', () async {
      await svc(status: 201).register(email: 'a@b.co', fullName: 'Ali', password: 'pw12345678');
      expect(jsonDecode(calls.single.body), {'email': 'a@b.co', 'full_name': 'Ali', 'password': 'pw12345678'});
    });

    test('biometric login restores the stored session only after a successful prompt', () async {
      final s = svc();
      await s.login('a@b.co', 'pw12345678');
      when(() => bio.authenticate(localizedReason: any(named: 'localizedReason'), options: any(named: 'options')))
          .thenAnswer((_) async => true);
      await s.setBiometricEnabled(true);
      expect((await s.loginWithBiometrics()).email, 'a@b.co');
    });

    test('biometric failure or being disabled blocks login', () async {
      final s = svc();
      await s.login('a@b.co', 'pw12345678');
      await expectLater(s.loginWithBiometrics(), throwsA(isA<AuthException>())); // not enabled
      when(() => bio.authenticate(localizedReason: any(named: 'localizedReason'), options: any(named: 'options')))
          .thenAnswer((_) async => false);
      await expectLater(s.setBiometricEnabled(true), throwsA(isA<AuthException>()));
      expect(await s.biometricEnabled, isFalse);
    });

    test('logout revokes server-side and wipes local secrets, even when offline', () async {
      final s = svc();
      await s.login('a@b.co', 'pw12345678');
      await s.logout();
      expect(calls.last.url.path, '/api/v1/auth/logout');
      expect(calls.last.headers['Authorization'], 'Bearer tok');
      expect(store.data, isEmpty);

      final offline = AuthService(baseUrl: 'http://x', storage: store, localAuth: bio,
          client: MockClient((_) async => throw http.ClientException('down')));
      store.data['auth_token'] = 'tok';
      await offline.logout();
      expect(store.data, isEmpty);
    });
  });

  group('screens', () {
    Widget app(Widget home) => MaterialApp(theme: AppTheme.light(), home: home);

    testWidgets('login validates, then submits and reports success', (tester) async {
      AuthUser? got;
      await tester.pumpWidget(app(LoginScreen(auth: svc(), onAuthenticated: (u) => got = u)));
      await tester.tap(find.byKey(const ValueKey('login-submit')));
      await tester.pump();
      expect(find.text('Wajib diisi'), findsNWidgets(2));
      await tester.enterText(find.byKey(const ValueKey('login-user')), 'a@b.co');
      await tester.enterText(find.byKey(const ValueKey('login-pass')), 'pw12345678');
      await tester.tap(find.byKey(const ValueKey('login-submit')));
      await tester.pumpAndSettle();
      expect(got?.fullName, 'Ali');
    });

    testWidgets('login shows server error', (tester) async {
      await tester.pumpWidget(app(LoginScreen(
          auth: svc(status: 401, body: {'detail': 'invalid credentials'}), onAuthenticated: (_) {})));
      await tester.enterText(find.byKey(const ValueKey('login-user')), 'a@b.co');
      await tester.enterText(find.byKey(const ValueKey('login-pass')), 'x');
      await tester.tap(find.byKey(const ValueKey('login-submit')));
      await tester.pumpAndSettle();
      expect(find.text('invalid credentials'), findsOneWidget);
    });

    testWidgets('biometric button appears only when enabled and available', (tester) async {
      final s = svc();
      await tester.pumpWidget(app(LoginScreen(auth: s, onAuthenticated: (_) {})));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('login-biometric')), findsNothing);

      store.data['biometric_enabled'] = 'true';
      await tester.pumpWidget(app(LoginScreen(key: UniqueKey(), auth: s, onAuthenticated: (_) {})));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('login-biometric')), findsOneWidget);
    });

    testWidgets('login links to registration', (tester) async {
      await tester.pumpWidget(app(LoginScreen(auth: svc(), onAuthenticated: (_) {})));
      await tester.tap(find.byKey(const ValueKey('to-register')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reg-submit')), findsOneWidget);
    });

    testWidgets('register gives instant validation feedback', (tester) async {
      await tester.pumpWidget(app(RegisterScreen(auth: svc(), onAuthenticated: (_) {})));
      await tester.enterText(find.byKey(const ValueKey('reg-email')), 'bad');
      await tester.pump();
      expect(find.text('Email tidak valid'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('reg-pass')), 'short');
      await tester.pump();
      expect(find.text('Minimal 8 karakter'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('reg-pass')), 'pw12345678');
      await tester.enterText(find.byKey(const ValueKey('reg-confirm')), 'different');
      await tester.pump();
      expect(find.text('Kata sandi tidak sama'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('reg-confirm')), 'pw12345678');
      await tester.pump();
      expect(find.text('Kata sandi tidak sama'), findsNothing);
    });

    testWidgets('register submits when valid', (tester) async {
      AuthUser? got;
      await tester.pumpWidget(app(RegisterScreen(auth: svc(status: 201), onAuthenticated: (u) => got = u)));
      await tester.enterText(find.byKey(const ValueKey('reg-name')), 'Ali');
      await tester.enterText(find.byKey(const ValueKey('reg-email')), 'a@b.co');
      await tester.enterText(find.byKey(const ValueKey('reg-pass')), 'pw12345678');
      await tester.enterText(find.byKey(const ValueKey('reg-confirm')), 'pw12345678');
      await tester.tap(find.byKey(const ValueKey('reg-submit')));
      await tester.pumpAndSettle();
      expect(got?.email, 'a@b.co');
    });
  });
}
