// Verifies that what is painted equals the API payload, character for
// character. Fixtures here are SYNTHETIC (see fixtures/api_fixtures.dart); the
// same assertions run against the live API in live_api_integrity_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app/models/quran_models.dart';
import 'package:quran_app/theme/app_theme.dart';
import 'package:quran_app/widgets/quran_verse_view.dart';
import 'package:quran_app/widgets/uthmani_page_view.dart';

import '../fixtures/api_fixtures.dart';

/// Text actually painted by the RichTexts matching [test], excluding widget
/// placeholders (the ayah marker contributes no characters).
String painted(WidgetTester tester, bool Function(RichText) test) => tester
    .widgetList<RichText>(find.byType(RichText))
    .where(test)
    .map((r) => r.text.toPlainText(includePlaceholders: false, includeSemanticsLabels: false))
    .join();

Widget host(Widget child, {double width = 360, double height = 640}) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: Center(child: SizedBox(width: width, height: height, child: child))),
    );

bool isVerse(RichText r) => (r.key as ValueKey?)?.value.toString().startsWith('verse-text-') ?? false;
bool isRun(RichText r) => (r.key as ValueKey?)?.value.toString().startsWith('page-run-') ?? false;

void expectNoRenderProblems(WidgetTester tester) {
  expect(tester.takeException(), isNull, reason: 'RenderFlex/overflow or other framework error');
  for (final p in tester.renderObjectList<RenderParagraph>(find.byType(RichText))) {
    expect(p.didExceedMaxLines, isFalse, reason: 'paragraph truncated');
    expect(p.overflow, isNot(TextOverflow.ellipsis));
  }
}

void main() {
  setUpAll(() => AppTheme.useGoogleFonts = false);
  tearDownAll(() => AppTheme.useGoogleFonts = true);

  final cases = {
    'Al-Fatihah 1:1 (short)': fatihah1,
    'Al-Ikhlas 112:1 (short)': ikhlas1,
    'long verse, wraps (stand-in for 2:255)': longVerse(),
    'At-Taubah 9:1': taubah1(),
  };

  for (final MapEntry(key: name, value: raw) in cases.entries) {
    for (final mode in ['tajweed', 'monochrome', 'tahfidz']) {
      testWidgets('$name renders exactly [$mode]', (tester) async {
        await tester.pumpWidget(host(SingleChildScrollView(
          child: QuranVerseView(
            verse: QuranVerse.fromApi(raw),
            tajweedColors: mode == 'tajweed',
            tahfidz: mode == 'tahfidz',
          ),
        )));
        expect(painted(tester, isVerse), raw['text_uthmani']);
        expectNoRenderProblems(tester);
        expect(find.byKey(ValueKey('marker-${raw['verse_key']}')), findsOneWidget);
      });
    }

    testWidgets('$name stays inside its container', (tester) async {
      await tester.pumpWidget(host(SingleChildScrollView(child: QuranVerseView(verse: QuranVerse.fromApi(raw)))));
      final box = tester.getRect(find.byType(SingleChildScrollView));
      final text = tester.getRect(find.byWidgetPredicate((w) => w is RichText && isVerse(w)));
      expect(text.left, greaterThanOrEqualTo(box.left - 0.5));
      expect(text.right, lessThanOrEqualTo(box.right + 0.5));
    });
  }

  testWidgets('translation is shown whole, never ellipsised', (tester) async {
    final raw = longVerse();
    await tester.pumpWidget(host(SingleChildScrollView(
      child: QuranVerseView(verse: QuranVerse.fromApi(raw), showTranslation: true),
    )));
    final t = tester.widget<Text>(find.byKey(const ValueKey('translation-2:255')));
    expect(t.data, (raw['translations'] as List).first['text']);
    expect(t.overflow, isNull);
    expect(t.maxLines, isNull);
    expectNoRenderProblems(tester);
  });

  group('page view', () {
    testWidgets('page text equals the concatenated verses; header/footer correct', (tester) async {
      final raws = [fatihah1, {...ikhlas1, 'page_number': 1}];
      final verses = raws.map(QuranVerse.fromApi).toList();
      await tester.pumpWidget(host(UthmaniPageView(page: 1, verses: verses)));
      final text = painted(tester, isRun);
      expect(text.replaceAll(' ', ''), raws.map((r) => (r['text_uthmani'] as String).replaceAll(' ', '')).join());
      for (final r in raws) {
        expect(text, contains(r['text_uthmani']));
      }
      expect(find.text('١'), findsWidgets); // page number + ayah marker
      expect(find.byKey(const ValueKey('page-number')), findsOneWidget);
      expectNoRenderProblems(tester);
    });

    testWidgets('At-Taubah has a banner but no basmalah; Al-Baqarah has both', (tester) async {
      await tester.pumpWidget(host(UthmaniPageView(page: 187, verses: [QuranVerse.fromApi(taubah1())])));
      expect(find.byKey(const ValueKey('banner-9')), findsOneWidget);
      expect(find.byKey(const ValueKey('basmalah-9')), findsNothing);

      final baqarah = longVerse(key: '2:1', page: 2);
      await tester.pumpWidget(host(UthmaniPageView(page: 2, verses: [QuranVerse.fromApi(baqarah)])));
      expect(find.byKey(const ValueKey('basmalah-2')), findsOneWidget);
    });

    testWidgets('Al-Fatihah shows no separate basmalah (it is verse 1)', (tester) async {
      await tester.pumpWidget(host(UthmaniPageView(page: 1, verses: [QuranVerse.fromApi(fatihah1)])));
      expect(find.byKey(const ValueKey('basmalah-1')), findsNothing);
    });

    testWidgets('narrow phone width does not overflow', (tester) async {
      await tester.pumpWidget(host(
          UthmaniPageView(page: 42, verses: [QuranVerse.fromApi(longVerse())], showTranslation: true),
          width: 320));
      expectNoRenderProblems(tester);
    });
  });
}
