// Shell di navigazione: bottom navigation a 4 voci + accesso a Informazioni.
// Orchestratore degli store condivisi (preferiti, sottoscrizioni, push) e del
// deep-link in arrivo dalle notifiche.
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/favorites_store.dart';
import '../api/models.dart';
import '../api/push_manager.dart';
import '../api/subscriptions_store.dart';
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
  final _favs = FavoritesStore();
  late final _subs = SubscriptionsStore(_api);
  late final _push = PushManager(_api);

  // Richiesta di aprire una fermata specifica negli Arrivi (deep-link push).
  final _arriviStopRequest = ValueNotifier<String?>(null);

  int _index = 0;

  @override
  void initState() {
    super.initState();
    _favs.load();
    _seedLineModes();
    _initPush();
  }

  Future<void> _initPush() async {
    await _push.init();
    await _subs.load(); // dopo la registrazione device (X-Device-Id pronto)
    _push.deepLink.addListener(_onDeepLink);
    _push.foreground.addListener(_onForegroundMessage);
    _onDeepLink(); // consuma un eventuale deep-link da app terminata
  }

  /// Carica l'elenco linee una volta per popolare il registry linea→modalità
  /// (icone tram/metro/bus reali da `route_type`). Best-effort.
  Future<void> _seedLineModes() async {
    try {
      final lines = await _api.lines();
      if (!mounted) return;
      LineModes.seed(lines);
      setState(() {});
    } catch (_) {
      // offline o backend giù: pill con euristica, nessun crash
    }
  }

  void _onDeepLink() {
    final link = _push.deepLink.value;
    if (link == null || !mounted) return;
    if (link.kind == 'imminent' && link.stopId != null) {
      _arriviStopRequest.value = link.stopId; // ArriviScreen lo apre
      setState(() => _index = 0);
    } else if (link.kind == 'strike' || link.kind == 'line_alert') {
      setState(() => _index = 3); // Avvisi
    }
    _push.clearDeepLink();
  }

  void _openStopInArrivi(String stopId) {
    _arriviStopRequest.value = stopId;
    setState(() => _index = 0);
  }

  void _onForegroundMessage() {
    final m = _push.foreground.value;
    if (m == null || !mounted) return;
    final n = m.notification;
    final title = n?.title ?? m.data['kind'] ?? 'Avviso';
    final body = n?.body ?? '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(body.isEmpty ? title : '$title — $body'),
        action: m.data.isEmpty
            ? null
            : SnackBarAction(
                label: 'Apri',
                onPressed: () {
                  _push.deepLink.value = AppDeepLink.fromData(m.data);
                },
              ),
      ),
    );
  }

  @override
  void dispose() {
    _push.deepLink.removeListener(_onDeepLink);
    _push.foreground.removeListener(_onForegroundMessage);
    _arriviStopRequest.dispose();
    _push.dispose();
    _api.close();
    _favs.dispose();
    _subs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TTColors.of(context);
    final pages = [
      ArriviScreen(api: _api, favs: _favs, openStop: _arriviStopRequest),
      MappaScreen(api: _api, favs: _favs, onOpenStop: _openStopInArrivi),
      PreferitiScreen(api: _api, favs: _favs, subs: _subs),
      AvvisiScreen(api: _api, favs: _favs),
    ];

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
                          appBar: AppBar(title: const Text('Informazioni')),
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
