import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens. Source: PRD.md §1 (Paper Warm / OLED Dark).
/// TODO(FASE 2): replace with Google Stitch tokens once the Stitch MCP is connected.
class AppColors {
  AppColors._();

  static const paperWarm = Color(0xFFFAF8F5);
  static const oledDark = Color(0xFF121212);
  static const inkLight = Color(0xFF1C1B19);
  static const inkDark = Color(0xFFEDE9E3);
  static const accent = Color(0xFF2E6B4F);
  static const destructive = Color(0xFFB3261E);
}

class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness b) {
    final isLight = b == Brightness.light;
    final bg = isLight ? AppColors.paperWarm : AppColors.oledDark;
    final ink = isLight ? AppColors.inkLight : AppColors.inkDark;
    final base = ThemeData(brightness: b, useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.accent,
        brightness: b,
        surface: bg,
        error: AppColors.destructive,
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
        bodyColor: ink,
        displayColor: ink,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: ink,
        elevation: 0,
      ),
    );
  }

  /// Arabic Mushaf text style (Uthmanic script).
  static TextStyle mushaf({double size = 26, Color? color}) =>
      GoogleFonts.amiriQuran(fontSize: size, height: 2.0, color: color);
}
