// Stati trasversali riutilizzabili: vuoto / errore / offline.
import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class StateView extends StatelessWidget {
  const StateView({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = TTColors.of(context);
    return Center(
      child: Container(
        margin: const EdgeInsets.all(TTSpace.x4),
        padding: const EdgeInsets.symmetric(horizontal: TTSpace.x5, vertical: TTSpace.x8),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(TTRadius.lg),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: c.surface2, shape: BoxShape.circle),
              child: Icon(icon, color: c.primary),
            ),
            const SizedBox(height: TTSpace.x3),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.ink)),
            if (body != null) ...[
              const SizedBox(height: 6),
              Text(body!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: c.inkMuted, height: 1.45)),
            ],
            if (actionLabel != null) ...[
              const SizedBox(height: TTSpace.x4),
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  backgroundColor: c.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TTRadius.md)),
                ),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
