// Schermata Informazioni / Fonti dati — crediti obbligatori (licenze).
import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class InfoScreen extends StatelessWidget {
  const InfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = TTColors.of(context);

    Widget sectionLabel(String s) => Padding(
          padding: const EdgeInsets.only(bottom: TTSpace.x3),
          child: Text(s,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: c.inkMuted, letterSpacing: 1.2)),
        );

    Widget credit(IconData icon, String title, String body) => Container(
          margin: const EdgeInsets.only(bottom: TTSpace.x3),
          padding: const EdgeInsets.all(TTSpace.x4),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(TTRadius.lg),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: c.primary),
              const SizedBox(width: TTSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink)),
                    const SizedBox(height: 4),
                    Text(body, style: TextStyle(fontSize: 13, color: c.inkMuted, height: 1.45)),
                  ],
                ),
              ),
            ],
          ),
        );

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(TTSpace.x5),
        children: [
          _appHeader(c),
          const SizedBox(height: TTSpace.x6),
          sectionLabel('FONTI DATI'),
          credit(Icons.directions_transit, 'Trasporto pubblico',
              'Città di Torino / GTT — licenza CC BY 4.0'),
          credit(Icons.warning_amber_rounded, 'Scioperi',
              'MIT — Osservatorio sui Conflitti Sindacali'),
          credit(Icons.map_outlined, 'Mappa', '© OpenStreetMap contributors'),
          const SizedBox(height: TTSpace.x5),
          _footer(c),
        ],
      ),
    );
  }

  Widget _appHeader(TTColors c) => Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: c.primary,
              borderRadius: BorderRadius.circular(TTRadius.lg),
            ),
            child: Icon(Icons.directions_transit, color: c.accent, size: 28),
          ),
          const SizedBox(width: TTSpace.x4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Transito Torino',
                    style: TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: c.ink)),
                const SizedBox(height: 2),
                Text('Arrivi, mezzi live e avvisi GTT · v0.1 (MVP)',
                    style: TextStyle(fontSize: 13, color: c.inkMuted)),
              ],
            ),
          ),
        ],
      );

  Widget _footer(TTColors c) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.auto_awesome, size: 14, color: c.inkSubtle),
          const SizedBox(width: 6),
          Text('Sviluppato con Claude Code',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.inkSubtle)),
        ],
      );
}
