import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/quran_models.dart';

class QuranApiException implements Exception {
  final String message;
  QuranApiException(this.message);
  @override
  String toString() => 'QuranApiException: $message';
}

/// Parsed page: typed verses plus the raw JSON elements (for integrity checks).
class PageResult {
  final List<QuranVerse> verses;
  final List<Map<String, dynamic>> raw;
  PageResult(this.verses, this.raw);
}

/// Per-chapter recitation: audio file and word segments per verse.
class ChapterRecitation {
  final String audioUrl;
  final Map<String, List<List<int>>> segmentsByVerse; // [word_position, start_ms, end_ms]
  ChapterRecitation(this.audioUrl, this.segmentsByVerse);
}

class QuranApiService {
  QuranApiService({http.Client? client, this.baseUrl = 'https://api.quran.com/api/v4'})
      : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  static const translationId = 33; // Indonesian (Kemenag)

  /// `fields=text_uthmani,text_imlaei` and `per_page=50` are added to the
  /// requested query: without them verse-level text is absent and the API
  /// pages results at 10 verses.
  Uri pageUri(int page) => Uri.parse('$baseUrl/verses/by_page/$page').replace(queryParameters: {
        'language': 'id',
        'words': 'true',
        'word_fields': 'text_uthmani,text_imlaei,location',
        'translations': '$translationId',
        'fields': 'text_uthmani,text_imlaei',
        'per_page': '50',
      });

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final r = await _client.get(uri);
    if (r.statusCode != 200) {
      throw QuranApiException('GET $uri -> ${r.statusCode}');
    }
    return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  Future<PageResult> fetchPage(int page) async {
    if (page < 1 || page > 604) throw RangeError.range(page, 1, 604, 'page');
    final json = await _getJson(pageUri(page));
    final raw = (json['verses'] as List).cast<Map<String, dynamic>>();
    return PageResult(
      raw.map((v) => QuranVerse.fromApi(v, translationId: translationId)).toList(),
      raw,
    );
  }

  Future<ChapterRecitation> fetchChapterRecitation(int reciterId, int chapter) async {
    final json = await _getJson(Uri.parse('$baseUrl/chapter_recitations/$reciterId/$chapter')
        .replace(queryParameters: {'segments': 'true'}));
    final file = json['audio_file'] as Map<String, dynamic>;
    final segs = <String, List<List<int>>>{};
    for (final t in (file['timestamps'] as List? ?? const []).cast<Map<String, dynamic>>()) {
      segs[t['verse_key'] as String] = [
        for (final s in (t['segments'] as List? ?? const []))
          [for (final n in (s as List)) (n as num).toInt()],
      ];
    }
    return ChapterRecitation(file['audio_url'] as String, segs);
  }

  /// Applies recitation segments to verse words: each segment is
  /// `[word_position, start_ms, end_ms]` (segments of other shapes are skipped).
  static QuranVerse applyRecitation(QuranVerse v, ChapterRecitation rec) {
    final segs = rec.segmentsByVerse[v.verseKey];
    final byPos = <int, List<int>>{
      for (final s in segs ?? const <List<int>>[])
        if (s.length >= 3) s[0]: s,
    };
    return v.copyWith(
      audio: VerseAudio(rec.audioUrl),
      words: [
        for (final w in v.words)
          byPos.containsKey(w.wordPosition)
              ? w.copyWith(startTimeMs: byPos[w.wordPosition]![1], endTimeMs: byPos[w.wordPosition]![2])
              : w,
      ],
    );
  }
}
