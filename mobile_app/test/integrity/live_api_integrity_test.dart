// Opt-in: hits the real Quran.com API v4.
//   QURAN_LIVE=1 flutter test test/integrity/live_api_integrity_test.dart
// Establishes authenticity of the *pipeline* on real data: fetch -> model ->
// SQLite -> verifier. Skipped by default (CI has no guarantee of network).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app/database/quran_database.dart';
import 'package:quran_app/services/quran_api_service.dart';
import 'package:quran_app/services/quran_integrity_verifier.dart';
import 'package:quran_app/services/quran_sync_manager.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final live = Platform.environment['QURAN_LIVE'] == '1';
  sqfliteFfiInit();

  // Al-Fatihah, Al-Baqarah start, Ayat Kursi page, At-Taubah start, Al-Ikhlas.
  for (final page in [1, 2, 42, 187, 604]) {
    test('page $page: SQLite copy matches API payload exactly', () async {
      final api = QuranApiService();
      final db = await QuranDatabase.open(path: inMemoryDatabasePath, factory: databaseFactoryFfi);
      final sync = QuranSyncManager(api, db);
      final fetched = await sync.syncPage(page);
      final stored = await db.getVersesByPage(page);
      const v = QuranIntegrityVerifier();
      expect(stored.length, fetched.raw.length);
      for (var i = 0; i < stored.length; i++) {
        final r = v.verifyVerseIntegrity(stored[i], fetched.raw[i]);
        expect(r.ok, isTrue, reason: r.report());
        expect(stored[i].page, page);
      }
      await db.close();
    }, skip: live ? false : 'set QURAN_LIVE=1 to run against api.quran.com');
  }
}
