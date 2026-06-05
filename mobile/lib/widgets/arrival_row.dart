// Riga arrivo: pill linea + capolinea + minuti (il numero domina). Lo stato è
// veicolato da etichetta + colore + icona (dot). ≤1 min → "in arrivo".
import 'package:flutter/material.dart';

import '../api/models.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'line_pill.dart';
import 'pulsing_dot.dart';

class ArrivalRow extends StatelessWidget {
  const ArrivalRow({super.key, required this.arrival});
  final Arrival arrival;

  @override
  Widget build(BuildContext context) {
    final c = TTColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final mins = arrival.etaMinutes;
    final arriving = mins <= 1;
    final st = TTStatus.arriving;
    final labelInk = dark ? const Color(0xFF9CD9B0) : st.ink;
    final chipBg = arriving
        ? (dark ? const Color(0x2E1E8C45) : st.bg)
        : Colors.transparent;
    final minColor = arriving ? (dark ? const Color(0xFF9CD9B0) : st.strong) : c.ink;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: TTSpace.x4, vertical: TTSpace.x4 - 2),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.borderMuted)),
      ),
      child: Row(
        children: [
          LinePill(number: arrival.line ?? '?', mode: arrival.mode, size: PillSize.lg),
          const SizedBox(width: TTSpace.x3 + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  arrival.headsign ?? 'Capolinea',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: arriving
                      ? const EdgeInsets.symmetric(horizontal: 8, vertical: 2)
                      : EdgeInsets.zero,
                  decoration: BoxDecoration(
                    color: chipBg,
                    borderRadius: BorderRadius.circular(TTRadius.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PulsingDot(color: st.base, size: 6, animate: true),
                      const SizedBox(width: 6),
                      Text(
                        arriving ? 'IN ARRIVO' : 'REAL-TIME',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                          color: arriving ? labelInk : c.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: TTSpace.x3),
          SizedBox(
            width: 84,
            child: arriving
                ? Text(
                    'in arrivo',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      height: 0.95,
                      letterSpacing: -1.0,
                      color: minColor,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '$mins',
                        style: TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.w800,
                          height: 0.95,
                          letterSpacing: -1.5,
                          color: minColor,
                          fontFeatures: tabularFigures,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Text('min',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600, color: c.inkSubtle)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Skeleton di riga arrivo (loading).
class ArrivalRowSkeleton extends StatelessWidget {
  const ArrivalRowSkeleton({super.key});
  @override
  Widget build(BuildContext context) {
    final c = TTColors.of(context);
    Widget bar(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(6)),
        );
    return Container(
      padding: const EdgeInsets.all(TTSpace.x4),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.borderMuted)),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 32,
            decoration:
                BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(TTRadius.pill)),
          ),
          const SizedBox(width: TTSpace.x3 + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [bar(160, 14), const SizedBox(height: 8), bar(80, 10)],
            ),
          ),
          bar(56, 36),
        ],
      ),
    );
  }
}
