import 'package:flutter/material.dart';

import '../bloc/tajweed_assessment_bloc.dart';
import '../models/quran_models.dart';
import '../models/surah_names.dart';
import '../theme/app_theme.dart';
import 'quran_verse_view.dart';

/// A single Madinah mushaf page: header (surah right, juz left), the page's
/// verses as one justified flow, and the page number centred in the footer.
class UthmaniPageView extends StatefulWidget {
  const UthmaniPageView({
    super.key,
    required this.page,
    required this.verses,
    this.tajweedColors = true,
    this.tahfidz = false,
    this.showTranslation = false,
    this.assessment,
    this.onScroll,
  });

  final int page;
  final List<QuranVerse> verses;
  final bool tajweedColors;
  final bool tahfidz;
  final bool showTranslation;
  final AssessmentState? assessment;
  final bool Function(ScrollNotification)? onScroll;

  @override
  State<UthmaniPageView> createState() => _UthmaniPageViewState();
}

class _UthmaniPageViewState extends State<UthmaniPageView> {
  final _revealed = <int>{};

  @override
  void didUpdateWidget(UthmaniPageView old) {
    super.didUpdateWidget(old);
    if (old.tahfidz != widget.tahfidz) _revealed.clear();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final first = widget.verses.isEmpty ? null : widget.verses.first;
    final style = AppTheme.arabicVerse(color: t.colorScheme.onSurface).copyWith(height: 2.2);
    final headerStyle = t.textTheme.labelMedium!.copyWith(color: t.colorScheme.onSurfaceVariant);

    final body = <Widget>[];
    final run = <InlineSpan>[];
    void flushRun() {
      if (run.isEmpty) return;
      body.add(RichText(
        key: ValueKey('page-run-${body.length}'),
        textAlign: TextAlign.justify,
        textDirection: TextDirection.rtl,
        text: TextSpan(style: style, children: List.of(run)),
      ));
      run.clear();
    }

    for (final v in widget.verses) {
      if (v.verseNumber == 1) {
        flushRun();
        body.add(SurahBanner(surah: v.surahNumber));
      }
      final spans = VerseSpans(
        tajweedColors: widget.tajweedColors,
        tahfidz: widget.tahfidz,
        revealed: _revealed,
        assessment: widget.assessment,
        onToggleWord: (id) =>
            setState(() => _revealed.contains(id) ? _revealed.remove(id) : _revealed.add(id)),
      ).build(context, v, style);
      run
        ..addAll(spans)
        ..add(TextSpan(text: ' ', style: style));
      if (widget.showTranslation && v.translationText.isNotEmpty) {
        flushRun();
        body.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Text(v.translationText,
                key: ValueKey('translation-${v.verseKey}'), style: t.textTheme.bodyLarge),
          ),
        ));
      }
    }
    flushRun();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.margin, vertical: AppSpacing.sm),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // RTL: first child sits on the right.
                Text(first == null ? '' : surahName(first.surahNumber), style: headerStyle),
                Text(first == null ? '' : 'الجزء ${arabicIndic(first.juz)}', style: headerStyle),
              ],
            ),
          ),
          Divider(height: 1, color: t.dividerColor),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: widget.onScroll ?? (_) => false,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.margin, vertical: AppSpacing.md),
                children: body,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text(arabicIndic(widget.page),
                key: const ValueKey('page-number'), style: headerStyle),
          ),
        ],
      ),
    );
  }
}

class SurahBanner extends StatelessWidget {
  const SurahBanner({super.key, required this.surah});
  final int surah;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(children: [
        Container(
          key: ValueKey('banner-$surah'),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: t.cardColor,
            border: Border.symmetric(horizontal: BorderSide(color: AppColors.brass, width: 1.2)),
          ),
          alignment: Alignment.center,
          child: Text(surahName(surah),
              style: AppTheme.arabicDisplay(color: t.colorScheme.primary).copyWith(fontSize: 24, height: 1.6)),
        ),
        if (showsBasmalahBanner(surah))
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(basmalah,
                key: ValueKey('basmalah-$surah'),
                style: AppTheme.arabicVerse(color: t.colorScheme.onSurface).copyWith(height: 2)),
          ),
      ]),
    );
  }
}
