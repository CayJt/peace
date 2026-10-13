import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../database/quran_database.dart';
import '../models/quran_models.dart';

enum LetterStatus { idle, cursor, pass, needRetry }

typedef ChannelFactory = WebSocketChannel Function(Uri uri);

abstract class AssessmentEvent extends Equatable {
  const AssessmentEvent();
  @override
  List<Object?> get props => [];
}

class AssessmentStarted extends AssessmentEvent {
  final QuranVerse verse;
  const AssessmentStarted(this.verse);
  @override
  List<Object?> get props => [verse.verseKey];
}

class AudioChunk extends AssessmentEvent {
  final Uint8List pcm16k;
  const AudioChunk(this.pcm16k);
}

class ServerMessage extends AssessmentEvent {
  final Map<String, dynamic> json;
  const ServerMessage(this.json);
  @override
  List<Object?> get props => [json];
}

class AssessmentStopped extends AssessmentEvent {
  const AssessmentStopped();
}

class AssessmentState extends Equatable {
  final String? verseKey;
  final bool listening;
  final Map<String, LetterStatus> letters; // "word:letter" -> status
  final Map<String, double> scores;
  final double? average;
  final String? error;

  const AssessmentState({
    this.verseKey,
    this.listening = false,
    this.letters = const {},
    this.scores = const {},
    this.average,
    this.error,
  });

  static String key(int wordPosition, int letterIndex) => '$wordPosition:$letterIndex';

  LetterStatus statusOf(int w, int l) => letters[key(w, l)] ?? LetterStatus.idle;

  /// Running average of this session's letter scores (null before the first).
  double? get liveAverage =>
      scores.isEmpty ? null : scores.values.reduce((a, b) => a + b) / scores.length;

  AssessmentState copyWith({
    String? verseKey,
    bool? listening,
    Map<String, LetterStatus>? letters,
    Map<String, double>? scores,
    double? average,
    String? error,
  }) =>
      AssessmentState(
        verseKey: verseKey ?? this.verseKey,
        listening: listening ?? this.listening,
        letters: letters ?? this.letters,
        scores: scores ?? this.scores,
        average: average ?? this.average,
        error: error,
      );

  @override
  List<Object?> get props => [verseKey, listening, letters, scores, average, error];
}

/// Streams mic PCM to the backend and turns LETTER_ASSESSED events into
/// cursor / pass / need_retry letter states, persisting scores to SQLite.
class TajweedAssessmentBloc extends Bloc<AssessmentEvent, AssessmentState> {
  TajweedAssessmentBloc({
    required this.db,
    required this.wsBase,
    ChannelFactory? channelFactory,
  })  : _connect = channelFactory ?? WebSocketChannel.connect,
        super(const AssessmentState()) {
    on<AssessmentStarted>(_onStart);
    on<AudioChunk>((e, emit) => _channel?.sink.add(e.pcm16k));
    on<ServerMessage>(_onMessage);
    on<AssessmentStopped>(_onStop);
  }

  final QuranDatabase db;
  final String wsBase; // e.g. ws://10.0.2.2:8000
  final ChannelFactory _connect;
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  QuranVerse? _verse;

  Future<void> _onStart(AssessmentStarted e, Emitter<AssessmentState> emit) async {
    await _close();
    _verse = e.verse;
    final ch = _connect(Uri.parse('$wsBase/ws/assess-tajweed/${e.verse.verseKey}'));
    _channel = ch;
    _sub = ch.stream.listen(
      (m) {
        try {
          add(ServerMessage(jsonDecode(m as String) as Map<String, dynamic>));
        } on FormatException {
          // ignore malformed frames
        }
      },
      onError: (Object err) => add(ServerMessage({'event': 'ERROR', 'message': '$err'})),
      onDone: () => add(const AssessmentStopped()),
    );
    emit(AssessmentState(
      verseKey: e.verse.verseKey,
      listening: true,
      letters: {AssessmentState.key(1, 0): LetterStatus.cursor},
    ));
  }

  /// The letter after (w, l) in verse order, or null at the end.
  (int, int)? _next(int w, int l) {
    final words = _verse?.words ?? const [];
    final wi = words.indexWhere((x) => x.wordPosition == w);
    if (wi < 0) return null;
    if (l + 1 < words[wi].letters.length) return (w, l + 1);
    if (wi + 1 < words.length) return (words[wi + 1].wordPosition, 0);
    return null;
  }

  Future<void> _onMessage(ServerMessage e, Emitter<AssessmentState> emit) async {
    final m = e.json;
    switch (m['event']) {
      case 'LETTER_ASSESSED':
        final w = m['word_position'] as int, l = m['letter_index'] as int;
        final score = (m['score'] as num).toDouble();
        final letters = {...state.letters};
        letters[AssessmentState.key(w, l)] =
            m['status'] == 'PASS' ? LetterStatus.pass : LetterStatus.needRetry;
        final nx = _next(w, l);
        if (nx != null) letters[AssessmentState.key(nx.$1, nx.$2)] = LetterStatus.cursor;
        final scores = {...state.scores, AssessmentState.key(w, l): score};
        emit(state.copyWith(letters: letters, scores: scores));
        final verse = _verse;
        if (verse != null) {
          final word = verse.words.where((x) => x.wordPosition == w);
          if (word.isNotEmpty && l < word.first.letters.length) {
            await db.recordLetterScore(word.first.letters[l].phonemeCode, score);
            await db.recordLetterAssessment(verse.verseKey, w, l, score);
          }
        }
      case 'VERSE_SUMMARY':
        emit(state.copyWith(listening: false, average: (m['average_score'] as num).toDouble()));
      case 'ERROR':
        emit(state.copyWith(listening: false, error: m['message'] as String? ?? 'error'));
    }
  }

  Future<void> _onStop(AssessmentStopped e, Emitter<AssessmentState> emit) async {
    _channel?.sink.add(jsonEncode({'event': 'END'}));
    await _close();
    emit(state.copyWith(listening: false));
  }

  Future<void> _close() async {
    await _sub?.cancel();
    _sub = null;
    await _channel?.sink.close();
    _channel = null;
  }

  @override
  Future<void> close() async {
    await _close();
    return super.close();
  }
}
