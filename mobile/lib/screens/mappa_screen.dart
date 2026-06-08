// Schermata Mappa: mezzi live di una linea su tile OSM, marker direzionali.
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../api/api_client.dart';
import '../api/favorites_store.dart';
import '../api/models.dart';
import '../api/realtime.dart';
import '../theme/tokens.dart';
import '../widgets/line_pill.dart';
import '../widgets/vehicle_marker.dart';

// Centro di Torino.
const _torino = LatLng(45.0703, 7.6869);

class MappaScreen extends StatefulWidget {
  const MappaScreen({super.key, required this.api, required this.favs});
  final ApiClient api;
  final FavoritesStore favs;

  @override
  State<MappaScreen> createState() => _MappaScreenState();
}

class _MappaScreenState extends State<MappaScreen> {
  final _map = MapController();
  String _line = '10';
  VehiclesStream? _stream;
  VehiclesResponse? _data;
  RealtimeStatus _status = RealtimeStatus.connecting;
  String? _selectedVehicleId;
  List<TransitLine> _lines = const [];
  List<List<LatLng>> _routePolys = const [];
  List<LatLng> _routeStops = const [];

  @override
  void initState() {
    super.initState();
    _subscribe();
    _loadLines();
    _loadShape();
  }

  Future<void> _loadShape() async {
    final line = _line;
    try {
      final shape = await widget.api.lineShape(line);
      if (!mounted || line != _line) return;
      setState(() {
        _routePolys = [
          for (final poly in shape.polylines)
            [for (final pt in poly) LatLng(pt[0], pt[1])],
        ];
        _routeStops = [
          for (final s in shape.stops)
            if (s.lat != null && s.lon != null) LatLng(s.lat!, s.lon!),
        ];
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _routePolys = const [];
          _routeStops = const [];
        });
      }
    }
  }

  Future<void> _loadLines() async {
    try {
      final ls = await widget.api.lines();
      if (mounted) setState(() => _lines = ls);
    } catch (_) {/* la selezione linea resta col default */}
  }

  void _subscribe() {
    _stream?.dispose();
    _data = null;
    _status = RealtimeStatus.connecting;
    final s = VehiclesStream(_line);
    _stream = s;
    s.stream.listen((u) {
      if (mounted) {
        setState(() {
          _data = u.data;
          _status = u.status;
        });
      }
    });
    s.start();
  }

  void _changeLine(String line) {
    setState(() {
      _line = line;
      _selectedVehicleId = null;
      _routePolys = const [];
      _routeStops = const [];
    });
    _subscribe();
    _loadShape();
  }

  @override
  void dispose() {
    _stream?.dispose();
    super.dispose();
  }

  List<Vehicle> get _vehicles =>
      (_data?.vehicles ?? const []).where((v) => v.hasPosition).toList();

  @override
  Widget build(BuildContext context) {
    final c = TTColors.of(context);
    final stale = _status != RealtimeStatus.live;
    return Stack(
      children: [
        FlutterMap(
          mapController: _map,
          options: const MapOptions(initialCenter: _torino, initialZoom: 13),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'it.anduma.transito',
              tileBuilder: Theme.of(context).brightness == Brightness.dark
                  ? _darkTileBuilder
                  : null,
            ),
            if (_routePolys.isNotEmpty)
              PolylineLayer(
                polylines: [
                  for (final poly in _routePolys)
                    Polyline(
                      points: poly,
                      strokeWidth: 5,
                      color: c.primary.withValues(alpha: 0.55),
                      borderStrokeWidth: 1,
                      borderColor: c.surface.withValues(alpha: 0.8),
                    ),
                ],
              ),
            if (_routeStops.isNotEmpty)
              MarkerLayer(
                markers: [
                  for (final p in _routeStops)
                    Marker(
                      point: p,
                      width: 12,
                      height: 12,
                      child: Container(
                        decoration: BoxDecoration(
                          color: c.surface,
                          shape: BoxShape.circle,
                          border: Border.all(color: c.primary, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
            MarkerLayer(
              markers: [
                for (final v in _vehicles)
                  Marker(
                    point: LatLng(v.lat!, v.lon!),
                    width: 56,
                    height: 56,
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedVehicleId = v.vehicleId),
                      child: VehicleMarker(
                        number: _line,
                        bearing: v.bearing,
                        selected: v.vehicleId == _selectedVehicleId,
                        stale: stale,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        const _OsmCredit(),
        SafeArea(child: _lineSelector(c)),
        if (stale) SafeArea(child: _statusBadge(c)),
        _fabs(c),
        if (_selectedVehicleId != null) _vehicleCard(c),
      ],
    );
  }

  Widget _lineSelector(TTColors c) => Align(
        alignment: Alignment.topCenter,
        child: Container(
          margin: const EdgeInsets.fromLTRB(TTSpace.x3, TTSpace.x2, TTSpace.x3, 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: c.surface.withValues(alpha: 0.95),
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(TTRadius.lg),
            boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 18, offset: Offset(0, 6))],
          ),
          child: Row(
            children: [
              LinePill(number: _line, mode: modeForLine(_line), size: PillSize.lg),
              const SizedBox(width: TTSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Linea $_line',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: c.ink)),
                    Text('${_vehicles.length} mezzi in servizio',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.inkMuted)),
                  ],
                ),
              ),
              TextButton(
                onPressed: _openLinePicker,
                style: TextButton.styleFrom(foregroundColor: c.primary),
                child: const Text('Cambia', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
              ListenableBuilder(
                listenable: widget.favs,
                builder: (context, _) {
                  final starred = widget.favs.has('line', _line);
                  return IconButton(
                    icon: Icon(
                      starred ? Icons.star : Icons.star_border,
                      size: 22,
                      color: starred ? c.accent : c.inkMuted,
                    ),
                    tooltip: starred ? 'Rimuovi dai preferiti' : 'Salva linea',
                    onPressed: () {
                      if (starred) {
                        widget.favs.remove('line', _line);
                      } else {
                        widget.favs.add(LocalFavorite(type: 'line', ref: _line, name: 'Linea $_line'));
                      }
                    },
                  );
                },
              ),
            ],
          ),
        ),
      );

  Widget _statusBadge(TTColors c) => Align(
        alignment: Alignment.topCenter,
        child: Container(
          margin: const EdgeInsets.only(top: 76),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: c.accent,
            borderRadius: BorderRadius.circular(TTRadius.pill),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.sync_problem, size: 14, color: Colors.white),
              SizedBox(width: 7),
              Text('Aggiornamenti in pausa',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
            ],
          ),
        ),
      );

  Widget _fabs(TTColors c) => Positioned(
        right: 12,
        bottom: 28,
        child: Column(
          children: [
            FloatingActionButton.small(
              heroTag: 'recenter',
              backgroundColor: c.surface,
              foregroundColor: c.primary,
              onPressed: () => _map.move(_torino, 13),
              child: const Icon(Icons.center_focus_strong),
            ),
            const SizedBox(height: 10),
            FloatingActionButton(
              heroTag: 'location',
              backgroundColor: c.surface,
              foregroundColor: c.primary,
              onPressed: () => _map.move(_torino, 15),
              child: const Icon(Icons.my_location),
            ),
          ],
        ),
      );

  Widget _vehicleCard(TTColors c) {
    final v = _vehicles.firstWhere(
      (e) => e.vehicleId == _selectedVehicleId,
      orElse: () => const Vehicle(),
    );
    return Positioned(
      left: 12,
      right: 12,
      bottom: 24,
      child: Container(
        padding: const EdgeInsets.all(TTSpace.x4),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(TTRadius.xl),
          border: Border.all(color: c.border),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 8))],
        ),
        child: Row(
          children: [
            LinePill(number: _line, mode: modeForLine(_line), size: PillSize.xl),
            const SizedBox(width: TTSpace.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('→ ${v.headsign ?? 'In servizio'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: c.ink)),
                  const SizedBox(height: 5),
                  Text(
                    v.speed != null ? '${v.speed!.toStringAsFixed(1)} km/h' : 'velocità n/d',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.inkMuted),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => setState(() => _selectedVehicleId = null),
              icon: Icon(Icons.close, color: c.inkMuted),
            ),
          ],
        ),
      ),
    );
  }

  void _openLinePicker() {
    final c = TTColors.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(TTRadius.x2l))),
      builder: (_) {
        final lines = _lines.isNotEmpty
            ? _lines.map((l) => l.line).toList()
            : const ['4', '9', '10', '13', '15', '51', '55', '58'];
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: TTSpace.x4),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Text('Scegli una linea',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c.ink)),
              ),
              for (final l in lines)
                ListTile(
                  leading: LinePill(number: l, mode: modeForLine(l), size: PillSize.md),
                  title: Text('Linea $l', style: TextStyle(color: c.ink, fontWeight: FontWeight.w600)),
                  trailing: l == _line ? Icon(Icons.check, color: c.accent) : null,
                  onTap: () {
                    Navigator.pop(context);
                    if (l != _line) _changeLine(l);
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

class _OsmCredit extends StatelessWidget {
  const _OsmCredit();
  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 6,
      bottom: 6,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        color: Colors.white.withValues(alpha: 0.7),
        child: const Text('© OpenStreetMap contributors',
            style: TextStyle(fontSize: 9, color: Colors.black54)),
      ),
    );
  }
}

// Schiarisce/inverte leggermente i tile per una resa "notturna" in dark mode.
Widget _darkTileBuilder(BuildContext context, Widget tile, TileImage image) {
  return ColorFiltered(
    colorFilter: const ColorFilter.matrix(<double>[
      -0.7, 0, 0, 0, 255, //
      0, -0.7, 0, 0, 255, //
      0, 0, -0.7, 0, 255, //
      0, 0, 0, 1, 0,
    ]),
    child: tile,
  );
}
