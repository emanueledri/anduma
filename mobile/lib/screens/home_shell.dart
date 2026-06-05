// Shell di navigazione: bottom navigation a 4 voci + accesso a Informazioni.
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../theme/tokens.dart';
import 'arrivi_screen.dart';
import 'avvisi_screen.dart';
import 'info_screen.dart';
import 'mappa_screen.dart';
import 'preferiti_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _api = ApiClient();
  int _index = 0;

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TTColors.of(context);
    final pages = [
      ArriviScreen(api: _api),
      MappaScreen(api: _api),
      const PreferitiScreen(),
      AvvisiScreen(api: _api),
    ];
    final titles = ['Arrivi', 'Mappa', 'Preferiti', 'Avvisi'];

    return Scaffold(
      appBar: _index == 1
          ? null // la mappa è full-bleed, senza app bar
          : AppBar(
              toolbarHeight: 0, // i titoli sono dentro le schermate
              backgroundColor: c.bg,
              elevation: 0,
              actions: [
                IconButton(
                  tooltip: 'Informazioni',
                  icon: Icon(Icons.info_outline, color: c.inkMuted),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => Scaffold(
                          backgroundColor: c.bg,
                          appBar: AppBar(title: Text(titles.isNotEmpty ? 'Informazioni' : '')),
                          body: const InfoScreen(),
                        )),
                  ),
                ),
              ],
            ),
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: c.surface,
        indicatorColor: c.primarySoft,
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.access_time), selectedIcon: Icon(Icons.access_time_filled), label: 'Arrivi'),
          NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'Mappa'),
          NavigationDestination(
              icon: Icon(Icons.star_border), selectedIcon: Icon(Icons.star), label: 'Preferiti'),
          NavigationDestination(
              icon: Icon(Icons.campaign_outlined), selectedIcon: Icon(Icons.campaign), label: 'Avvisi'),
        ],
      ),
    );
  }
}
