import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens mapped from Google Stitch project
/// "Smart Mushaf Al-Qur'an" (projects/1135762773500847197, design system
/// "Mushaf Al-Madinah Digital"). Dark mode follows PRD.md §1 (OLED #121212),
/// using Stitch's inverse/fixed tones since Stitch only defines a light theme.
class AppColors {
  AppColors._();

  // Surfaces (light)
  static const paper = Color(0xFFFBF9F5); // surface / background
  static const pulp = Color(0xFFF5F1E8); // cards, tafsir panels
  static const hairline = Color(0x142D261E); // rgba(45,38,30,0.08)
  static const oled = Color(0xFF121212);

  // Ink
  static const ink = Color(0xFF1F1B16);
  static const inkSecondary = Color(0xFF4A4036);
  static const inkTertiary = Color(0xFF7A6E5F);

  // Accents
  static const emerald = Color(0xFF1B4D3E); // primary-container
  static const emeraldDeep = Color(0xFF003629); // primary
  static const brass = Color(0xFFBFA054); // ayah rosettes, borders
  static const gold = Color(0xFFD4AF37); // active tab / bookmark
  static const error = Color(0xFFBA1A1A);

  // Tajweed notation
  static const ghunnah = Color(0xFF3B7A57);
  static const idgham = Color(0xFF708238);
  static const ikhfa = Color(0xFFC17C3F);
  static const qalqalah = Color(0xFF4A7C9B);
  static const madd = Color(0xFFB84B52);
  static const waqf = Color(0xFF8C827A);
}

/// Stitch spacing scale (rem * 16).
class AppSpacing {
  AppSpacing._();
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 28.0;
  static const xl = 48.0;
  static const margin = 16.0;
  static const gutter = 20.0;
}

/// Stitch roundness: ROUND_EIGHT (DEFAULT 0.5rem).
class AppRadius {
  AppRadius._();
  static const sm = 4.0;
  static const base = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const full = 9999.0;
}

class AppTheme {
  AppTheme._();

  /// Tests (no network / no bundled fonts) set this to false to use plain TextStyles.
  static bool useGoogleFonts = true;

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness b) {
    final isLight = b == Brightness.light;
    final bg = isLight ? AppColors.paper : AppColors.oled;
    final ink = isLight ? AppColors.ink : const Color(0xFFF2F0ED);
    final scheme = isLight
        ? const ColorScheme.light(
            primary: AppColors.emeraldDeep,
            onPrimary: Colors.white,
            primaryContainer: AppColors.emerald,
            onPrimaryContainer: Color(0xFF8ABDA9),
            secondary: Color(0xFF745B15),
            onSecondary: Colors.white,
            secondaryContainer: Color(0xFFFFDC89),
            onSecondaryContainer: Color(0xFF795F19),
            tertiary: Color(0xFF591708),
            tertiaryContainer: Color(0xFF772D1C),
            error: AppColors.error,
            onError: Colors.white,
            surface: AppColors.paper,
            onSurface: AppColors.ink,
            onSurfaceVariant: Color(0xFF404945),
            outline: Color(0xFF707974),
            outlineVariant: Color(0xFFC0C9C3),
            surfaceContainerLowest: Colors.white,
            surfaceContainerLow: Color(0xFFF5F3EF),
            surfaceContainer: Color(0xFFEFEEEA),
            surfaceContainerHigh: Color(0xFFEAE8E4),
            surfaceContainerHighest: Color(0xFFE4E2DE),
          )
        : const ColorScheme.dark(
            primary: Color(0xFF9ED1BD), // inverse-primary
            onPrimary: Color(0xFF002117),
            primaryContainer: AppColors.emerald,
            onPrimaryContainer: Color(0xFFBAEED9),
            secondary: Color(0xFFE4C373), // secondary-fixed-dim
            onSecondary: Color(0xFF251A00),
            tertiary: Color(0xFFFFB4A3), // tertiary-fixed-dim
            error: Color(0xFFFFB4AB),
            onError: Color(0xFF690005),
            surface: AppColors.oled,
            onSurface: Color(0xFFF2F0ED),
            onSurfaceVariant: Color(0xFFC0C9C3),
            outline: Color(0xFF707974),
            outlineVariant: Color(0xFF404945),
            surfaceContainerLowest: Colors.black,
            surfaceContainerLow: Color(0xFF181817),
            surfaceContainer: Color(0xFF1E1E1C),
            surfaceContainerHigh: Color(0xFF282826),
            surfaceContainerHighest: Color(0xFF30312E),
          );

    final base = ThemeData(brightness: b, useMaterial3: true);
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      dividerColor: isLight ? AppColors.hairline : const Color(0x1FFFFFFF),
      cardColor: isLight ? AppColors.pulp : scheme.surfaceContainer,
      textTheme: useGoogleFonts ? _text(base.textTheme, ink) : base.textTheme.apply(bodyColor: ink, displayColor: ink),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: isLight ? AppColors.pulp : scheme.surfaceContainer,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.base),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.base),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.base),
          ),
        ),
      ),
    );
  }

  /// Plus Jakarta Sans scale from the Stitch design system.
  static TextTheme _text(TextTheme t, Color ink) {
    TextStyle s(double size, double lh, FontWeight w, [double ls = 0]) =>
        GoogleFonts.plusJakartaSans(
          fontSize: size,
          height: lh / size,
          fontWeight: w,
          letterSpacing: ls * size,
          color: ink,
        );
    return t.copyWith(
      titleLarge: s(22, 30, FontWeight.w700, -0.01), // surah-title
      titleMedium: s(18, 26, FontWeight.w600), // headline-md
      bodyLarge: s(15, 26, FontWeight.w400), // body-verse-translation
      bodyMedium: s(14, 24, FontWeight.w400), // body-tafsir
      labelMedium: s(12, 16, FontWeight.w500, 0.04), // label-meta
      labelSmall: s(11, 14, FontWeight.w600, 0.08), // label-caption
    );
  }

  /// Arabic verse (Amiri). Stitch: 26px/58px mobile, 32px/72px large.
  static TextStyle arabicVerse({bool large = false, Color? color}) =>
      !useGoogleFonts
          ? TextStyle(fontSize: large ? 32 : 26, height: large ? 72 / 32 : 58 / 26, color: color)
          : GoogleFonts.amiri(
        fontSize: large ? 32 : 26,
        height: large ? 72 / 32 : 58 / 26,
        fontWeight: FontWeight.w400,
        color: color,
      );

  /// Surah banner / display Arabic. Stitch: 30px/64px mobile, 40px/84px large.
  static TextStyle arabicDisplay({bool large = false, Color? color}) =>
      !useGoogleFonts
          ? TextStyle(fontSize: large ? 40 : 30, fontWeight: FontWeight.w700, color: color)
          : GoogleFonts.amiri(
        fontSize: large ? 40 : 30,
        height: large ? 84 / 40 : 64 / 30,
        fontWeight: FontWeight.w700,
        color: color,
      );

  static const tajweed = <String, Color>{
    'ghunnah': AppColors.ghunnah,
    'idgham': AppColors.idgham,
    'ikhfa': AppColors.ikhfa,
    'qalqalah': AppColors.qalqalah,
    'madd': AppColors.madd,
    'waqf': AppColors.waqf,
  };
}
