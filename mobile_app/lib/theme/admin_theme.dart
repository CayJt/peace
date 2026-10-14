import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_theme.dart';

/// Surface (background) modes offered in the admin console.
enum AdminSurface { warmPaper, oledCharcoal, pureWhite }

enum AdminLayout { mobile, tablet, desktop }

/// Breakpoints: Desktop >= 1024, Tablet 600-1023, Mobile < 600.
AdminLayout adminLayoutFor(double width) =>
    width >= 1024 ? AdminLayout.desktop : (width >= 600 ? AdminLayout.tablet : AdminLayout.mobile);

/// Admin design tokens. Brand colours, typography and radii come from the Stitch
/// design system "Mushaf Al-Madinah Digital" (project 1135762773500847197);
/// surfaces and status colours are the ones specified for the console. Stitch has
/// no admin screens yet, so no layout tokens beyond these exist to import.
class AdminTokens {
  AdminTokens._();

  // Surfaces
  static const warmPaper = Color(0xFFFAF8F5);
  static const oledCharcoal = Color(0xFF121212);
  static const pureWhite = Color(0xFFFFFFFF);

  // Status accents
  static const success = Color(0xFF10B981);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFEF4444);

  // Brand (Stitch)
  static const emerald = AppColors.emerald;
  static const brass = AppColors.brass;

  // Shape & depth (Stitch roundness ROUND_EIGHT)
  static const radiusCard = 12.0;
  static const radiusControl = AppRadius.base;
  static const sidebarWidth = 264.0;
  static const railWidth = 80.0;
  static const contentMaxWidth = 1200.0;

  static List<BoxShadow> elevation(Brightness b) => [
        BoxShadow(
          color: Colors.black.withValues(alpha: b == Brightness.dark ? 0.5 : 0.07),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ];
}

class AdminTheme {
  AdminTheme._();

  static ThemeData of(AdminSurface s) {
    final dark = s == AdminSurface.oledCharcoal;
    final bg = switch (s) {
      AdminSurface.warmPaper => AdminTokens.warmPaper,
      AdminSurface.oledCharcoal => AdminTokens.oledCharcoal,
      AdminSurface.pureWhite => AdminTokens.pureWhite,
    };
    final base = ThemeData(brightness: dark ? Brightness.dark : Brightness.light, useMaterial3: true);
    final scheme = ColorScheme.fromSeed(
      seedColor: AdminTokens.emerald,
      brightness: base.brightness,
      error: AdminTokens.danger,
    ).copyWith(
      surface: bg,
      primary: dark ? const Color(0xFF9ED1BD) : AdminTokens.emerald,
      secondary: AdminTokens.brass,
      surfaceContainerLowest: dark ? const Color(0xFF0C0C0C) : AdminTokens.pureWhite,
      surfaceContainerLow: dark ? const Color(0xFF181818) : const Color(0xFFF5F3EF),
      surfaceContainer: dark ? const Color(0xFF1E1E1E) : const Color(0xFFF0EEEA),
    );
    final text = AppTheme.useGoogleFonts
        ? GoogleFonts.plusJakartaSansTextTheme(base.textTheme)
        : base.textTheme;
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      textTheme: text.apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface),
      cardTheme: CardThemeData(
        color: dark ? scheme.surfaceContainerLow : (s == AdminSurface.pureWhite ? const Color(0xFFFAFAFA) : AdminTokens.pureWhite),
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AdminTokens.radiusCard),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: dark ? 0.3 : 0.6)),
        ),
      ),
      dividerColor: scheme.outlineVariant.withValues(alpha: 0.5),
      appBarTheme: AppBarTheme(backgroundColor: bg, foregroundColor: scheme.onSurface, elevation: 0, scrolledUnderElevation: 0),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AdminTokens.radiusControl)),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AdminTokens.radiusControl)),
      ),
    );
  }

  static Color statusColor(String status) => switch (status) {
        'open' || 'pending' => AdminTokens.warning,
        'in_progress' => const Color(0xFF3B82F6),
        'resolved' || 'active' => AdminTokens.success,
        'discarded' || 'revoked' || 'inactive' => AdminTokens.danger,
        _ => AdminTokens.brass,
      };
}

/// A thin geometric (arabesque-inspired) band: a row of brass lozenges.
class ArabesqueBorder extends StatelessWidget {
  const ArabesqueBorder({super.key, this.height = 10});
  final double height;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.fromHeight(height), painter: _ArabesquePainter(AdminTokens.brass.withValues(alpha: 0.7)));
}

class _ArabesquePainter extends CustomPainter {
  _ArabesquePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final line = Paint()..color = color.withValues(alpha: 0.5)..strokeWidth = 1;
    canvas.drawLine(Offset(0, h / 2), Offset(size.width, h / 2), line);
    final fill = Paint()..color = color;
    for (double x = h; x < size.width; x += h * 2.4) {
      final p = Path()
        ..moveTo(x, 0)
        ..lineTo(x + h / 2, h / 2)
        ..lineTo(x, h)
        ..lineTo(x - h / 2, h / 2)
        ..close();
      canvas.drawPath(p, fill);
    }
  }

  @override
  bool shouldRepaint(_ArabesquePainter old) => old.color != color;
}
