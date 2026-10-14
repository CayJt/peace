import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/reader_settings_cubit.dart';
import '../../bloc/reading_tracker_bloc.dart';
import '../../bloc/tajweed_assessment_bloc.dart';
import '../../database/quran_database.dart';
import '../../models/quran_models.dart';
import '../../services/mic_source.dart';
import '../../services/quran_sync_manager.dart';
import '../../widgets/floating_pill.dart';
import '../../widgets/uthmani_page_view.dart';

class MushafPageScreen extends StatefulWidget {
  const MushafPageScreen({
    super.key,
    required this.sync,
    required this.db,
    required this.mic,
    required this.onOpenHistory,
    required this.onOpenChat,
    required this.onOpenSettings,
    this.onSessionRecorded,
    this.onSendFeedback,
    this.initialPage = 1,
  });

  final QuranSyncManager sync;
  final QuranDatabase db;
  final MicSource mic;
  final VoidCallback onOpenHistory, onOpenChat, onOpenSettings;
  final void Function(int page, int durationSec, int letters, double score)? onSessionRecorded;
  final Future<String?> Function(String category, String message)? onSendFeedback;
  final int initialPage;

  @override
  State<MushafPageScreen> createState() => _MushafPageScreenState();
}

class _MushafPageScreenState extends State<MushafPageScreen> with WidgetsBindingObserver {
  late final PageController _pages = PageController(initialPage: widget.initialPage - 1);
  final _futures = <int, Future<List<QuranVerse>>>{};
  Timer? _ticker;
  bool _pillVisible = true;
  int _page = 1;
  int _secondsOnPage = 0;
  int _verseIdx = 0;
  StreamSubscription<Uint8List>? _micSub;
  List<QuranVerse> _currentVerses = const [];

  @override
  void initState() {
    super.initState();
    _page = widget.initialPage;
    WidgetsBinding.instance.addObserver(this);
    context.read<ReadingTrackerBloc>().add(PageOpened(_page));
    _startTicker();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      _secondsOnPage++;
      context.read<ReadingTrackerBloc>().add(const ReadingTick());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      _startTicker();
    } else {
      _ticker?.cancel();
      _stopMic();
    }
  }

  Future<List<QuranVerse>> _load(int page) => _futures.putIfAbsent(page, () {
        final f = widget.sync.getPage(page);
        f.then<void>((_) {}, onError: (Object _) { _futures.remove(page); }); // allow retry
        return f;
      });

  Future<void> _flushSession() async {
    final a = context.read<TajweedAssessmentBloc>().state;
    final n = a.scores.length;
    if (_secondsOnPage >= 5 || n > 0) {
      await widget.db.recordReadingSession(_page, _secondsOnPage, n, a.liveAverage ?? 0);
      // Only sessions with scored letters feed the admin leaderboard.
      if (n > 0) widget.onSessionRecorded?.call(_page, _secondsOnPage, n, a.liveAverage ?? 0);
    }
    _secondsOnPage = 0;
  }

  Future<void> _onPageChanged(int index) async {
    await _flushSession();
    _stopMic();
    _verseIdx = 0;
    if (!mounted) return;
    setState(() {
      _page = index + 1;
      _pillVisible = true;
    });
    context.read<ReadingTrackerBloc>().add(PageOpened(_page));
  }

  bool _onScroll(ScrollNotification n) {
    if (n is UserScrollNotification) {
      if (n.direction == ScrollDirection.reverse && _pillVisible) {
        setState(() => _pillVisible = false);
      } else if (n.direction == ScrollDirection.forward && !_pillVisible) {
        setState(() => _pillVisible = true);
      }
    }
    return false;
  }

  Future<void> _toggleMic() async {
    final settings = context.read<ReaderSettingsCubit>();
    if (settings.state.mic) {
      _stopMic();
      return;
    }
    if (_currentVerses.isEmpty) return;
    if (!await widget.mic.requestPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Izin mikrofon diperlukan')));
      }
      return;
    }
    settings.setMic(true);
    await _startVerse();
  }

  Future<void> _startVerse() async {
    if (_verseIdx >= _currentVerses.length) {
      _stopMic();
      return;
    }
    final bloc = context.read<TajweedAssessmentBloc>();
    bloc.add(AssessmentStarted(_currentVerses[_verseIdx]));
    await _micSub?.cancel();
    final stream = await widget.mic.startPcmStream();
    _micSub = stream.listen((c) => bloc.add(AudioChunk(c)));
  }

  void _stopMic() {
    if (!mounted) return;
    _micSub?.cancel();
    _micSub = null;
    widget.mic.stop();
    final settings = context.read<ReaderSettingsCubit>();
    if (settings.state.mic) {
      settings.setMic(false);
      context.read<TajweedAssessmentBloc>().add(const AssessmentStopped());
    }
  }

  Future<void> _feedback() async {
    final send = widget.onSendFeedback!;
    final msg = await showDialog<(String, String)>(context: context, builder: (_) => const _FeedbackDialog());
    if (msg == null || msg.$2.length < 3) return;
    final err = await send(msg.$1, msg.$2);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err ?? 'Terima kasih atas masukan Anda')));
    }
  }

  void _openMenu() {
    showModalBottomSheet<void>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.insights_outlined), title: const Text('Riwayat'), onTap: () { Navigator.pop(c); widget.onOpenHistory(); }),
          ListTile(leading: const Icon(Icons.chat_bubble_outline), title: const Text('Tanya Al-Qur\'an'), onTap: () { Navigator.pop(c); widget.onOpenChat(); }),
          ListTile(leading: const Icon(Icons.settings_outlined), title: const Text('Pengaturan'), onTap: () { Navigator.pop(c); widget.onOpenSettings(); }),
          if (widget.onSendFeedback != null)
            ListTile(leading: const Icon(Icons.feedback_outlined), title: const Text('Kirim saran'), onTap: () { Navigator.pop(c); _feedback(); }),
        ]),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _micSub?.cancel();
    widget.mic.stop();
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: BlocListener<TajweedAssessmentBloc, AssessmentState>(
          listenWhen: (a, b) =>
              (a.listening && !b.listening && b.average != null) ||
              (a.engine != 'energy' && b.engine == 'energy'),
          listener: (context, s) {
            if (s.engine == 'energy' && s.listening) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Pengenalan suara belum aktif di server: penilaian hanya berdasar volume')));
              return;
            }
            // verse finished: move on to the next verse while the mic is on
            if (context.read<ReaderSettingsCubit>().state.mic) {
              _verseIdx++;
              _startVerse();
            }
          },
          child: Stack(children: [
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => setState(() => _pillVisible = !_pillVisible),
              child: BlocBuilder<ReaderSettingsCubit, ReaderSettings>(
                builder: (context, s) => BlocBuilder<TajweedAssessmentBloc, AssessmentState>(
                  builder: (context, a) => Directionality(
                    textDirection: TextDirection.rtl, // page 1 on the right, swipe like a book
                    child: PageView.builder(
                      key: const ValueKey('mushaf-pages'),
                      controller: _pages,
                      itemCount: 604,
                      onPageChanged: _onPageChanged,
                      itemBuilder: (context, i) => FutureBuilder<List<QuranVerse>>(
                        future: _load(i + 1),
                        builder: (context, snap) {
                          if (snap.hasError) {
                            return Center(
                              child: Column(mainAxisSize: MainAxisSize.min, children: [
                                const Text('Gagal memuat halaman'),
                                TextButton(onPressed: () => setState(() {}), child: const Text('Coba lagi')),
                              ]),
                            );
                          }
                          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                          if (i + 1 == _page) _currentVerses = snap.data!;
                          return UthmaniPageView(
                            page: i + 1,
                            verses: snap.data!,
                            tajweedColors: s.tajweedColors,
                            tahfidz: s.tahfidz,
                            showTranslation: s.translation,
                            assessment: i + 1 == _page ? a : null,
                            onScroll: _onScroll,
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 36,
              child: Center(
                child: BlocBuilder<ReaderSettingsCubit, ReaderSettings>(
                  builder: (context, s) => BlocBuilder<TajweedAssessmentBloc, AssessmentState>(
                    builder: (context, a) => FloatingPill(
                      visible: _pillVisible,
                      tajweed: s.tajweedColors,
                      translation: s.translation,
                      tahfidz: s.tahfidz,
                      mic: s.mic,
                      score: a.liveAverage,
                      onTajweed: context.read<ReaderSettingsCubit>().toggleTajweed,
                      onTranslation: context.read<ReaderSettingsCubit>().toggleTranslation,
                      onTahfidz: context.read<ReaderSettingsCubit>().toggleTahfidz,
                      onMic: _toggleMic,
                      onMenu: _openMenu,
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Owns its controller so it is disposed only once the dialog route is gone.
class _FeedbackDialog extends StatefulWidget {
  const _FeedbackDialog();

  @override
  State<_FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<_FeedbackDialog> {
  final _ctrl = TextEditingController();
  String _category = 'suggestion';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Kirim saran'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            initialValue: _category,
            items: const [
              DropdownMenuItem(value: 'suggestion', child: Text('Saran')),
              DropdownMenuItem(value: 'bug', child: Text('Bug')),
              DropdownMenuItem(value: 'content', child: Text('Konten')),
              DropdownMenuItem(value: 'other', child: Text('Lainnya')),
            ],
            onChanged: (v) => setState(() => _category = v ?? _category),
          ),
          TextField(key: const ValueKey('feedback-text'), controller: _ctrl, maxLines: 4, maxLength: 2000, decoration: const InputDecoration(hintText: 'Tulis masukan Anda')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          FilledButton(key: const ValueKey('feedback-send'), onPressed: () => Navigator.pop(context, (_category, _ctrl.text.trim())), child: const Text('Kirim')),
        ],
      );
}
