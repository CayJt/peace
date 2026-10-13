import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Glassmorphic floating capsule with icon-only controls.
class FloatingPill extends StatelessWidget {
  const FloatingPill({
    super.key,
    required this.visible,
    required this.tajweed,
    required this.translation,
    required this.tahfidz,
    required this.mic,
    required this.score,
    required this.onTajweed,
    required this.onTranslation,
    required this.onTahfidz,
    required this.onMic,
    required this.onMenu,
  });

  final bool visible, tajweed, translation, tahfidz, mic;
  final double? score; // 0..1 average for current page, null if none yet
  final VoidCallback onTajweed, onTranslation, onTahfidz, onMic, onMenu;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final glass = t.colorScheme.surface.withValues(alpha: 0.62);
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        offset: visible ? Offset.zero : const Offset(0, 1.5),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 220),
          opacity: visible ? 1 : 0,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.full),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                key: const ValueKey('floating-pill'),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
                decoration: BoxDecoration(
                  color: glass,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  border: Border.all(color: t.dividerColor),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _Btn(const ValueKey('pill-tajweed'), Icons.palette_outlined, 'Warna tajwid', tajweed, onTajweed),
                  _Btn(const ValueKey('pill-translation'), Icons.translate, 'Terjemahan', translation, onTranslation),
                  _Btn(const ValueKey('pill-tahfidz'), Icons.visibility_off_outlined, 'Mode tahfidz', tahfidz, onTahfidz),
                  _Btn(const ValueKey('pill-mic'), mic ? Icons.mic : Icons.mic_none, 'Penilaian suara', mic, onMic),
                  if (mic || score != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Chip(
                        key: const ValueKey('score-chip'),
                        visualDensity: VisualDensity.compact,
                        label: Text(score == null ? '—' : '${(score! * 100).round()}%'),
                      ),
                    ),
                  _Btn(const ValueKey('pill-menu'), Icons.more_horiz, 'Menu', false, onMenu),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  const _Btn(this.k, this.icon, this.tip, this.active, this.onTap);
  final Key k;
  final IconData icon;
  final String tip;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return IconButton(
      key: k,
      tooltip: tip,
      isSelected: active,
      icon: Icon(icon, color: active ? c.primary : c.onSurfaceVariant),
      selectedIcon: Icon(icon, color: c.primary),
      style: IconButton.styleFrom(
        backgroundColor: active ? c.primary.withValues(alpha: 0.14) : null,
      ),
      onPressed: onTap,
    );
  }
}
