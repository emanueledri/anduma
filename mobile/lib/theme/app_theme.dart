// ThemeData light/dark con Manrope + estensione TTColors (palette "Notte").
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tokens.dart';

class AppTheme {
  static ThemeData light() => _build(Brightness.light, TTColors.light);
  static ThemeData dark() => _build(Brightness.dark, TTColors.dark);

  static ThemeData _build(Brightness brightness, TTColors c) {
    final base = ThemeData(brightness: brightness, useMaterial3: true);
    final textTheme = GoogleFonts.manropeTextTheme(base.textTheme).apply(
      bodyColor: c.ink,
      displayColor: c.ink,
    );
    return base.copyWith(
      scaffoldBackgroundColor: c.bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: TTPalette.primary500,
        brightness: brightness,
        primary: c.primary,
        surface: c.surface,
      ),
      textTheme: textTheme,
      extensions: <ThemeExtension<dynamic>>[c],
      splashFactory: InkSparkle.splashFactory,
    );
  }
}

/// Cifre a larghezza fissa (tabular) per i minuti che cambiano senza "jitter".
const tabularFigures = [FontFeature.tabularFigures()];
