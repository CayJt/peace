import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/mic_source.dart';
import '../../services/quran_chat_service.dart';
import '../../theme/app_theme.dart';

class _Msg {
  final bool user;
  final String text;
  final List<ChatVerse> verses;
  _Msg(this.user, this.text, [this.verses = const []]);
}

class QuranChatScreen extends StatefulWidget {
  const QuranChatScreen({super.key, required this.service, required this.mic});
  final QuranChatService service;
  final MicSource mic;

  @override
  State<QuranChatScreen> createState() => _QuranChatScreenState();
}

class _QuranChatScreenState extends State<QuranChatScreen> {
  final _msgs = <_Msg>[];
  final _ctrl = TextEditingController();
  bool _busy = false, _recording = false;

  Future<void> _ask(Future<ChatAnswer> Function() f, String shown) async {
    setState(() {
      _msgs.add(_Msg(true, shown));
      _busy = true;
    });
    try {
      final a = await f();
      setState(() => _msgs.add(_Msg(false, a.answer, a.verses)));
    } on Exception catch (e) {
      setState(() => _msgs.add(_Msg(false, '${e.toString().replaceFirst('Exception: ', '')}')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _send() {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _busy) return;
    _ctrl.clear();
    _ask(() => widget.service.askText(text), text);
  }

  Future<void> _startVoice() async {
    if (!await widget.mic.requestPermission()) return;
    await widget.mic.startFile();
    setState(() => _recording = true);
  }

  Future<void> _endVoice() async {
    if (!_recording) return;
    setState(() => _recording = false);
    final path = await widget.mic.stopFile();
    if (path == null) return;
    final bytes = await File(path).readAsBytes();
    _ask(() => widget.service.askAudio(bytes), '🎤 Pertanyaan suara');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Tanya Al-Qur\'an')),
      body: Column(children: [
        Expanded(
          child: _msgs.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Text('Tanyakan tentang ayat, makna, tafsir, atau tajwid.',
                        textAlign: TextAlign.center, style: t.textTheme.bodyMedium),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(AppSpacing.margin),
                  itemCount: _msgs.length,
                  itemBuilder: (_, i) {
                    final m = _msgs[i];
                    return Align(
                      alignment: m.user ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.all(AppSpacing.md),
                        constraints: const BoxConstraints(maxWidth: 520),
                        decoration: BoxDecoration(
                          color: m.user ? t.colorScheme.primaryContainer : t.cardColor,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(m.text,
                              style: t.textTheme.bodyMedium?.copyWith(
                                  color: m.user ? t.colorScheme.onPrimaryContainer : null)),
                          for (final v in m.verses) ...[
                            const Divider(),
                            Text(v.verseKey, style: t.textTheme.labelSmall),
                            Directionality(
                                textDirection: TextDirection.rtl,
                                child: Text(v.text, style: AppTheme.arabicVerse(color: t.colorScheme.onSurface))),
                            Text(v.translation, style: t.textTheme.bodyMedium),
                          ],
                        ]),
                      ),
                    );
                  },
                ),
        ),
        if (_busy) const LinearProgressIndicator(),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('chat-input'),
                  controller: _ctrl,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: _recording ? 'Merekam… lepas untuk kirim' : 'Tulis pertanyaan',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.full)),
                  ),
                ),
              ),
              GestureDetector(
                onLongPressStart: (_) => _startVoice(),
                onLongPressEnd: (_) => _endVoice(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(_recording ? Icons.mic : Icons.mic_none,
                      key: const ValueKey('chat-hold-mic'),
                      color: _recording ? t.colorScheme.error : t.colorScheme.onSurfaceVariant, size: 28),
                ),
              ),
              IconButton(key: const ValueKey('chat-send'), onPressed: _send, icon: const Icon(Icons.send)),
            ]),
          ),
        ),
      ]),
    );
  }
}
