// Design tokens — Transito Torino (palette "Notte", da Claude design).
// Colori, scala semantica e atomi condivisi. Vedi docs/DESIGN_PROMPTS.md.
import 'package:flutter/material.dart';

/// Palette primaria "Notte" (blu profondo) + accento ambra + neutrali caldi.
class TTPalette {
  // Primario "Notte"
  static const primary50 = Color(0xFFEEF1F8);
  static const primary100 = Color(0xFFD9DFEC);
  static const primary300 = Color(0xFF8593B8);
  static const primary400 = Color(0xFF566792);
  static const primary500 = Color(0xFF2C3E66);
  static const primary700 = Color(0xFF1C2843);
  static const primary800 = Color(0xFF141C30);
  static const primary900 = Color(0xFF0B1220);

  // Accento ambra (CTA + "in arrivo ora")
  static const accent50 = Color(0xFFFEF4E6);
  static const accent300 = Color(0xFFF4B860);
  static const accent500 = Color(0xFFE8920E);
  static const accent600 = Color(0xFFC7780A);
  static const accent700 = Color(0xFF9A5A05);

  // Neutrali caldi (tema chiaro)
  static const neutral0 = Color(0xFFFFFFFF);
  static const neutral25 = Color(0xFFFBFAF8);
  static const neutral50 = Color(0xFFF6F5F2);
  static const neutral100 = Color(0xFFEDEBE6);
  static const neutral200 = Color(0xFFDCD8D0);
  static const neutral400 = Color(0xFF8F8A80);
  static const neutral500 = Color(0xFF65615A);
  static const neutral700 = Color(0xFF312F2B);
  static const neutral800 = Color(0xFF1F1E1B);

  // Dark neutrals (warm)
  static const darkBg = Color(0xFF13151A);
  static const darkSurface = Color(0xFF1B1E25);
  static const darkSurface2 = Color(0xFF252932);
  static const darkBorder = Color(0xFF2C3140);
  static const darkInk = Color(0xFFF2F0EA);
  static const darkInkMuted = Color(0xFFA8A59C);
  static const darkInkSubtle = Color(0xFF6E6B62);
}

/// Uno stato semantico = colore di sfondo + accento + inchiostro.
class TTStatusColor {
  final Color bg; // sfondo tenue (chiaro)
  final Color base; // dot / accento
  final Color strong; // testo minuti
  final Color ink; // testo etichetta
  const TTStatusColor(this.bg, this.base, this.strong, this.ink);
}

class TTStatus {
  static const arriving =
      TTStatusColor(Color(0xFFE7F6EC), Color(0xFF1E8C45), Color(0xFF176D36), Color(0xFF0B3E1F));
  static const delayed =
      TTStatusColor(Color(0xFFFDECE5), Color(0xFFC44712), Color(0xFF9C380E), Color(0xFF491808));
  static const warning =
      TTStatusColor(Color(0xFFFEF4E0), Color(0xFFB57A06), Color(0xFF8C5E05), Color(0xFF3F2A02));
  static const strike =
      TTStatusColor(Color(0xFFFBE7E7), Color(0xFFB3261E), Color(0xFF8B1D17), Color(0xFF3F0A07));
  static const scheduled =
      TTStatusColor(Color(0xFFEEF1F8), Color(0xFF566792), Color(0xFF3D4E78), Color(0xFF1F2A48));
}

/// Spaziature (griglia 4pt) e raggi, come costanti comode.
class TTSpace {
  static const x1 = 4.0, x2 = 8.0, x3 = 12.0, x4 = 16.0, x5 = 20.0, x6 = 24.0, x8 = 32.0;
}

class TTRadius {
  static const sm = 8.0, md = 12.0, lg = 16.0, xl = 20.0, x2l = 28.0, pill = 999.0;
}

/// Colori dipendenti dal tema (surface/ink/pill/accent), come da ARR_THEMES.
/// Esposti via [ThemeExtension] così i widget li leggono da `Theme.of(context)`.
@immutable
class TTColors extends ThemeExtension<TTColors> {
  final Color bg;
  final Color surface;
  final Color surface2;
  final Color border;
  final Color borderMuted;
  final Color ink;
  final Color inkMuted;
  final Color inkSubtle;
  final Color pillBg;
  final Color pillInk;
  final Color primary;
  final Color primarySoft;
  final Color accent;

  const TTColors({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.border,
    required this.borderMuted,
    required this.ink,
    required this.inkMuted,
    required this.inkSubtle,
    required this.pillBg,
    required this.pillInk,
    required this.primary,
    required this.primarySoft,
    required this.accent,
  });

  static const light = TTColors(
    bg: TTPalette.neutral25,
    surface: TTPalette.neutral0,
    surface2: TTPalette.neutral50,
    border: TTPalette.neutral100,
    borderMuted: Color(0xFFF1EFEA),
    ink: TTPalette.neutral800,
    inkMuted: TTPalette.neutral500,
    inkSubtle: TTPalette.neutral400,
    pillBg: TTPalette.primary800,
    pillInk: TTPalette.neutral0,
    primary: TTPalette.primary800,
    primarySoft: TTPalette.primary50,
    accent: TTPalette.accent500,
  );

  static const dark = TTColors(
    bg: TTPalette.darkBg,
    surface: TTPalette.darkSurface,
    surface2: TTPalette.darkSurface2,
    border: TTPalette.darkBorder,
    borderMuted: TTPalette.darkSurface2,
    ink: TTPalette.darkInk,
    inkMuted: TTPalette.darkInkMuted,
    inkSubtle: TTPalette.darkInkSubtle,
    pillBg: TTPalette.primary300, // schiarito per contrasto su dark
    pillInk: TTPalette.primary900,
    primary: TTPalette.primary300,
    primarySoft: Color(0xFF1F2A48),
    accent: TTPalette.accent300,
  );

  /// Helper: lo `TTColors` corrente dal context.
  static TTColors of(BuildContext context) =>
      Theme.of(context).extension<TTColors>() ?? light;

  @override
  TTColors copyWith() => this;

  @override
  TTColors lerp(ThemeExtension<TTColors>? other, double t) {
    if (other is! TTColors) return this;
    return t < 0.5 ? this : other;
  }
}
