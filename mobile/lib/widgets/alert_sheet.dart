// Bottom sheet per creare/rimuovere alert "linea in arrivo" su una fermata.
// Le linee candidate sono quelle attualmente in transito alla fermata.
import 'package:flutter/material.dart';

import '../api/models.dart';
import '../api/subscriptions_store.dart';
import '../theme/tokens.dart';
import 'line_pill.dart';

Future<void> showStopAlertSheet(
  BuildContext context, {
  required String stopId,
  required String stopName,
  required List<String> lines,
  required SubscriptionsStore subs,
}) {
  final c = TTColors.of(context);
  return showModalBottomSheet(
    context: context,
    backgroundColor: c.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(TTRadius.x2l)),
    ),
    builder: (_) => _StopAlertSheet(
      stopId: stopId,
      stopName: stopName,
      lines: lines,
      subs: subs,
    ),
  );
}

/// Sheet per gli alert di una **linea** preferita: sciopero + avvisi/deviazioni.
Future<void> showLineAlertSheet(
  BuildContext context, {
  required String line,
  required SubscriptionsStore subs,
}) {
  final c = TTColors.of(context);
  return showModalBottomSheet(
    context: context,
    backgroundColor: c.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(TTRadius.x2l)),
    ),
    builder: (_) => _LineAlertSheet(line: line, subs: subs),
  );
}

class _LineAlertSheet extends StatelessWidget {
  const _LineAlertSheet({required this.line, required this.subs});
  final String line;
  final SubscriptionsStore subs;

  Future<void> _set(BuildContext context, Future<bool> Function() op) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!await op()) {
      messenger.showSnackBar(SnackBar(
        content: Text(subs.ready
            ? 'Operazione non riuscita. Riprova.'
            : 'Notifiche non ancora attive su questo dispositivo.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TTColors.of(context);
    return SafeArea(
      child: ListenableBuilder(
        listenable: subs,
        builder: (context, _) {
          final strikeOn = subs.strikeForLine(line) != null;
          final alertOn = subs.lineAlertForLine(line) != null;
          return Padding(
            padding: const EdgeInsets.fromLTRB(TTSpace.x5, TTSpace.x4, TTSpace.x5, TTSpace.x5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                        color: c.border, borderRadius: BorderRadius.circular(TTRadius.pill)),
                  ),
                ),
                const SizedBox(height: TTSpace.x4),
                Row(
                  children: [
                    LinePill(number: line, mode: modeForLine(line), size: PillSize.lg),
                    const SizedBox(width: TTSpace.x3),
                    Text('Avvisami per la linea',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: c.ink)),
                  ],
                ),
                if (!subs.ready) ...[
                  const SizedBox(height: TTSpace.x4),
                  Container(
                    padding: const EdgeInsets.all(TTSpace.x4),
                    decoration: BoxDecoration(
                      color: c.surface2,
                      borderRadius: BorderRadius.circular(TTRadius.md),
                      border: Border.all(color: c.border),
                    ),
                    child: Text('Le notifiche non sono ancora attive su questo dispositivo.',
                        style: TextStyle(fontSize: 13, color: c.inkMuted, height: 1.4)),
                  ),
                ],
                const SizedBox(height: TTSpace.x3),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: alertOn,
                  onChanged: (v) => _set(context, () => subs.toggleLineAlert(line, on: v)),
                  title: Text('Avvisi e deviazioni',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink)),
                  subtitle: Text('Modifiche al servizio sulla linea',
                      style: TextStyle(fontSize: 12, color: c.inkMuted)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: strikeOn,
                  onChanged: (v) => _set(context, () => subs.toggleStrike(line, on: v)),
                  title: Text('Scioperi',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink)),
                  subtitle: Text('Scioperi del trasporto pubblico',
                      style: TextStyle(fontSize: 12, color: c.inkMuted)),
                ),
                const SizedBox(height: TTSpace.x2),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StopAlertSheet extends StatefulWidget {
  const _StopAlertSheet({
    required this.stopId,
    required this.stopName,
    required this.lines,
    required this.subs,
  });
  final String stopId;
  final String stopName;
  final List<String> lines;
  final SubscriptionsStore subs;

  @override
  State<_StopAlertSheet> createState() => _StopAlertSheetState();
}

class _StopAlertSheetState extends State<_StopAlertSheet> {
  int _threshold = 5;
  static const _thresholds = [5, 10, 20];

  @override
  Widget build(BuildContext context) {
    final c = TTColors.of(context);
    return SafeArea(
      child: ListenableBuilder(
        listenable: widget.subs,
        builder: (context, _) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(TTSpace.x5, TTSpace.x4, TTSpace.x5, TTSpace.x5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: c.border,
                      borderRadius: BorderRadius.circular(TTRadius.pill),
                    ),
                  ),
                ),
                const SizedBox(height: TTSpace.x4),
                Text('Avvisami quando arriva',
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: c.ink)),
                const SizedBox(height: 2),
                Text(widget.stopName,
                    style: TextStyle(fontSize: 13, color: c.inkMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if (!widget.subs.ready) ...[
                  const SizedBox(height: TTSpace.x4),
                  _notice(c, 'Le notifiche non sono ancora attive su questo dispositivo.'),
                ] else ...[
                  const SizedBox(height: TTSpace.x5),
                  Text('CON QUANTO ANTICIPO',
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700, color: c.inkMuted, letterSpacing: 1.0)),
                  const SizedBox(height: TTSpace.x2),
                  Row(
                    children: [
                      for (final t in _thresholds) ...[
                        _thresholdChip(c, t),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                  const SizedBox(height: TTSpace.x5),
                  Text('LINEE',
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700, color: c.inkMuted, letterSpacing: 1.0)),
                  const SizedBox(height: TTSpace.x2),
                  if (widget.lines.isEmpty)
                    _notice(c, 'Nessuna linea in transito al momento. Riprova quando vedi gli arrivi.')
                  else
                    ...widget.lines.map((l) => _lineRow(c, l)),
                ],
                const SizedBox(height: TTSpace.x4),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _notice(TTColors c, String text) => Container(
        padding: const EdgeInsets.all(TTSpace.x4),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(TTRadius.md),
          border: Border.all(color: c.border),
        ),
        child: Text(text, style: TextStyle(fontSize: 13, color: c.inkMuted, height: 1.4)),
      );

  Widget _thresholdChip(TTColors c, int t) {
    final active = _threshold == t;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => setState(() => _threshold = t),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? c.primary : c.surface,
          border: active ? null : Border.all(color: c.border),
          borderRadius: BorderRadius.circular(TTRadius.pill),
        ),
        child: Text('$t min',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: active ? (dark ? c.pillInk : Colors.white) : c.ink)),
      ),
    );
  }

  Widget _lineRow(TTColors c, String line) {
    final active = widget.subs.hasImminent(widget.stopId, line);
    return Padding(
      padding: const EdgeInsets.only(bottom: TTSpace.x2),
      child: Row(
        children: [
          LinePill(number: line, mode: modeForLine(line), size: PillSize.md),
          const Spacer(),
          Switch(
            value: active,
            onChanged: (on) => _toggle(line, on),
          ),
        ],
      ),
    );
  }

  Future<void> _toggle(String line, bool on) async {
    final messenger = ScaffoldMessenger.of(context);
    bool ok;
    if (on) {
      ok = await widget.subs.addImminent(widget.stopId, line, _threshold);
    } else {
      final existing = widget.subs
          .imminentForStop(widget.stopId)
          .where((s) => s.line == line)
          .toList();
      ok = existing.isEmpty || await widget.subs.remove(existing.first.id);
    }
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Operazione non riuscita. Riprova.')),
      );
    }
  }
}
