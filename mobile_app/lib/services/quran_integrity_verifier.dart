import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/quran_models.dart';

enum MismatchKind { text, imlaei, wordCount, wordPosition, wordText, letters, translation, verseKey, page }

class Mismatch {
  final MismatchKind kind;
  final String detail;
  const Mismatch(this.kind, this.detail);
  @override
  String toString() => '${kind.name}: $detail';
}

class IntegrityResult {
  final String verseKey;
  final List<Mismatch> mismatches;
  const IntegrityResult(this.verseKey, this.mismatches);
  bool get ok => mismatches.isEmpty;

  /// Detailed multi-line log suitable for export.
  String report() => ok
      ? '[OK] $verseKey'
      : '[MISMATCH] $verseKey\n${mismatches.map((m) => '  - $m').join('\n')}';
}

class QuranIntegrityVerifier {
  const QuranIntegrityVerifier({this.translationId = 33});
  final int translationId;

  static String _cp(int r) => 'U+${r.toRadixString(16).toUpperCase().padLeft(4, '0')}';

  /// Describes the first difference between two strings at code-point level,
  /// so lost diacritics are visible (e.g. a missing U+064E FATHA).
  static String charDiff(String expected, String actual) {
    final e = expected.runes.toList(), a = actual.runes.toList();
    final n = e.length < a.length ? e.length : a.length;
    for (var i = 0; i < n; i++) {
      if (e[i] != a[i]) {
        return 'first difference at code point $i: expected ${_cp(e[i])} but got ${_cp(a[i])} '
            '(lengths ${e.length} vs ${a.length})';
      }
    }
    if (e.length > a.length) {
      return 'truncated: missing ${e.length - a.length} code point(s) from index $n, starting with ${_cp(e[n])}';
    }
    return 'extra ${a.length - e.length} code point(s) from index $n, starting with ${_cp(a[n])}';
  }

  static bool _eq(String a, String b) {
    final x = a.runes.toList(), y = b.runes.toList();
    if (x.length != y.length) return false;
    for (var i = 0; i < x.length; i++) {
      if (x[i] != y[i]) return false;
    }
    return true;
  }

  /// Compares [localVerse] (as stored/rendered) with the raw Quran.com v4
  /// `verses[]` element. Comparison is exact: no normalisation of any kind.
  IntegrityResult verifyVerseIntegrity(QuranVerse localVerse, Map<String, dynamic> rawApiResponse) {
    final m = <Mismatch>[];
    final raw = rawApiResponse;
    final key = raw['verse_key'] as String;

    if (localVerse.verseKey != key) {
      m.add(Mismatch(MismatchKind.verseKey, 'expected $key but got ${localVerse.verseKey}'));
    }
    final parts = key.split(':');
    if (localVerse.surahNumber != int.parse(parts[0]) || localVerse.verseNumber != int.parse(parts[1])) {
      m.add(Mismatch(MismatchKind.verseKey,
          'surah/verse ${localVerse.surahNumber}:${localVerse.verseNumber} do not match key $key'));
    }
    final page = raw['page_number'] as int;
    if (localVerse.page != page) {
      m.add(Mismatch(MismatchKind.page, 'expected page $page but got ${localVerse.page}'));
    }
    if (localVerse.page < 1 || localVerse.page > 604) {
      m.add(Mismatch(MismatchKind.page, 'page ${localVerse.page} outside 1..604'));
    }

    final uth = raw['text_uthmani'] as String;
    if (!_eq(uth, localVerse.textUthmani)) {
      m.add(Mismatch(MismatchKind.text, charDiff(uth, localVerse.textUthmani)));
    }
    final imlaei = raw['text_imlaei'] as String? ?? '';
    if (!_eq(imlaei, localVerse.textImlaei)) {
      m.add(Mismatch(MismatchKind.imlaei, charDiff(imlaei, localVerse.textImlaei)));
    }

    final apiWords = (raw['words'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .where((w) => w['char_type_name'] != 'end')
        .toList();
    if (apiWords.length != localVerse.words.length) {
      m.add(Mismatch(MismatchKind.wordCount,
          'expected ${apiWords.length} words but got ${localVerse.words.length}'));
    }
    for (var i = 0; i < apiWords.length && i < localVerse.words.length; i++) {
      final aw = apiWords[i], lw = localVerse.words[i];
      if (lw.wordPosition != aw['position']) {
        m.add(Mismatch(MismatchKind.wordPosition,
            'index $i: expected position ${aw['position']} but got ${lw.wordPosition}'));
      }
      final wt = aw['text_uthmani'] as String;
      if (!_eq(wt, lw.textUthmani)) {
        m.add(Mismatch(MismatchKind.wordText, 'word ${aw['position']}: ${charDiff(wt, lw.textUthmani)}'));
      }
      final joined = lw.letters.map((l) => l.char).join();
      final expectedLetters = Letter.decompose(wt);
      if (!_eq(wt, joined)) {
        m.add(Mismatch(MismatchKind.letters,
            'word ${aw['position']}: letters rejoin to a different string: ${charDiff(wt, joined)}'));
      } else if (lw.letters.length != expectedLetters.length) {
        m.add(Mismatch(MismatchKind.letters,
            'word ${aw['position']}: expected ${expectedLetters.length} letters but got ${lw.letters.length}'));
      } else {
        for (var j = 0; j < lw.letters.length; j++) {
          if (lw.letters[j].letterIndex != j) {
            m.add(Mismatch(MismatchKind.letters,
                'word ${aw['position']}: letter at slot $j has index ${lw.letters[j].letterIndex}'));
          }
        }
      }
    }

    final tr = (raw['translations'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .where((t) => t['resource_id'] == translationId);
    if (tr.isEmpty) {
      m.add(Mismatch(MismatchKind.translation, 'API response has no translation $translationId'));
    } else {
      final t = tr.first['text'] as String;
      if (!_eq(t, localVerse.translationText)) {
        m.add(Mismatch(MismatchKind.translation, charDiff(t, localVerse.translationText)));
      }
      if (localVerse.translationText.endsWith('…') || localVerse.translationText.endsWith('...')) {
        m.add(const Mismatch(MismatchKind.translation, 'translation ends with an ellipsis (truncated)'));
      }
    }
    if (localVerse.translationId != translationId) {
      m.add(Mismatch(MismatchKind.translation,
          'translation id ${localVerse.translationId}, expected $translationId'));
    }
    return IntegrityResult(key, m);
  }

  /// SHA-256 over the canonical verse content (key, page, Uthmani, Imlaei,
  /// each word, translation). Used for the whole-database audit.
  static String verseHash({
    required String verseKey,
    required int page,
    required String textUthmani,
    required String textImlaei,
    required List<String> words,
    required String translation,
  }) {
    final canon = [verseKey, '$page', textUthmani, textImlaei, ...words, translation].join('\u0000');
    return sha256.convert(utf8.encode(canon)).toString();
  }

  static String hashLocal(QuranVerse v) => verseHash(
        verseKey: v.verseKey,
        page: v.page,
        textUthmani: v.textUthmani,
        textImlaei: v.textImlaei,
        words: v.words.map((w) => w.textUthmani).toList(),
        translation: v.translationText,
      );

  String hashRaw(Map<String, dynamic> raw) {
    final tr = (raw['translations'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .where((t) => t['resource_id'] == translationId);
    return verseHash(
      verseKey: raw['verse_key'] as String,
      page: raw['page_number'] as int,
      textUthmani: raw['text_uthmani'] as String,
      textImlaei: raw['text_imlaei'] as String? ?? '',
      words: (raw['words'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .where((w) => w['char_type_name'] != 'end')
          .map((w) => w['text_uthmani'] as String)
          .toList(),
      translation: tr.isEmpty ? '' : tr.first['text'] as String,
    );
  }
}

class AuditReport {
  final int expected;
  final int verified;
  final List<String> problems;
  const AuditReport(this.expected, this.verified, this.problems);
  bool get allAuthentic => problems.isEmpty && verified == expected;
  String get summary => allAuthentic
      ? 'Semua $verified ayat terverifikasi otentik'
      : '$verified/$expected ayat terverifikasi; ${problems.length} masalah';
}
