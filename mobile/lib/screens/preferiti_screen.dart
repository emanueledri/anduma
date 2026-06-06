// Schermata Preferiti: fermate e linee salvate, arrivi inline auto-refresh.
import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/favorites_store.dart';
import '../api/models.dart';
import '../theme/tokens.dart';
import '../widgets/arrival_row.dart';
import '../widgets/line_pill.dart';
import '../widgets/state_views.dart';

class PreferitiScreen extends StatefulWidget {
  const PreferitiScreen({super.key, required this.api, required this.favs});
  final ApiClient api;
  final FavoritesStore favs;

  @override
  State<PreferitiScreen> createState() => _PreferitiScreenState();
}

class _PreferitiScreenState extends State<PreferitiScreen> {
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _refresh = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TTColors.of(context);
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: widget.favs,
        builder: (context, _) {
          final stops = widget.favs.stops;
          final lines = widget.favs.lines;
          final empty = stops.isEmpty && lines.isEmpty;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _title(c),
              Expanded(
                child: empty
                    ? const StateView(
                        icon: Icons.star_border,
                        title: 'Ancora nessun preferito',
                        body:
                            'Cerca una fermata o apri la mappa e tocca la stella per salvarla qui.',
                      )
                    : RefreshIndicator(
                        onRefresh: () async => setState(() {}),
                        child: ListView(
                          padding:
                              const EdgeInsets.fromLTRB(TTSpace.x4, 0, TTSpace.x4, TTSpace.x8),
                          children: [
                            if (stops.isNotEmpty) ...[
                              _sectionLabel(c, 'FERMATE'),
                              const SizedBox(height: TTSpace.x2),
                              for (final f in stops) _StopCard(fav: f, api: widget.api, favs: widget.favs),
                            ],
                            if (lines.isNotEmpty) ...[
                              SizedBox(height: stops.isNotEmpty ? TTSpace.x5 : 0),
                              _sectionLabel(c, 'LINEE'),
                              const SizedBox(height: TTSpace.x2),
                              for (final f in lines) _LineCard(fav: f, favs: widget.favs),
                            ],
                          ],
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _title(TTColors c) => Padding(
        padding: const EdgeInsets.fromLTRB(TTSpace.x5, TTSpace.x2, TTSpace.x5, TTSpace.x3),
        child: Text(
          'Preferiti',
          style: TextStyle(
              fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.6, color: c.ink),
        ),
      );

  Widget _sectionLabel(TTColors c, String label) => Text(
        label,
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700, color: c.inkMuted, letterSpacing: 1.2),
      );
}

// ---------------------------------------------------------------- card fermata
class _StopCard extends StatefulWidget {
  const _StopCard({required this.fav, required this.api, required this.favs});
  final LocalFavorite fav;
  final ApiClient api;
  final FavoritesStore favs;

  @override
  State<_StopCard> createState() => _StopCardState();
}

class _StopCardState extends State<_StopCard> {
  ArrivalsResponse? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = _data == null);
    try {
      final res = await widget.api.arrivals(widget.fav.ref);
      if (mounted) setState(() { _data = res; _error = null; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TTColors.of(context);
    return Dismissible(
      key: ValueKey('stop_${widget.fav.ref}'),
      direction: DismissDirection.endToStart,
      background: _dismissBg(c),
      onDismissed: (_) => widget.favs.remove(widget.fav.type, widget.fav.ref),
      child: Container(
        margin: const EdgeInsets.only(bottom: TTSpace.x3),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(TTRadius.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(c),
            _body(c),
          ],
        ),
      ),
    );
  }

  Widget _header(TTColors c) => Padding(
        padding: const EdgeInsets.fromLTRB(TTSpace.x4, TTSpace.x3, TTSpace.x2, 0),
        child: Row(
          children: [
            Icon(Icons.place_outlined, size: 14, color: c.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                widget.fav.name,
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: c.ink),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: Icon(Icons.star, size: 20, color: c.accent),
              tooltip: 'Rimuovi dai preferiti',
              onPressed: () => widget.favs.remove(widget.fav.type, widget.fav.ref),
            ),
          ],
        ),
      );

  Widget _body(TTColors c) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: TTSpace.x4),
        child: ArrivalRowSkeleton(),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(TTSpace.x4, TTSpace.x2, TTSpace.x4, TTSpace.x3),
        child: Text('Impossibile aggiornare',
            style: TextStyle(fontSize: 13, color: c.inkMuted)),
      );
    }
    final arrivals = _data?.arrivals.take(3).toList() ?? const [];
    if (arrivals.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(TTSpace.x4, TTSpace.x2, TTSpace.x4, TTSpace.x3),
        child: Text('Nessun passaggio previsto',
            style: TextStyle(fontSize: 13, color: c.inkMuted)),
      );
    }
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(TTRadius.lg)),
      child: Column(children: arrivals.map((a) => ArrivalRow(arrival: a)).toList()),
    );
  }
}

// ----------------------------------------------------------------- card linea
class _LineCard extends StatelessWidget {
  const _LineCard({required this.fav, required this.favs});
  final LocalFavorite fav;
  final FavoritesStore favs;

  @override
  Widget build(BuildContext context) {
    final c = TTColors.of(context);
    return Dismissible(
      key: ValueKey('line_${fav.ref}'),
      direction: DismissDirection.endToStart,
      background: _dismissBg(c),
      onDismissed: (_) => favs.remove(fav.type, fav.ref),
      child: Container(
        margin: const EdgeInsets.only(bottom: TTSpace.x3),
        padding: const EdgeInsets.fromLTRB(TTSpace.x4, TTSpace.x3, TTSpace.x2, TTSpace.x3),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(TTRadius.lg),
        ),
        child: Row(
          children: [
            LinePill(number: fav.ref, mode: modeForLine(fav.ref), size: PillSize.lg),
            const SizedBox(width: TTSpace.x3),
            Expanded(
              child: Text(
                fav.name,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.ink),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: Icon(Icons.star, size: 20, color: c.accent),
              tooltip: 'Rimuovi dai preferiti',
              onPressed: () => favs.remove(fav.type, fav.ref),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _dismissBg(TTColors c) => Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: TTSpace.x4),
      decoration: BoxDecoration(
        color: TTStatus.strike.base,
        borderRadius: BorderRadius.circular(TTRadius.lg),
      ),
      child: const Icon(Icons.delete_outline, color: Colors.white),
    );
