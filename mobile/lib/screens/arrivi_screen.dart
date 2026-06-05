// Schermata Arrivi: ricerca fermata + arrivi in tempo reale (auto-refresh 15s).
import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/arrival_row.dart';
import '../widgets/line_pill.dart';
import '../widgets/pulsing_dot.dart';
import '../widgets/state_views.dart';

class ArriviScreen extends StatefulWidget {
  const ArriviScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<ArriviScreen> createState() => _ArriviScreenState();
}

class _ArriviScreenState extends State<ArriviScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  Timer? _refresh;

  List<Stop> _results = const [];
  bool _searching = false;
  Stop? _stop;
  ArrivalsResponse? _arrivals;
  String? _filterLine;
  bool _loadingArrivals = false;
  String? _error;
  DateTime? _updatedAt;

  @override
  void dispose() {
    _debounce?.cancel();
    _refresh?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onQueryChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    if (q.trim().isEmpty) {
      setState(() => _results = const []);
      return;
    }
    setState(() => _searching = true);
    try {
      final res = await widget.api.searchStops(q);
      if (mounted) setState(() => _results = res);
    } catch (_) {
      if (mounted) setState(() => _results = const []);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _selectStop(Stop stop) {
    setState(() {
      _stop = stop;
      _results = const [];
      _filterLine = null;
      _searchCtrl.clear();
      FocusScope.of(context).unfocus();
    });
    _loadArrivals();
    _refresh?.cancel();
    _refresh = Timer.periodic(const Duration(seconds: 15), (_) => _loadArrivals(silent: true));
  }

  Future<void> _loadArrivals({bool silent = false}) async {
    final stop = _stop;
    if (stop == null) return;
    if (!silent) setState(() => _loadingArrivals = true);
    try {
      final res = await widget.api.arrivals(stop.stopId);
      if (mounted) {
        setState(() {
          _arrivals = res;
          _error = null;
          _updatedAt = DateTime.now();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted && !silent) setState(() => _loadingArrivals = false);
    }
  }

  void _clearStop() {
    _refresh?.cancel();
    setState(() {
      _stop = null;
      _arrivals = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = TTColors.of(context);
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(c),
          _searchBar(c),
          Expanded(child: _body(c)),
        ],
      ),
    );
  }

  Widget _title(TTColors c) => Padding(
        padding: const EdgeInsets.fromLTRB(TTSpace.x5, TTSpace.x2, TTSpace.x5, TTSpace.x3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Arrivi',
                style: TextStyle(
                    fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.6, color: c.ink)),
            if (_stop != null && _updatedAt != null) _liveBadge(c),
          ],
        ),
      );

  Widget _liveBadge(TTColors c) {
    final secs = DateTime.now().difference(_updatedAt!).inSeconds;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PulsingDot(color: TTStatus.arriving.base, size: 6),
        const SizedBox(width: 6),
        Text('aggiornato ${secs}s fa',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: c.inkMuted, fontFeatures: tabularFigures)),
      ],
    );
  }

  Widget _searchBar(TTColors c) => Padding(
        padding: const EdgeInsets.fromLTRB(TTSpace.x4, 0, TTSpace.x4, TTSpace.x3),
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(Icons.search, size: 18, color: c.inkMuted),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: _onQueryChanged,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.ink),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: 'Cerca fermata o numero palina',
                    hintStyle: TextStyle(color: c.inkSubtle, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
              if (_searchCtrl.text.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    _searchCtrl.clear();
                    setState(() => _results = const []);
                  },
                  child: Icon(Icons.close, size: 18, color: c.inkMuted),
                ),
            ],
          ),
        ),
      );

  Widget _body(TTColors c) {
    // Risultati di ricerca hanno priorità mentre si digita.
    if (_results.isNotEmpty || _searching) return _searchResults(c);
    if (_stop == null) {
      return const StateView(
        icon: Icons.directions_transit,
        title: 'Cerca una fermata',
        body: 'Digita il nome della fermata o il numero della palina per vedere i prossimi passaggi.',
      );
    }
    return _arrivalsView(c);
  }

  Widget _searchResults(TTColors c) {
    if (_searching && _results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_results.isEmpty) {
      return const StateView(icon: Icons.search_off, title: 'Nessun risultato');
    }
    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (_, i) {
        final s = _results[i];
        return ListTile(
          leading: Icon(Icons.place_outlined, color: c.primary),
          title: Text(s.name, style: TextStyle(fontWeight: FontWeight.w700, color: c.ink)),
          subtitle: s.code != null
              ? Text('Palina ${s.code}', style: TextStyle(color: c.inkMuted))
              : null,
          onTap: () => _selectStop(s),
        );
      },
    );
  }

  Widget _arrivalsView(TTColors c) {
    final stop = _stop!;
    final all = _arrivals?.arrivals ?? const [];
    final lines = <String>{for (final a in all) if (a.line != null) a.line!}.toList()..sort();
    final shown = _filterLine == null ? all : all.where((a) => a.line == _filterLine).toList();

    return RefreshIndicator(
      onRefresh: _loadArrivals,
      child: ListView(
        children: [
          _stopHeader(c, stop),
          if (lines.isNotEmpty) _filterRow(c, lines),
          if (_loadingArrivals && _arrivals == null)
            ...List.generate(5, (_) => const ArrivalRowSkeleton())
          else if (_error != null)
            StateView(
              icon: Icons.cloud_off,
              title: 'Impossibile aggiornare',
              body: 'Controlla la connessione e riprova.',
              actionLabel: 'Riprova',
              onAction: _loadArrivals,
            )
          else if (shown.isEmpty)
            const StateView(
                icon: Icons.schedule, title: 'Nessun passaggio previsto', body: 'Riprova tra poco.')
          else
            ...shown.map((a) => ArrivalRow(arrival: a)),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _stopHeader(TTColors c, Stop stop) => Container(
        margin: const EdgeInsets.fromLTRB(TTSpace.x4, 0, TTSpace.x4, TTSpace.x3),
        padding: const EdgeInsets.all(TTSpace.x4),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(TTRadius.lg),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.place, size: 14, color: c.inkMuted),
                      const SizedBox(width: 6),
                      Text('FERMATA ${stop.code ?? stop.stopId}',
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w600, color: c.inkMuted, letterSpacing: 0.6)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(stop.name,
                      style: TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w800, color: c.ink, letterSpacing: -0.4)),
                ],
              ),
            ),
            IconButton(
              onPressed: _clearStop,
              icon: Icon(Icons.close, color: c.inkMuted),
              tooltip: 'Chiudi',
            ),
          ],
        ),
      );

  Widget _filterRow(TTColors c, List<String> lines) => SizedBox(
        height: 32,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(TTSpace.x4, 0, TTSpace.x4, 0),
          children: [
            _chip(c, label: 'Tutte', active: _filterLine == null, onTap: () => setState(() => _filterLine = null)),
            const SizedBox(width: 8),
            for (final l in lines) ...[
              _lineChip(c, l),
              const SizedBox(width: 8),
            ],
          ],
        ),
      );

  Widget _chip(TTColors c, {required String label, required bool active, required VoidCallback onTap}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? c.primary : c.surface,
            border: active ? null : Border.all(color: c.border),
            borderRadius: BorderRadius.circular(TTRadius.pill),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: active ? (Theme.of(context).brightness == Brightness.dark ? c.pillInk : Colors.white) : c.ink)),
        ),
      );

  Widget _lineChip(TTColors c, String line) {
    final active = _filterLine == line;
    return GestureDetector(
      onTap: () => setState(() => _filterLine = active ? null : line),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? c.primary : c.surface,
          border: active ? null : Border.all(color: c.border),
          borderRadius: BorderRadius.circular(TTRadius.pill),
        ),
        child: LinePill(number: line, mode: modeForLine(line), size: PillSize.sm),
      ),
    );
  }
}
