// Schermata Preferiti — placeholder. Il design dedicato (prompt #3) non è ancora
// stato prodotto; quando arriva si implementa qui con le card preferiti.
import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../widgets/state_views.dart';

class PreferitiScreen extends StatelessWidget {
  const PreferitiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = TTColors.of(context);
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(TTSpace.x5, TTSpace.x2, TTSpace.x5, TTSpace.x3),
            child: Text('Preferiti',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.6, color: c.ink)),
          ),
          const Expanded(
            child: StateView(
              icon: Icons.star_border,
              title: 'Ancora nessun preferito',
              body: 'Salva fermate e linee per vederle qui con i prossimi passaggi.',
            ),
          ),
        ],
      ),
    );
  }
}
