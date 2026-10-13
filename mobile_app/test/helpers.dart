import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quran_app/services/mic_source.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class MockLocalAuth extends Mock implements LocalAuthentication {}

/// In-memory stand-in for the platform keychain.
class FakeSecureStorage extends Fake implements FlutterSecureStorage {
  final data = <String, String>{};
  @override
  Future<String?> read({required String key, IOSOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, MacOsOptions? mOptions, WindowsOptions? wOptions}) async => data[key];
  @override
  Future<void> write({required String key, required String? value, IOSOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, MacOsOptions? mOptions, WindowsOptions? wOptions}) async {
    if (value == null) {
      data.remove(key);
    } else {
      data[key] = value;
    }
  }
  @override
  Future<void> delete({required String key, IOSOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, MacOsOptions? mOptions, WindowsOptions? wOptions}) async => data.remove(key);
}

class FakeMic implements MicSource {
  final chunks = StreamController<Uint8List>();
  bool permission = true;
  @override
  Future<bool> requestPermission() async => permission;
  @override
  Future<Stream<Uint8List>> startPcmStream() async => chunks.stream;
  @override
  Future<void> startFile() async {}
  @override
  Future<String?> stopFile() async => null;
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

/// Fake WebSocket: records what the client sends, lets tests push server frames.
class FakeChannel extends Fake implements WebSocketChannel {
  final incoming = StreamController<dynamic>();
  final sent = <dynamic>[];
  bool closed = false;

  @override
  Stream<dynamic> get stream => incoming.stream;

  @override
  late final WebSocketSink sink = _Sink(this);

  @override
  Future<void> get ready async {}
}

class _Sink extends Fake implements WebSocketSink {
  _Sink(this.c);
  final FakeChannel c;
  @override
  void add(dynamic data) => c.sent.add(data);
  @override
  Future<void> close([int? closeCode, String? closeReason]) async => c.closed = true;
}
