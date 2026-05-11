import 'package:flutter/material.dart';
import 'palette.dart';

ThemeData buildAppTheme() {
  const colorScheme = ColorScheme.light(
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

  return base.copyWith(
    textTheme: base.textTheme.copyWith(
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
      labelSmall: const TextStyle(
        color: AppPalette.muted,
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.15,
      ),
    ),
  );
}
