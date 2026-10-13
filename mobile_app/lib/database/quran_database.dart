import 'package:sqflite/sqflite.dart';

import '../models/quran_models.dart';

class QuranDatabase {
  QuranDatabase._(this._db);
  final Database _db;

  /// Opens (creating if needed) the database. Pass [inMemoryPath] =
  /// `inMemoryDatabasePath` in tests; [factory] lets tests inject sqflite_ffi.
  static Future<QuranDatabase> open({String? path, DatabaseFactory? factory}) async {
    final f = factory ?? databaseFactory;
    final db = await f.openDatabase(
      path ?? '${await f.getDatabasesPath()}/quran.db',
      options: OpenDatabaseOptions(version: 1, onCreate: _create),
    );
    return QuranDatabase._(db);
  }

  static Future<void> _create(Database db, int v) async {
    await db.execute('''CREATE TABLE verses(
      verse_key TEXT PRIMARY KEY, surah_number INTEGER NOT NULL, verse_number INTEGER NOT NULL,
      juz INTEGER NOT NULL, page INTEGER NOT NULL, text_uthmani TEXT NOT NULL,
      text_imlaei TEXT NOT NULL, translation_id INTEGER NOT NULL, translation_text TEXT NOT NULL,
      audio_url TEXT)''');
    await db.execute('CREATE INDEX idx_verses_page ON verses(page, surah_number, verse_number)');
    await db.execute('''CREATE TABLE words(
      word_id INTEGER PRIMARY KEY, verse_key TEXT NOT NULL, word_position INTEGER NOT NULL,
      text_uthmani TEXT NOT NULL, text_imlaei TEXT NOT NULL, translation TEXT NOT NULL,
      start_time_ms INTEGER, end_time_ms INTEGER,
      FOREIGN KEY(verse_key) REFERENCES verses(verse_key) ON DELETE CASCADE)''');
    await db.execute('CREATE INDEX idx_words_verse ON words(verse_key, word_position)');
    await db.execute('''CREATE TABLE letters(
      verse_key TEXT NOT NULL, word_position INTEGER NOT NULL, letter_index INTEGER NOT NULL,
      char TEXT NOT NULL, phoneme_code TEXT NOT NULL, tajweed_rule TEXT NOT NULL,
      makhraj_category TEXT NOT NULL, latest_score REAL, read_count INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY(verse_key, word_position, letter_index))''');
    await db.execute('''CREATE TABLE user_letter_scores(
      letter_key TEXT PRIMARY KEY, phoneme_code TEXT NOT NULL, total_score REAL NOT NULL,
      attempts_count INTEGER NOT NULL, average_score REAL NOT NULL, last_read_at INTEGER NOT NULL)''');
    await db.execute('''CREATE TABLE reading_sessions(
      id INTEGER PRIMARY KEY AUTOINCREMENT, page INTEGER NOT NULL, duration_sec INTEGER NOT NULL,
      letters_evaluated INTEGER NOT NULL, score REAL NOT NULL, created_at INTEGER NOT NULL)''');
  }

  Future<void> close() => _db.close();

  /// Stores a verse with its words and letters (replacing any previous copy).
  Future<void> saveVerses(List<QuranVerse> verses) async {
    await _db.transaction((txn) async {
      final b = txn.batch();
      for (final v in verses) {
        b.delete('words', where: 'verse_key = ?', whereArgs: [v.verseKey]);
        b.delete('letters', where: 'verse_key = ? AND latest_score IS NULL', whereArgs: [v.verseKey]);
        b.insert('verses', {
          'verse_key': v.verseKey,
          'surah_number': v.surahNumber,
          'verse_number': v.verseNumber,
          'juz': v.juz,
          'page': v.page,
          'text_uthmani': v.textUthmani,
          'text_imlaei': v.textImlaei,
          'translation_id': v.translationId,
          'translation_text': v.translationText,
          'audio_url': v.audio?.url,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        for (final w in v.words) {
          b.insert('words', {
            'word_id': w.wordId,
            'verse_key': v.verseKey,
            'word_position': w.wordPosition,
            'text_uthmani': w.textUthmani,
            'text_imlaei': w.textImlaei,
            'translation': w.translation,
            'start_time_ms': w.startTimeMs,
            'end_time_ms': w.endTimeMs,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
          for (final l in w.letters) {
            b.insert('letters', {
              'verse_key': v.verseKey,
              'word_position': w.wordPosition,
              'letter_index': l.letterIndex,
              'char': l.char,
              'phoneme_code': l.phonemeCode,
              'tajweed_rule': l.tajweedRule.name,
              'makhraj_category': l.makhrajCategory.name,
              'latest_score': l.latestScore,
              'read_count': l.readCount,
            }, conflictAlgorithm: ConflictAlgorithm.ignore);
          }
        }
      }
      await b.commit(noResult: true);
    });
  }

  Future<bool> hasPage(int page) async {
    final r = await _db.rawQuery('SELECT COUNT(*) c FROM verses WHERE page = ?', [page]);
    return (r.first['c'] as int) > 0;
  }

  Future<int> verseCount() async =>
      (await _db.rawQuery('SELECT COUNT(*) c FROM verses')).first['c'] as int;

  Future<List<QuranVerse>> getAllVerses() async => _hydrate(
      await _db.query('verses', orderBy: 'surah_number, verse_number'));

  Future<List<QuranVerse>> getVersesByPage(int pageNumber) async {
    if (pageNumber < 1 || pageNumber > 604) {
      throw RangeError.range(pageNumber, 1, 604, 'pageNumber');
    }
    return _hydrate(await _db.query('verses',
        where: 'page = ?', whereArgs: [pageNumber], orderBy: 'surah_number, verse_number'));
  }

  Future<List<QuranVerse>> _hydrate(List<Map<String, Object?>> rows) async {
    final out = <QuranVerse>[];
    for (final r in rows) {
      final key = r['verse_key'] as String;
      final wordRows = await _db.query('words',
          where: 'verse_key = ?', whereArgs: [key], orderBy: 'word_position');
      final letterRows = await _db.query('letters',
          where: 'verse_key = ?', whereArgs: [key], orderBy: 'word_position, letter_index');
      final byWord = <int, List<Letter>>{};
      for (final l in letterRows) {
        byWord.putIfAbsent(l['word_position'] as int, () => []).add(Letter(
              letterIndex: l['letter_index'] as int,
              char: l['char'] as String,
              phonemeCode: l['phoneme_code'] as String,
              tajweedRule: TajweedRule.values.byName(l['tajweed_rule'] as String),
              makhrajCategory: MakhrajCategory.values.byName(l['makhraj_category'] as String),
              latestScore: (l['latest_score'] as num?)?.toDouble(),
              readCount: l['read_count'] as int,
            ));
      }
      out.add(QuranVerse(
        verseKey: key,
        surahNumber: r['surah_number'] as int,
        verseNumber: r['verse_number'] as int,
        juz: r['juz'] as int,
        page: r['page'] as int,
        textUthmani: r['text_uthmani'] as String,
        textImlaei: r['text_imlaei'] as String,
        translationId: r['translation_id'] as int,
        translationText: r['translation_text'] as String,
        audio: r['audio_url'] == null ? null : VerseAudio(r['audio_url'] as String),
        words: [
          for (final w in wordRows)
            Word(
              wordId: w['word_id'] as int,
              wordPosition: w['word_position'] as int,
              textUthmani: w['text_uthmani'] as String,
              textImlaei: w['text_imlaei'] as String,
              translation: w['translation'] as String,
              startTimeMs: w['start_time_ms'] as int?,
              endTimeMs: w['end_time_ms'] as int?,
              letters: byWord[w['word_position'] as int] ?? const [],
            ),
        ],
      ));
    }
    return out;
  }

  /// Accumulates a score for a phoneme across all attempts.
  Future<void> recordLetterScore(String phonemeCode, double score) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction((txn) async {
      final rows = await txn.query('user_letter_scores', where: 'letter_key = ?', whereArgs: [phonemeCode]);
      final total = (rows.isEmpty ? 0.0 : (rows.first['total_score'] as num).toDouble()) + score;
      final n = (rows.isEmpty ? 0 : rows.first['attempts_count'] as int) + 1;
      await txn.insert(
        'user_letter_scores',
        {
          'letter_key': phonemeCode,
          'phoneme_code': phonemeCode,
          'total_score': total,
          'attempts_count': n,
          'average_score': total / n,
          'last_read_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  /// Updates the per-position letter (cursor/pass/retry state).
  Future<void> recordLetterAssessment(String verseKey, int wordPosition, int letterIndex, double score) =>
      _db.rawUpdate(
        'UPDATE letters SET latest_score = ?, read_count = read_count + 1 '
        'WHERE verse_key = ? AND word_position = ? AND letter_index = ?',
        [score, verseKey, wordPosition, letterIndex],
      );

  Future<void> recordReadingSession(int page, int durationSec, int lettersEvaluated, double score) =>
      _db.insert('reading_sessions', {
        'page': page,
        'duration_sec': durationSec,
        'letters_evaluated': lettersEvaluated,
        'score': score,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

  Future<List<Map<String, Object?>>> recentSessions({int limit = 20}) =>
      _db.query('reading_sessions', orderBy: 'created_at DESC, id DESC', limit: limit);

  /// Seconds read per local day for the last [days] days (oldest first).
  Future<List<int>> secondsPerDay({int days = 7, DateTime? now}) async {
    final today = DateTime.fromMillisecondsSinceEpoch((now ?? DateTime.now()).millisecondsSinceEpoch);
    final start = DateTime(today.year, today.month, today.day).subtract(Duration(days: days - 1));
    final rows = await _db.query('reading_sessions',
        where: 'created_at >= ?', whereArgs: [start.millisecondsSinceEpoch]);
    final out = List<int>.filled(days, 0);
    for (final r in rows) {
      final d = DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int);
      final idx = DateTime(d.year, d.month, d.day).difference(start).inDays;
      if (idx >= 0 && idx < days) out[idx] += r['duration_sec'] as int;
    }
    return out;
  }

  Future<Map<String, dynamic>> getOverallScoreSummary() async {
    final l = (await _db.rawQuery(
            'SELECT COALESCE(SUM(total_score),0) t, COALESCE(SUM(attempts_count),0) n FROM user_letter_scores'))
        .first;
    final s = (await _db.rawQuery(
            'SELECT COUNT(*) c, COALESCE(SUM(duration_sec),0) d, COUNT(DISTINCT page) p FROM reading_sessions'))
        .first;
    final n = l['n'] as int;
    return {
      'average_score': n == 0 ? 0.0 : (l['t'] as num).toDouble() / n,
      'letters_evaluated': n,
      'sessions_count': s['c'],
      'total_seconds': s['d'],
      'pages_read': s['p'],
    };
  }
}
