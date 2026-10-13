import 'dart:convert';

import 'package:http/http.dart' as http;

class ChatVerse {
  final String verseKey, text, translation;
  const ChatVerse(this.verseKey, this.text, this.translation);
}

class ChatAnswer {
  final String answer;
  final List<ChatVerse> verses;
  const ChatAnswer(this.answer, this.verses);
}

class QuranChatService {
  QuranChatService({http.Client? client, required this.baseUrl}) : _client = client ?? http.Client();
  final http.Client _client;
  final String baseUrl;
  Uri get _uri => Uri.parse('$baseUrl/api/v1/quran-chat');

  Future<ChatAnswer> askText(String text) async =>
      _parse(await _client.post(_uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode({'text': text})));

  Future<ChatAnswer> askAudio(List<int> wavBytes) async {
    final req = http.MultipartRequest('POST', _uri)
      ..files.add(http.MultipartFile.fromBytes('audio', wavBytes, filename: 'question.wav'));
    return _parse(await http.Response.fromStream(await _client.send(req)));
  }

  ChatAnswer _parse(http.Response r) {
    if (r.statusCode != 200) {
      throw Exception(r.statusCode == 503 ? 'Asisten belum tersedia' : 'Gagal (${r.statusCode})');
    }
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    return ChatAnswer(j['answer'] as String, [
      for (final v in (j['referenced_verses'] as List))
        ChatVerse(v['verse_key'], v['text'], v['translation']),
    ]);
  }
}
