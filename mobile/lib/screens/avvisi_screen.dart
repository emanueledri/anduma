// Schermata Avvisi: avvisi di servizio GTT + scioperi MIT.
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/favorites_store.dart';
import '../api/models.dart';
import '../theme/tokens.dart';
import '../widgets/line_pill.dart';
import '../widgets/state_views.dart';

class AvvisiScreen extends StatefulWidget {
  const AvvisiScreen({super.key, required this.api, required this.favs});
  final ApiClient api;
  final FavoritesStore favs;

  @override
  State<AvvisiScreen> createState() => _AvvisiScreenState();
}

class _AvvisiScreenState extends State<AvvisiScreen> {
  AlertsResponse? _data;
  bool _loading = true;
  bool _failed = false;
  bool _onlyMine = false;
  String? _lineFilter; // linea specifica scelta dall'elenco (precede "Le mie linee")

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _data == null;
      _failed = false;
    });
    try {
      final res = await widget.api.alerts();
      if (mounted) setState(() { _data = res; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _failed = true; _loading = false; });
    }
  }

  /// Linee presenti negli avvisi di servizio correnti (per il picker).
  List<String> get _availableLines {
    final set = <String>{for (final a in _data?.serviceAlerts ?? const []) ...a.lines};
    final list = set.toList()..sort(_compareLines);
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final c = TTColors.of(context);
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: widget.favs,
        builder: (context, _) {
          final myLines = widget.favs.lines.map((f) => f.ref).toSet();
          if (myLines.isEmpty && _onlyMine) _onlyMine = false;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _title(c),
              _filterRow(c, myLines.length),
              Expanded(child: _content(c, myLines)),
            ],
          );
        },
      ),
    );
  }

  Widget _title(TTColors c) => Padding(
        padding: const EdgeInsets.fromLTRB(TTSpace.x5, TTSpace.x2, TTSpace.x5, TTSpace.x3),
        child: Text('Avvisi',
            style: TextStyle(
                fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.6, color: c.ink)),
      );

  Widget _filterRow(TTColors c, int favCount) {
    final byLine = _lineFilter != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(TTSpace.x4, 0, TTSpace.x4, TTSpace.x3),
      child: SizedBox(
        height: 36,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            _chip(c,
                label: 'Tutti',
                active: !_onlyMine && !byLine,
                onTap: () => setState(() { _onlyMine = false; _lineFilter = null; })),
            const SizedBox(width: 8),
            if (favCount > 0) ...[
              _chip(c,
                  label: 'Le mie linee · $favCount',
                  active: _onlyMine && !byLine,
                  onTap: () => setState(() { _onlyMine = true; _lineFilter = null; })),
              const SizedBox(width: 8),
            ],
            _lineChip(c, byLine),
          ],
        ),
      ),
    );
  }

  Widget _lineChip(TTColors c, bool active) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = active ? (dark ? c.pillInk : Colors.white) : c.ink;
    return GestureDetector(
      onTap: _openLinePicker,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? c.primary : c.surface,
          border: active ? null : Border.all(color: c.border),
          borderRadius: BorderRadius.circular(TTRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(active ? Icons.filter_alt : Icons.filter_alt_outlined, size: 16, color: fg),
            const SizedBox(width: 6),
            Text(active ? 'Linea $_lineFilter' : 'Scegli linea',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
            if (active) ...[
              const SizedBox(width: 4),
              Icon(Icons.close, size: 15, color: fg),
            ] else
              Icon(Icons.arrow_drop_down, size: 18, color: fg),
          ],
        ),
      ),
    );
  }

  Future<void> _openLinePicker() async {
    // Se è già attivo un filtro, il tap lo azzera (la X sul chip).
    if (_lineFilter != null) {
      setState(() => _lineFilter = null);
      return;
    }
    final lines = _availableLines;
    final c = TTColors.of(context);
    if (lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nessuna linea con avvisi al momento.')),
      );
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(TTRadius.x2l))),
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: TTSpace.x4),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text('Filtra per linea',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c.ink)),
            ),
            for (final l in lines)
              ListTile(
                leading: LinePill(number: l, mode: modeForLine(l), size: PillSize.md),
                title: Text('Linea $l', style: TextStyle(color: c.ink, fontWeight: FontWeight.w600)),
                onTap: () => Navigator.pop(context, l),
              ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) setState(() { _lineFilter = picked; _onlyMine = false; });
  }

  Widget _chip(TTColors c, {required String label, required bool active, required VoidCallback onTap}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 14),
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
                color: active ? (dark ? c.pillInk : Colors.white) : c.ink)),
      ),
    );
  }

  Widget _content(TTColors c, Set<String> myLines) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_failed) {
      return StateView(
        icon: Icons.cloud_off,
        title: 'Impossibile caricare gli avvisi',
        actionLabel: 'Riprova',
        onAction: _load,
      );
    }
    final data = _data!;
    final byLine = _lineFilter != null;
    // Gli scioperi sono trasversali al servizio: mostrati quando non si filtra per linea.
    final strikes = byLine ? const <Strike>[] : data.strikes;
    final List<ServiceAlert> alerts;
    if (byLine) {
      alerts = data.serviceAlerts.where((a) => a.lines.contains(_lineFilter)).toList();
    } else if (_onlyMine) {
      alerts = data.serviceAlerts.where((a) => a.lines.any(myLines.contains)).toList();
    } else {
      alerts = data.serviceAlerts;
    }

    if (strikes.isEmpty && alerts.isEmpty) {
      final filtered = byLine || _onlyMine;
      return StateView(
        icon: filtered ? Icons.filter_alt_off : Icons.check_circle_outline,
        title: byLine
            ? 'Nessun avviso per la linea $_lineFilter'
            : _onlyMine
                ? 'Nessun avviso sulle tue linee'
                : 'Nessun avviso',
        body: filtered
            ? 'Nessuna deviazione corrispondente al momento.'
            : 'Nessuna deviazione o sciopero al momento.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(TTSpace.x4, 0, TTSpace.x4, TTSpace.x6),
        children: [
          for (final s in strikes) _StrikeCard(s),
          for (final a in alerts) _ServiceAlertCard(a),
        ],
      ),
    );
  }
}

/// Ordina le linee: prima le numeriche per valore, poi le alfanumeriche.
int _compareLines(String a, String b) {
  final na = int.tryParse(a), nb = int.tryParse(b);
  if (na != null && nb != null) return na.compareTo(nb);
  if (na != null) return -1;
  if (nb != null) return 1;
  return a.compareTo(b);
}

class _StrikeCard extends StatelessWidget {
  const _StrikeCard(this.strike);
  final Strike strike;

  @override
  Widget build(BuildContext context) {
    const st = TTStatus.strike;
    final when = [strike.startDate, strike.endDate].where((e) => e != null).join(' → ');
    return Container(
      margin: const EdgeInsets.only(bottom: TTSpace.x3),
      padding: const EdgeInsets.all(TTSpace.x4),
      decoration: BoxDecoration(
        color: st.bg,
        borderRadius: BorderRadius.circular(TTRadius.lg),
        border: Border.all(color: st.base.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: st.base, size: 20),
              const SizedBox(width: 8),
              Text('SCIOPERO',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: st.strong, letterSpacing: 0.6)),
            ],
          ),
          const SizedBox(height: 6),
          Text(strike.sector ?? 'Trasporto pubblico',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: st.ink)),
          const SizedBox(height: 4),
          Text(
            [if (when.isNotEmpty) when, if (strike.area != null) strike.area].join(' · '),
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: st.ink.withValues(alpha: 0.8)),
          ),
        ],
      ),
    );
  }
}

class _ServiceAlertCard extends StatelessWidget {
  const _ServiceAlertCard(this.alert);
  final ServiceAlert alert;

  @override
  Widget build(BuildContext context) {
    final c = TTColors.of(context);
    const st = TTStatus.warning;
    return Container(
      margin: const EdgeInsets.only(bottom: TTSpace.x3),
      padding: const EdgeInsets.all(TTSpace.x4),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(TTRadius.lg),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: st.base, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(alert.header ?? 'Avviso di servizio',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.ink)),
              ),
            ],
          ),
          if (alert.description != null) ...[
            const SizedBox(height: 6),
            Text(alert.description!,
                style: TextStyle(fontSize: 13, color: c.inkMuted, height: 1.4)),
          ],
          if (alert.lines.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final l in alert.lines) LinePill(number: l, mode: modeForLine(l), size: PillSize.sm)],
            ),
          ],
        ],
      ),
    );
  }
}
