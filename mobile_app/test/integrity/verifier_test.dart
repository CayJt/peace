import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app/models/quran_models.dart';
import 'package:quran_app/services/quran_integrity_verifier.dart';

import '../fixtures/api_fixtures.dart';

QuranVerse local() => QuranVerse.fromApi(fatihah1);
const v = QuranIntegrityVerifier();

void main() {
  test('identical data verifies', () {
    final r = v.verifyVerseIntegrity(local(), fatihah1);
    expect(r.ok, isTrue, reason: r.report());
  });

  test('a dropped fatha is reported with its code point', () {
    final bad = local();
    final broken = QuranVerse(
      verseKey: bad.verseKey, surahNumber: 1, verseNumber: 1, juz: 1, page: 1,
      textUthmani: bad.textUthmani.replaceFirst('ِ', ''), // kasra
      textImlaei: bad.textImlaei, translationText: bad.translationText, words: bad.words,
    );
    final r = v.verifyVerseIntegrity(broken, fatihah1);
    expect(r.ok, isFalse);
    expect(r.mismatches.first.kind, MismatchKind.text);
    expect(r.report(), contains('U+0650'));
  });

  test('truncated translation, wrong page, missing word are all caught', () {
    final b = local();
    final bad = QuranVerse(
      verseKey: b.verseKey, surahNumber: 1, verseNumber: 1, juz: 1, page: 2,
      textUthmani: b.textUthmani, textImlaei: b.textImlaei,
      translationText: b.translationText.substring(0, 10),
      words: b.words.take(3).toList(),
    );
    final kinds = v.verifyVerseIntegrity(bad, fatihah1).mismatches.map((m) => m.kind).toSet();
    expect(kinds, containsAll([MismatchKind.page, MismatchKind.translation, MismatchKind.wordCount]));
  });

  test('hash is stable for equal content and changes on any difference', () {
    expect(QuranIntegrityVerifier.hashLocal(local()), v.hashRaw(fatihah1));
    final other = {...fatihah1, 'text_uthmani': '${fatihah1['text_uthmani']}ّ'};
    expect(v.hashRaw(other), isNot(v.hashRaw(fatihah1)));
  });
}
