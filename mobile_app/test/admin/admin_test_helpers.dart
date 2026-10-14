import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app/admin_app.dart';
import 'package:quran_app/theme/app_theme.dart';

import 'fake_backend.dart';

/// Sets the logical viewport (DPR 1) for the test.
void setSize(WidgetTester tester, double w, double h) {
  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

const desktop = Size(1280, 900);
const tablet = Size(800, 900);
const mobile = Size(390, 844);

/// Pumps frames until [finder] matches (the fake backend is microtask-only, so no real I/O is awaited).
/// `pumpAndSettle` can't be used: the pulse dot animates forever.
Future<void> until(WidgetTester tester, Finder finder, {int frames = 60}) async {
  for (var i = 0; i < frames && finder.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsWidgets, reason: 'timed out waiting for $finder');
}

Future<void> frames(WidgetTester tester, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Mounts the admin area. With [token] the stored session is restored (skips the login form).
Future<FakeSessionStore> pumpAdmin(WidgetTester tester, FakeAdminBackend be, {Size size = desktop, String? token = 'tok-1'}) async {
  AppTheme.useGoogleFonts = false;
  setSize(tester, size.width, size.height);
  final store = FakeSessionStore()..token = token;
  await tester.pumpWidget(MaterialApp(
    home: AdminRoot(api: be.api(), store: store, pollInterval: Duration.zero),
  ));
  await frames(tester);
  return store;
}

Finder nav(String id) => find.byKey(ValueKey('nav-$id'));

Future<void> openNav(WidgetTester tester, String id) async {
  await tester.tap(nav(id));
  await frames(tester, 8);
}

/// Scrolls [finder] into view (wide tables scroll horizontally) and taps it, like a user would.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}
