import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quran_app/services/user_telemetry.dart';

void main() {
  late List<http.Request> sent;
  UserTelemetry make({String? token = 'tok', int status = 201, bool offline = false}) {
    sent = [];
    return UserTelemetry(
      baseUrl: 'http://x',
      appVersion: '1.2.3',
      tokenProvider: () async => token,
      client: MockClient((r) async {
        sent.add(r);
        if (offline) throw http.ClientException('down');
        return http.Response('', r.url.path.endsWith('heartbeat') ? 204 : status);
      }),
    );
  }

  test('heartbeat is authenticated and skipped when signed out', () async {
    expect(await make().heartbeat(), isTrue);
    expect(sent.single.headers['Authorization'], 'Bearer tok');
    expect(await make(token: null).heartbeat(), isFalse);
    expect(sent, isEmpty);
  });

  test('session upload sends the summary and clamps the score', () async {
    final t = make();
    expect(await t.uploadSession(page: 5, durationSec: 40, lettersEvaluated: 12, score: 1.7, khatamCount: 2), isTrue);
    expect(jsonDecode(sent.single.body), {'page': 5, 'duration_sec': 40, 'letters_evaluated': 12, 'score': 1.0, 'khatam_count': 2});
  });

  test('network failures never throw', () async {
    final t = make(offline: true);
    expect(await t.heartbeat(), isFalse);
    expect(await t.uploadSession(page: 1, durationSec: 1, lettersEvaluated: 1, score: .5, khatamCount: 0), isFalse);
    expect(await t.sendFeedback('bug', 'rusak'), 'Tidak dapat terhubung ke server');
  });

  test('feedback works anonymously and reports rate limiting', () async {
    final t = make(token: null);
    expect(await t.sendFeedback('suggestion', 'Tambah fitur'), isNull);
    expect(sent.single.headers.containsKey('Authorization'), isFalse);
    expect(jsonDecode(sent.single.body), {'category': 'suggestion', 'message': 'Tambah fitur', 'app_version': '1.2.3'});
    expect(await make(status: 429).sendFeedback('bug', 'spam spam'), contains('Terlalu banyak'));
  });

  test('start sends an immediate heartbeat and stop halts the timer', () async {
    final t = UserTelemetry(
      baseUrl: 'http://x', tokenProvider: () async => 't', heartbeatEvery: const Duration(milliseconds: 20),
      client: MockClient((r) async {
        (sent = [...sent, r]);
        return http.Response('', 204);
      }),
    );
    sent = [];
    t.start();
    await Future<void>.delayed(const Duration(milliseconds: 90));
    t.stop();
    final n = sent.length;
    expect(n, greaterThanOrEqualTo(3));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(sent.length, n);
  });
}
