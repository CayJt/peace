import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app/models/quran_models.dart';
import 'package:quran_app/services/quran_api_service.dart';

import 'fixtures/api_fixtures.dart';

void main() {
  group('Letter.decompose', () {
    test('marks attach to their base letter and rejoin exactly', () {
      for (final w in ['بِسْمِ', 'ٱلرَّحْمَٰنِ', 'أَحَدٌ', 'ٱللَّهِ']) {
        final ls = Letter.decompose(w);
        expect(ls.map((l) => l.char).join(), w);
      }
      expect(Letter.decompose('بِسْمِ').map((l) => l.phonemeCode), ['ب', 'س', 'م']);
      expect(Letter.decompose('ٱلرَّحْمَٰنِ').length, 6);
    });

    test('indexes are sequential and rules detected', () {
      final ls = Letter.decompose('قُلْ');
      expect([for (final l in ls) l.letterIndex], [0, 1]);
      expect(Letter.decompose('قْ').first.tajweedRule, TajweedRule.qalqalah);
      expect(Letter.decompose('نَّ').first.tajweedRule, TajweedRule.ghunnah);
      expect(Letter.decompose('هَ').first.makhrajCategory, MakhrajCategory.halq);
    });
  });

  group('QuranVerse.fromApi', () {
    test('maps verse, words (excluding end marker) and translation 33', () {
      final v = QuranVerse.fromApi(fatihah1);
      expect(v.verseKey, '1:1');
      expect([v.surahNumber, v.verseNumber, v.juz, v.page], [1, 1, 1, 1]);
      expect(v.words.length, 4);
      expect(v.words.map((w) => w.wordPosition), [1, 2, 3, 4]);
      expect(v.words.first.translation, 'Dengan nama');
      expect(v.translationText, startsWith('Dengan nama Allah'));
      expect(v.words.every((w) => w.letters.isNotEmpty), isTrue);
    });
  });

  group('QuranApiService', () {
    test('page uri carries required query parameters', () {
      final u = QuranApiService().pageUri(5);
      expect(u.path, endsWith('/verses/by_page/5'));
      expect(u.queryParameters['translations'], '33');
      expect(u.queryParameters['words'], 'true');
      expect(u.queryParameters['word_fields'], 'text_uthmani,text_imlaei,location');
      expect(u.queryParameters['per_page'], '50');
    });

    test('applyRecitation maps [word, from, to] segments to word times', () {
      final v = QuranVerse.fromApi(fatihah1);
      final rec = ChapterRecitation('a.mp3', {
        '1:1': [
          [1, 0, 500],
          [2, 500, 900],
        ]
      });
      final t = QuranApiService.applyRecitation(v, rec);
      expect(t.audio!.url, 'a.mp3');
      expect([t.words[0].startTimeMs, t.words[0].endTimeMs], [0, 500]);
      expect(t.words[2].startTimeMs, isNull);
    });
  });
}
