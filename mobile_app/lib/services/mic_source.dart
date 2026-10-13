import 'dart:io';
import 'dart:typed_data';

import 'package:record/record.dart';

/// Microphone abstraction so UI/bloc code is testable without hardware.
abstract class MicSource {
  Future<bool> requestPermission();

  /// 16 kHz mono PCM16 little-endian chunks.
  Future<Stream<Uint8List>> startPcmStream();

  /// Records a WAV file (hold-to-speak). Returns the file path on [stopFile].
  Future<void> startFile();
  Future<String?> stopFile();

  Future<void> stop();
  Future<void> dispose();
}

class RecordMicSource implements MicSource {
  final _rec = AudioRecorder();

  @override
  Future<bool> requestPermission() => _rec.hasPermission();

  @override
  Future<Stream<Uint8List>> startPcmStream() => _rec.startStream(
      const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: 16000, numChannels: 1));

  @override
  Future<void> startFile() => _rec.start(
        const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
        path: '${Directory.systemTemp.path}/chat_${DateTime.now().millisecondsSinceEpoch}.wav',
      );

  @override
  Future<String?> stopFile() => _rec.stop();

  @override
  Future<void> stop() async {
    if (await _rec.isRecording()) await _rec.stop();
  }

  @override
  Future<void> dispose() => _rec.dispose();
}
