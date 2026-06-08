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
  late Future<AlertsResponse> _future = widget.api.alerts();
  bool _onlyMine = false;

  Future<void> _reload() async {
    final next = widget.api.alerts();
    setState(() { _future = next; });
    await next;
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
          // Niente linee preferite → niente filtro (e si resetta se attivo).
          if (myLines.isEmpty && _onlyMine) _onlyMine = false;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _title(c),
              if (myLines.isNotEmpty) _filterRow(c, myLines.length),
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

  Widget _filterRow(TTColors c, int count) => Padding(
        padding: const EdgeInsets.fromLTRB(TTSpace.x4, 0, TTSpace.x4, TTSpace.x3),
        child: Row(
          children: [
            _chip(c, label: 'Tutti', active: !_onlyMine, onTap: () => setState(() => _onlyMine = false)),
            const SizedBox(width: 8),
            _chip(c,
                label: 'Le mie linee · $count',
                active: _onlyMine,
                onTap: () => setState(() => _onlyMine = true)),
          ],
        ),
      );

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
    return FutureBuilder<AlertsResponse>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return StateView(
            icon: Icons.cloud_off,
            title: 'Impossibile caricare gli avvisi',
            actionLabel: 'Riprova',
            onAction: _reload,
          );
        }
        final data = snap.data!;
        // Gli scioperi sono trasversali al servizio: mostrati sempre.
        final strikes = data.strikes;
        final alerts = _onlyMine
            ? data.serviceAlerts.where((a) => a.lines.any(myLines.contains)).toList()
            : data.serviceAlerts;

        if (strikes.isEmpty && alerts.isEmpty) {
          return StateView(
            icon: _onlyMine ? Icons.filter_alt_off : Icons.check_circle_outline,
            title: _onlyMine ? 'Nessun avviso sulle tue linee' : 'Nessun avviso',
            body: _onlyMine
                ? 'Le tue linee preferite non hanno deviazioni al momento.'
                : 'Nessuna deviazione o sciopero al momento.',
          );
        }
        return RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(TTSpace.x4, 0, TTSpace.x4, TTSpace.x6),
            children: [
              for (final s in strikes) _StrikeCard(s),
              for (final a in alerts) _ServiceAlertCard(a),
            ],
          ),
        );
      },
    );
  }
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
