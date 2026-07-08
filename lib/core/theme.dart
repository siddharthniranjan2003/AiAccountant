import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'palette.dart';

ThemeData buildAppTheme() {
  final colorScheme = ColorScheme.light(
    primary: AppPalette.ink,
    onPrimary: Colors.white,
    secondary: AppPalette.accent,
    onSecondary: Colors.white,
    tertiary: AppPalette.pen,
    onTertiary: Colors.white,
    error: AppPalette.accent,
    onError: Colors.white,
    surface: AppPalette.sheet,
    onSurface: AppPalette.ink,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppPalette.paper,
  );

  final textTheme = base.textTheme.copyWith(
    headlineSmall: const TextStyle(
      color: AppPalette.ink,
      fontSize: 28,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.4,
    ),
    titleLarge: const TextStyle(
      color: AppPalette.ink,
      fontSize: 18,
      fontWeight: FontWeight.w800,
    ),
    titleMedium: const TextStyle(
      color: AppPalette.ink,
      fontSize: 15,
      fontWeight: FontWeight.w700,
    ),
    bodyLarge: const TextStyle(
      color: AppPalette.ink,
      fontSize: 14,
      height: 1.35,
    ),
    bodyMedium: const TextStyle(
      color: AppPalette.ink,
      fontSize: 13,
      height: 1.35,
    ),
    bodySmall: const TextStyle(
      color: AppPalette.inkSoft,
      fontSize: 11.5,
      height: 1.4,
    ),
    labelLarge: const TextStyle(
      color: AppPalette.ink,
      fontSize: 13,
      fontWeight: FontWeight.w700,
    ),
    labelMedium: const TextStyle(
      color: AppPalette.inkSoft,
      fontSize: 11.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.2,
    ),
    labelSmall: TextStyle(
      color: AppPalette.muted,
      fontSize: 10.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.15,
    ),
  );

  return base.copyWith(
    // Flutter caps modal bottom sheets at 640px and centers them on wide
    // screens. Raise that so the voucher/scan/picker sheets spread out on
    // desktop; on phones (narrower than this) they stay full-width as before.
    bottomSheetTheme: const BottomSheetThemeData(
      constraints: BoxConstraints(maxWidth: 1500),
    ),
    // Web gets Manrope (the "accounting app" look); mobile keeps the default
    // until its own redesign. manropeTextTheme keeps every style's size,
    // weight and color and only swaps the font family.
    textTheme: kIsWeb ? GoogleFonts.manropeTextTheme(textTheme) : textTheme,
  );
}
