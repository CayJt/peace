import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../bloc/tajweed_assessment_bloc.dart';
import '../models/quran_models.dart';
import '../models/surah_names.dart';
import '../theme/app_theme.dart';

/// Builds the inline spans for a verse. The *text* spans, concatenated, equal
/// `verse.textUthmani` exactly (words joined by one space); the circular ayah
/// marker is a [WidgetSpan] and so contributes no characters.
class VerseSpans {
  VerseSpans({
    required this.tajweedColors,
    required this.tahfidz,
    required this.revealed,
    required this.onToggleWord,
    this.assessment,
    this.baseColor,
  });

  final bool tajweedColors;
  final bool tahfidz;
  final Set<int> revealed; // word ids
  final void Function(int wordId) onToggleWord;
  final AssessmentState? assessment;
  final Color? baseColor;

  static const _space = ' ';

  List<InlineSpan> build(BuildContext context, QuranVerse v, TextStyle style) {
    final spans = <InlineSpan>[];
    for (var i = 0; i < v.words.length; i++) {
      final w = v.words[i];
      spans.add(_word(v, w, style));
      if (i < v.words.length - 1) spans.add(TextSpan(text: _space, style: style));
    }
    if (v.words.isEmpty) spans.add(TextSpan(text: v.textUthmani, style: style));
    spans.add(WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: AyahMarker(number: v.verseNumber, key: ValueKey('marker-${v.verseKey}')),
    ));
    return spans;
  }

  InlineSpan _word(QuranVerse v, Word w, TextStyle style) {
    final masked = tahfidz && !revealed.contains(w.wordId);
    final tap = TapGestureRecognizer()..onTap = () => onToggleWord(w.wordId);
    final wordStyle = masked
        ? style.copyWith(
            foreground: Paint()
              ..color = style.color ?? Colors.black
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7))
        : style;

    final children = <InlineSpan>[];
    final ass = assessment?.verseKey == v.verseKey ? assessment : null;
    if (ass == null && !tajweedColors) {
      return TextSpan(text: w.textUthmani, style: wordStyle, recognizer: tahfidz ? tap : null);
    }
    // Group consecutive letters sharing the same decoration to avoid
    // needless splitting of connected Arabic glyphs.
    String buf = '';
    TextStyle? bufStyle;
    void flush() {
      if (buf.isNotEmpty) children.add(TextSpan(text: buf, style: bufStyle));
      buf = '';
    }

    for (final l in w.letters) {
      var s = wordStyle;
      if (tajweedColors && !masked && l.tajweedRule != TajweedRule.none) {
        s = s.copyWith(color: AppTheme.tajweed[l.tajweedRule.name]);
      }
      if (ass != null) {
        final bg = switch (ass.statusOf(w.wordPosition, l.letterIndex)) {
          LetterStatus.cursor => AppColors.gold.withValues(alpha: 0.35),
          LetterStatus.pass => AppColors.ghunnah.withValues(alpha: 0.25),
          LetterStatus.needRetry => AppColors.madd.withValues(alpha: 0.28),
          LetterStatus.idle => null,
        };
        if (bg != null) s = s.copyWith(backgroundColor: bg);
      }
      if (bufStyle != s) flush();
      bufStyle = s;
      buf += l.char;
    }
    flush();
    return TextSpan(children: children, recognizer: tahfidz ? tap : null, style: wordStyle);
  }
}

class AyahMarker extends StatelessWidget {
  const AyahMarker({super.key, required this.number});
  final int number;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsetsDirectional.symmetric(horizontal: 4),
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.brass, width: 1.4),
        ),
        child: Text(arabicIndic(number),
            style: const TextStyle(fontSize: 13, color: AppColors.brass, height: 1.0)),
      );
}

/// One verse (used by the page view and by integrity widget tests).
class QuranVerseView extends StatefulWidget {
  const QuranVerseView({
    super.key,
    required this.verse,
    this.tajweedColors = true,
    this.tahfidz = false,
    this.showTranslation = false,
    this.assessment,
    this.fontSize = 26,
  });

  final QuranVerse verse;
  final bool tajweedColors;
  final bool tahfidz;
  final bool showTranslation;
  final AssessmentState? assessment;
  final double fontSize;

  @override
  State<QuranVerseView> createState() => _QuranVerseViewState();
}

class _QuranVerseViewState extends State<QuranVerseView> {
  final _revealed = <int>{};

  @override
  void didUpdateWidget(QuranVerseView old) {
    super.didUpdateWidget(old);
    if (old.tahfidz != widget.tahfidz) _revealed.clear();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = AppTheme.arabicVerse(color: scheme.onSurface)
        .copyWith(fontSize: widget.fontSize, height: 2.2);
    final spans = VerseSpans(
      tajweedColors: widget.tajweedColors,
      tahfidz: widget.tahfidz,
      revealed: _revealed,
      assessment: widget.assessment,
      onToggleWord: (id) => setState(() => _revealed.contains(id) ? _revealed.remove(id) : _revealed.add(id)),
    ).build(context, widget.verse, style);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RichText(
            key: ValueKey('verse-text-${widget.verse.verseKey}'),
            textAlign: TextAlign.justify,
            textDirection: TextDirection.rtl,
            text: TextSpan(style: style, children: spans),
          ),
          if (widget.showTranslation && widget.verse.translationText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.md),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  widget.verse.translationText,
                  key: ValueKey('translation-${widget.verse.verseKey}'),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
