import '../database/quran_database.dart';
import 'quran_api_service.dart';
import 'quran_integrity_verifier.dart';

/// QA audit: re-fetches every cached page from Quran.com and compares the
/// SHA-256 of each verse with the local copy. Not for production builds.
class MushafAudit {
  MushafAudit(this._api, this._db, {QuranIntegrityVerifier verifier = const QuranIntegrityVerifier()})
      : _verifier = verifier;

  static const totalVerses = 6236;
  final QuranApiService _api;
  final QuranDatabase _db;
  final QuranIntegrityVerifier _verifier;

  Future<AuditReport> run({void Function(double)? onProgress}) async {
    final local = {for (final v in await _db.getAllVerses()) v.verseKey: v};
    final problems = <String>[];
    var verified = 0;
    final seen = <String>{};
    for (var p = 1; p <= 604; p++) {
      final page = await _api.fetchPage(p);
      for (final raw in page.raw) {
        final key = raw['verse_key'] as String;
        seen.add(key);
        final v = local[key];
        if (v == null) {
          problems.add('$key: missing locally');
        } else if (QuranIntegrityVerifier.hashLocal(v) != _verifier.hashRaw(raw)) {
          problems.add(_verifier.verifyVerseIntegrity(v, raw).report());
        } else {
          verified++;
        }
      }
      onProgress?.call(p / 604);
    }
    if (seen.length != totalVerses) {
      problems.add('API returned ${seen.length} verses, expected $totalVerses');
    }
    return AuditReport(totalVerses, verified, problems);
  }
}
