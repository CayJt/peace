import 'package:equatable/equatable.dart';

enum TajweedRule { none, ghunnah, idgham, ikhfa, qalqalah, madd, waqf }

enum MakhrajCategory { jawf, halq, lisan, shafatan, khayshum }

/// Base-letter decomposition shared by contract with the backend
/// (`backend_server/services/arabic.py`): harakat, shadda, sukun, Quranic
/// annotation marks and tatweel are attached marks, not letters.
bool isArabicMark(int cp) =>
    (cp >= 0x064B && cp <= 0x065F) ||
    cp == 0x0670 ||
    (cp >= 0x06D6 && cp <= 0x06ED) ||
    (cp >= 0x0610 && cp <= 0x061A) ||
    cp == 0x0640;

bool isArabicLetter(int cp) =>
    ((cp >= 0x0621 && cp <= 0x064A) || (cp >= 0x0671 && cp <= 0x06D3)) &&
    !isArabicMark(cp);

const _sukun = 0x0652, _shadda = 0x0651, _maddah = 0x0653;
const _qalqalahLetters = {'ق', 'ط', 'ب', 'ج', 'د'};

MakhrajCategory makhrajOf(String ch) {
  const halq = 'ءهعحغخأإآؤئ';
  const shafatan = 'بمو';
  const jawf = 'اٱىي';
  if (halq.contains(ch)) return MakhrajCategory.halq;
  if (shafatan.contains(ch)) return MakhrajCategory.shafatan;
  if (jawf.contains(ch)) return MakhrajCategory.jawf;
  return MakhrajCategory.lisan;
}

class Letter extends Equatable {
  final int letterIndex;
  final String char;
  final String phonemeCode;
  final TajweedRule tajweedRule;
  final MakhrajCategory makhrajCategory;
  final double? latestScore;
  final int readCount;

  const Letter({
    required this.letterIndex,
    required this.char,
    required this.phonemeCode,
    this.tajweedRule = TajweedRule.none,
    this.makhrajCategory = MakhrajCategory.lisan,
    this.latestScore,
    this.readCount = 0,
  });

  /// Splits a word into letters. Each letter keeps its attached marks in
  /// [char] so the concatenation of all letters equals the word exactly.
  static List<Letter> decompose(String word) {
    final runes = word.runes.toList();
    final groups = <List<int>>[];
    for (final r in runes) {
      if (isArabicLetter(r) || groups.isEmpty) {
        groups.add([r]);
      } else {
        groups.last.add(r);
      }
    }
    return [
      for (var i = 0; i < groups.length; i++) _fromGroup(i, groups[i]),
    ];
  }

  static Letter _fromGroup(int index, List<int> g) {
    final base = String.fromCharCode(g.first);
    final marks = g.skip(1).toSet();
    var rule = TajweedRule.none;
    if (_qalqalahLetters.contains(base) && marks.contains(_sukun)) {
      rule = TajweedRule.qalqalah;
    } else if ((base == 'ن' || base == 'م') && marks.contains(_shadda)) {
      rule = TajweedRule.ghunnah;
    } else if (marks.contains(_maddah)) {
      rule = TajweedRule.madd;
    }
    return Letter(
      letterIndex: index,
      char: String.fromCharCodes(g),
      phonemeCode: base,
      tajweedRule: rule,
      makhrajCategory: makhrajOf(base),
    );
  }

  Letter copyWith({double? latestScore, int? readCount}) => Letter(
        letterIndex: letterIndex,
        char: char,
        phonemeCode: phonemeCode,
        tajweedRule: tajweedRule,
        makhrajCategory: makhrajCategory,
        latestScore: latestScore ?? this.latestScore,
        readCount: readCount ?? this.readCount,
      );

  @override
  List<Object?> get props =>
      [letterIndex, char, phonemeCode, tajweedRule, makhrajCategory, latestScore, readCount];
}

class Word extends Equatable {
  final int wordId;
  final int wordPosition;
  final String textUthmani;
  final String textImlaei;
  final String translation;
  final int? startTimeMs;
  final int? endTimeMs;
  final List<Letter> letters;

  const Word({
    required this.wordId,
    required this.wordPosition,
    required this.textUthmani,
    this.textImlaei = '',
    this.translation = '',
    this.startTimeMs,
    this.endTimeMs,
    this.letters = const [],
  });

  factory Word.fromApi(Map<String, dynamic> j) {
    final uthmani = j['text_uthmani'] as String;
    return Word(
      wordId: j['id'] as int,
      wordPosition: j['position'] as int,
      textUthmani: uthmani,
      textImlaei: (j['text_imlaei'] as String?) ?? '',
      translation: ((j['translation'] as Map?)?['text'] as String?) ?? '',
      letters: Letter.decompose(uthmani),
    );
  }

  Word copyWith({int? startTimeMs, int? endTimeMs, List<Letter>? letters}) => Word(
        wordId: wordId,
        wordPosition: wordPosition,
        textUthmani: textUthmani,
        textImlaei: textImlaei,
        translation: translation,
        startTimeMs: startTimeMs ?? this.startTimeMs,
        endTimeMs: endTimeMs ?? this.endTimeMs,
        letters: letters ?? this.letters,
      );

  @override
  List<Object?> get props => [wordId, wordPosition, textUthmani, textImlaei, translation, startTimeMs, endTimeMs, letters];
}

class VerseAudio extends Equatable {
  final String url;
  const VerseAudio(this.url);
  @override
  List<Object?> get props => [url];
}

class QuranVerse extends Equatable {
  final String verseKey;
  final int surahNumber;
  final int verseNumber;
  final int juz;
  final int page;
  final String textUthmani;
  final String textImlaei;
  final int translationId;
  final String translationText;
  final VerseAudio? audio;
  final List<Word> words;

  const QuranVerse({
    required this.verseKey,
    required this.surahNumber,
    required this.verseNumber,
    required this.juz,
    required this.page,
    required this.textUthmani,
    required this.textImlaei,
    this.translationId = 33,
    this.translationText = '',
    this.audio,
    this.words = const [],
  });

  /// Parses one element of Quran.com v4 `verses[]`. The ayah-number marker
  /// (`char_type_name == "end"`) is not a word and is excluded.
  factory QuranVerse.fromApi(Map<String, dynamic> j, {int translationId = 33}) {
    final key = j['verse_key'] as String;
    final parts = key.split(':');
    final rawWords = (j['words'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .where((w) => w['char_type_name'] != 'end');
    final translations = (j['translations'] as List? ?? const []).cast<Map<String, dynamic>>();
    final tr = translations.where((t) => t['resource_id'] == translationId);
    return QuranVerse(
      verseKey: key,
      surahNumber: int.parse(parts[0]),
      verseNumber: j['verse_number'] as int? ?? int.parse(parts[1]),
      juz: j['juz_number'] as int,
      page: j['page_number'] as int,
      textUthmani: j['text_uthmani'] as String,
      textImlaei: (j['text_imlaei'] as String?) ?? '',
      translationId: translationId,
      translationText: tr.isEmpty ? '' : tr.first['text'] as String,
      words: rawWords.map(Word.fromApi).toList(),
    );
  }

  QuranVerse copyWith({VerseAudio? audio, List<Word>? words}) => QuranVerse(
        verseKey: verseKey,
        surahNumber: surahNumber,
        verseNumber: verseNumber,
        juz: juz,
        page: page,
        textUthmani: textUthmani,
        textImlaei: textImlaei,
        translationId: translationId,
        translationText: translationText,
        audio: audio ?? this.audio,
        words: words ?? this.words,
      );

  @override
  List<Object?> get props => [verseKey, surahNumber, verseNumber, juz, page, textUthmani, textImlaei, translationId, translationText, audio, words];
}
