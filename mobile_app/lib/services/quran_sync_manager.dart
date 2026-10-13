import '../database/quran_database.dart';
import '../models/quran_models.dart';
import 'quran_api_service.dart';

/// Offline-first access to the 604 Madinah pages: SQLite first, API on miss.
class QuranSyncManager {
  QuranSyncManager(this._api, this._db, {this.reciterId = 7});

  final QuranApiService _api;
  final QuranDatabase _db;
  final int reciterId; // 7 = Mishari Rashid al-Afasy on Quran.com
  final _recitations = <int, ChapterRecitation>{};

  Future<List<QuranVerse>> getPage(int page) async {
    if (await _db.hasPage(page)) return _db.getVersesByPage(page);
    return (await syncPage(page)).verses;
  }

  /// Downloads one page (and chapter timestamps when available) into SQLite.
  Future<PageResult> syncPage(int page) async {
    final result = await _api.fetchPage(page);
    var verses = result.verses;
    for (final chapter in verses.map((v) => v.surahNumber).toSet()) {
      try {
        final rec = _recitations[chapter] ??=
            await _api.fetchChapterRecitation(reciterId, chapter);
        verses = [
          for (final v in verses)
            v.surahNumber == chapter ? QuranApiService.applyRecitation(v, rec) : v
        ];
      } on Exception {
        // Audio timing is optional: text must still be cached for offline reading.
      }
    }
    await _db.saveVerses(verses);
    return PageResult(verses, result.raw);
  }

  /// Downloads every page in [from]..[to], reporting progress (0..1).
  Future<void> syncRange({int from = 1, int to = 604, void Function(double)? onProgress}) async {
    for (var p = from; p <= to; p++) {
      if (!await _db.hasPage(p)) await syncPage(p);
      onProgress?.call((p - from + 1) / (to - from + 1));
    }
  }
}
