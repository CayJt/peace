import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app/database/quran_database.dart';
import 'package:quran_app/models/quran_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fixtures/api_fixtures.dart';

void main() {
  sqfliteFfiInit();
  late QuranDatabase db;

  setUp(() async {
    db = await QuranDatabase.open(path: inMemoryDatabasePath, factory: databaseFactoryFfi);
  });
  tearDown(() => db.close());

  test('verses round-trip exactly through SQLite', () async {
    final v = QuranVerse.fromApi(fatihah1);
    await db.saveVerses([v]);
    final back = (await db.getVersesByPage(1)).single;
    expect(back.textUthmani, v.textUthmani);
    expect(back.words.map((w) => w.textUthmani), v.words.map((w) => w.textUthmani));
    expect(back.words.map((w) => w.letters.map((l) => l.char).join()),
        v.words.map((w) => w.textUthmani));
    expect(back.translationText, v.translationText);
  });

  test('page bounds are enforced', () async {
    expect(() => db.getVersesByPage(0), throwsRangeError);
    expect(() => db.getVersesByPage(605), throwsRangeError);
    expect(await db.getVersesByPage(10), isEmpty);
  });

  test('letter scores accumulate and summarise', () async {
    await db.recordLetterScore('ب', 1.0);
    await db.recordLetterScore('ب', 0.5);
    await db.recordLetterScore('س', 0.9);
    await db.recordReadingSession(1, 40, 3, 0.8);
    await db.recordReadingSession(2, 30, 2, 0.7);
    final s = await db.getOverallScoreSummary();
    expect(s['letters_evaluated'], 3);
    expect(s['average_score'], closeTo((1.0 + 0.5 + 0.9) / 3, 1e-9));
    expect(s['sessions_count'], 2);
    expect(s['total_seconds'], 70);
    expect(s['pages_read'], 2);
  });

  test('letter assessment updates the positional letter', () async {
    await db.saveVerses([QuranVerse.fromApi(fatihah1)]);
    await db.recordLetterAssessment('1:1', 1, 0, 0.9);
    final l = (await db.getVersesByPage(1)).single.words.first.letters.first;
    expect([l.latestScore, l.readCount], [0.9, 1]);
    // re-saving the verse must not wipe user scores
    await db.saveVerses([QuranVerse.fromApi(fatihah1)]);
    final l2 = (await db.getVersesByPage(1)).single.words.first.letters.first;
    expect(l2.latestScore, 0.9);
  });

  test('secondsPerDay buckets sessions by day', () async {
    await db.recordReadingSession(1, 60, 1, 1);
    final days = await db.secondsPerDay();
    expect(days.length, 7);
    expect(days.last, 60);
  });
}
