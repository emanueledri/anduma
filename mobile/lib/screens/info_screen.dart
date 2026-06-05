// Schermata Informazioni / Fonti dati — crediti obbligatori (licenze).
import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class InfoScreen extends StatelessWidget {
  const InfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = TTColors.of(context);
    Widget credit(String title, String body) => Container(
          margin: const EdgeInsets.only(bottom: TTSpace.x3),
          padding: const EdgeInsets.all(TTSpace.x4),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(TTRadius.lg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink)),
              const SizedBox(height: 4),
              Text(body, style: TextStyle(fontSize: 13, color: c.inkMuted, height: 1.45)),
            ],
          ),
        );

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(TTSpace.x5),
        children: [
          Text('Informazioni',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.6, color: c.ink)),
          const SizedBox(height: 6),
          Text('Transito Torino · versione 0.1 (MVP)',
              style: TextStyle(fontSize: 13, color: c.inkMuted)),
          const SizedBox(height: TTSpace.x6),
          Text('FONTI DATI',
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: c.inkMuted, letterSpacing: 1.2)),
          const SizedBox(height: TTSpace.x3),
          credit('Trasporto pubblico', 'Città di Torino / GTT — licenza CC BY 4.0'),
          credit('Scioperi', 'MIT — Osservatorio sui Conflitti Sindacali'),
          credit('Mappa', '© OpenStreetMap contributors'),
        ],
      ),
    );
  }
}
