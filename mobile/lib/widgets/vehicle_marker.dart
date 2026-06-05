// Marker mezzo sulla mappa: badge con numero linea + freccia di direzione
// (ruotata secondo il bearing). Selezionato → più grande, colore accento.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

class VehicleMarker extends StatelessWidget {
  const VehicleMarker({
    super.key,
    required this.number,
    this.bearing,
    this.selected = false,
    this.stale = false,
  });

  final String number;
  final double? bearing; // gradi, 0 = nord, senso orario
  final bool selected;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final c = TTColors.of(context);
    final base = selected ? c.accent : c.pillBg;
    final size = selected ? 40.0 : 34.0;
    return Opacity(
      opacity: stale ? 0.6 : 1,
      child: SizedBox(
        width: size + 16,
        height: size + 16,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Freccia di direzione: ruota attorno al badge secondo il bearing.
            if (bearing != null)
              Transform.rotate(
                angle: bearing! * math.pi / 180,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Icon(Icons.navigation, size: 16, color: base),
                ),
              ),
            // Badge centrale col numero.
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: base,
                shape: BoxShape.circle,
                border: Border.all(color: c.surface, width: 2),
                boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2))],
              ),
              alignment: Alignment.center,
              child: Text(
                number,
                style: TextStyle(
                  color: selected ? Colors.white : c.pillInk,
                  fontWeight: FontWeight.w800,
                  fontSize: selected ? 15 : 13,
                  height: 1,
                  fontFeatures: tabularFigures,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
