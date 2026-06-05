import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Pallino che pulsa — usato per segnalare il "real-time / live".
class PulsingDot extends StatefulWidget {
  const PulsingDot({super.key, required this.color, this.size = 6, this.animate = true});
  final Color color;
  final double size;
  final bool animate;

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
    );
    if (!widget.animate) return dot;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        final t = _c.value;
        return Stack(
          alignment: Alignment.center,
          children: [
            Opacity(
              opacity: (1 - t) * 0.5,
              child: Container(
                width: widget.size + widget.size * 2 * t,
                height: widget.size + widget.size * 2 * t,
                decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
              ),
            ),
            child!,
          ],
        );
      },
      child: dot,
    );
  }
}

/// Helpers per i colori semantici (con adattamento dark mode).
TTStatusColor statusColors(String key) => switch (key) {
      'arriving' => TTStatus.arriving,
      'delayed' => TTStatus.delayed,
      'warning' => TTStatus.warning,
      'strike' => TTStatus.strike,
      _ => TTStatus.scheduled,
    };
