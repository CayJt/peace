import 'dart:typed_data';

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app/bloc/tajweed_assessment_bloc.dart';
import 'package:quran_app/database/quran_database.dart';
import 'package:quran_app/models/quran_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fixtures/api_fixtures.dart';
import 'helpers.dart';

void main() {
  sqfliteFfiInit();
  late QuranDatabase db;
  late FakeChannel ch;
  late Uri connected;
  late TajweedAssessmentBloc bloc;
  late QuranVerse verse;

  setUp(() async {
    db = await QuranDatabase.open(path: inMemoryDatabasePath, factory: databaseFactoryFfi);
    verse = QuranVerse.fromApi(fatihah1);
    await db.saveVerses([verse]);
    ch = FakeChannel();
    bloc = TajweedAssessmentBloc(db: db, wsBase: 'ws://h', channelFactory: (u) {
      connected = u;
      return ch;
    });
  });
  tearDown(() async {
    await bloc.close();
    await db.close();
  });

  void server(Map<String, dynamic> m) => ch.incoming.add(jsonEncode(m));
  Map<String, dynamic> assessed(int w, int l, double s, String st) =>
      {'event': 'LETTER_ASSESSED', 'word_position': w, 'letter_index': l, 'score': s, 'status': st};

  test('start connects to the verse endpoint and places the cursor on letter 1', () async {
    bloc.add(AssessmentStarted(verse));
    await pumpEventQueue();
    expect(connected.toString(), 'ws://h/ws/assess-tajweed/1:1');
    expect(bloc.state.listening, isTrue);
    expect(bloc.state.statusOf(1, 0), LetterStatus.cursor);
  });

  test('audio is forwarded to the socket as binary', () async {
    bloc.add(AssessmentStarted(verse));
    await pumpEventQueue();
    bloc.add(AudioChunk(Uint8List.fromList([1, 2, 3])));
    await pumpEventQueue();
    expect(ch.sent.single, [1, 2, 3]);
  });

  test('PASS -> pass + cursor advances; low score -> needRetry', () async {
    bloc.add(AssessmentStarted(verse));
    await pumpEventQueue();
    server(assessed(1, 0, 0.94, 'PASS'));
    await pumpEventQueue();
    expect(bloc.state.statusOf(1, 0), LetterStatus.pass);
    expect(bloc.state.statusOf(1, 1), LetterStatus.cursor);
    server(assessed(1, 1, 0.3, 'NEED_RETRY'));
    await pumpEventQueue();
    expect(bloc.state.statusOf(1, 1), LetterStatus.needRetry);
    expect(bloc.state.statusOf(1, 2), LetterStatus.cursor);
    expect(bloc.state.liveAverage, closeTo(0.62, 1e-9));
    await pumpEventQueue(times: 50); // let persistence finish before tearDown closes the db
  });

  test('cursor crosses into the next word', () async {
    bloc.add(AssessmentStarted(verse));
    await pumpEventQueue();
    final last = verse.words.first.letters.length - 1; // ب س م -> index 2
    server(assessed(1, last, 1.0, 'PASS'));
    await pumpEventQueue();
    expect(bloc.state.statusOf(2, 0), LetterStatus.cursor);
  });

  test('scores are persisted to SQLite (user_letter_scores and the letter row)', () async {
    bloc.add(AssessmentStarted(verse));
    await pumpEventQueue();
    server(assessed(1, 0, 0.8, 'PASS'));
    await pumpEventQueue(times: 50);
    final s = await db.getOverallScoreSummary();
    expect(s['letters_evaluated'], 1);
    expect(s['average_score'], closeTo(0.8, 1e-9));
    final l = (await db.getVersesByPage(1)).single.words.first.letters.first;
    expect(l.latestScore, 0.8);
  });

  test('VERSE_SUMMARY stops listening and records the average', () async {
    bloc.add(AssessmentStarted(verse));
    await pumpEventQueue();
    server({'event': 'VERSE_SUMMARY', 'verse_key': '1:1', 'letters_assessed': 3, 'average_score': 0.77});
    await pumpEventQueue();
    expect(bloc.state.listening, isFalse);
    expect(bloc.state.average, 0.77);
  });

  test('server ERROR is surfaced', () async {
    bloc.add(AssessmentStarted(verse));
    await pumpEventQueue();
    server({'event': 'ERROR', 'message': 'unknown verse'});
    await pumpEventQueue();
    expect(bloc.state.error, 'unknown verse');
    expect(bloc.state.listening, isFalse);
  });

  test('stop sends END and closes the socket', () async {
    bloc.add(AssessmentStarted(verse));
    await pumpEventQueue();
    bloc.add(const AssessmentStopped());
    await pumpEventQueue();
    expect(ch.sent.last, '{"event":"END"}');
    expect(ch.closed, isTrue);
    expect(bloc.state.listening, isFalse);
  });

  test('malformed frames are ignored', () async {
    bloc.add(AssessmentStarted(verse));
    await pumpEventQueue();
    ch.incoming.add('not json');
    await pumpEventQueue();
    expect(bloc.state.listening, isTrue);
  });

  test('READY records which engine the server is using', () async {
    bloc.add(AssessmentStarted(verse));
    await pumpEventQueue();
    server({'event': 'READY', 'verse_key': '1:1', 'letters': 12, 'engine': 'energy'});
    await pumpEventQueue();
    expect(bloc.state.engine, 'energy');
    expect(bloc.state.listening, isTrue);
  });
}
