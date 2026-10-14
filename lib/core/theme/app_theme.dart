import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const accent = Color(0xff52c7b8);
  static ThemeData build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final background = dark ? const Color(0xff212327) : const Color(0xffefeef1);
    final controls = dark ? const Color(0xff232627) : const Color(0xfffefefe);
    final text = dark ? const Color(0xffcdccca) : const Color(0xff212327);
    final border = (dark ? Colors.white : Colors.black).withValues(
      alpha: dark ? .08 : .06,
    );
    final scheme =
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: brightness,
        ).copyWith(
          surface: background,
          onSurface: text,
          primary: accent,
          surfaceContainer: controls,
          outline: border,
        );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: text,
      ),
      cardTheme: CardThemeData(
        color: controls,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: border),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          backgroundColor: controls,
          foregroundColor: text,
          side: BorderSide(color: border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: controls,
          foregroundColor: text,
          side: BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: controls,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: accent,
        textColor: scheme.onPrimary,
      ),
      dividerColor: border,
    );
  }
}
