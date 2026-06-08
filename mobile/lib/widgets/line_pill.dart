// Pill linea: icona (tram/bus) + numero, fully rounded. La modalità è
// veicolata dall'icona, mai dal solo colore (accessibilità).
import 'package:flutter/material.dart';

import '../api/models.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

enum PillSize { sm, md, lg, xl }

IconData _iconFor(LineMode mode) => switch (mode) {
      LineMode.tram => Icons.tram,
      LineMode.metro => Icons.subway,
      LineMode.rail => Icons.train,
      LineMode.funicular => Icons.cable,
      LineMode.bus => Icons.directions_bus,
    };

class LinePill extends StatelessWidget {
  const LinePill({
    super.key,
    required this.number,
    this.mode = LineMode.bus,
    this.size = PillSize.md,
    this.color,
    this.ink,
  });

  final String number;
  final LineMode mode;
  final PillSize size;
  final Color? color;
  final Color? ink;

  @override
  Widget build(BuildContext context) {
    final c = TTColors.of(context);
    final spec = switch (size) {
      PillSize.sm => (h: 22.0, px: 8.0, gap: 4.0, font: 13.0, icon: 12.0),
      PillSize.md => (h: 28.0, px: 10.0, gap: 5.0, font: 15.0, icon: 14.0),
      PillSize.lg => (h: 36.0, px: 14.0, gap: 7.0, font: 19.0, icon: 16.0),
      PillSize.xl => (h: 44.0, px: 18.0, gap: 8.0, font: 24.0, icon: 20.0),
    };
    final bg = color ?? c.pillBg;
    final fg = ink ?? c.pillInk;
    return Container(
      height: spec.h,
      padding: EdgeInsets.symmetric(horizontal: spec.px),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(TTRadius.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_iconFor(mode), size: spec.icon, color: fg),
          SizedBox(width: spec.gap),
          Text(
            number,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w800,
              fontSize: spec.font,
              height: 1,
              letterSpacing: -0.2,
              fontFeatures: tabularFigures,
            ),
          ),
        ],
      ),
    );
  }
}
