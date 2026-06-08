// Modelli dati lato client, mappati 1:1 sulle risposte JSON del backend.

/// Modalità del mezzo (per l'icona della pill linea).
enum LineMode { tram, metro, rail, bus, funicular }

LineMode _modeFromString(String? s) => switch (s) {
      'tram' => LineMode.tram,
      'metro' => LineMode.metro,
      'rail' => LineMode.rail,
      'funicular' => LineMode.funicular,
      _ => LineMode.bus,
    };

/// Fallback locale (linee tram storiche di Torino) usato finché il registry
/// non è popolato dal backend (`/lines` espone `mode` da `route_type`).
const _torinoTramLines = {'3', '4', '9', '10', '13', '15', '16'};

/// Registry linea→modalità, popolato una volta da `/lines` all'avvio. Finché è
/// vuoto si ricade sull'euristica delle linee tram note.
class LineModes {
  static final Map<String, LineMode> _byLine = {};

  static void seed(Iterable<TransitLine> lines) {
    for (final l in lines) {
      _byLine[l.line] = l.modeValue;
    }
  }

  static LineMode of(String? line) {
    if (line == null) return LineMode.bus;
    final known = _byLine[line];
    if (known != null) return known;
    return _torinoTramLines.contains(line) ? LineMode.tram : LineMode.bus;
  }
}

LineMode modeForLine(String? line) => LineModes.of(line);

class TransitLine {
  final String line;
  final String? description;
  final List<String> routeIds;
  final String? modeName; // dal backend (route_type); null se non fornito
  const TransitLine({
    required this.line,
    this.description,
    this.routeIds = const [],
    this.modeName,
  });

  factory TransitLine.fromJson(Map<String, dynamic> j) => TransitLine(
        line: j['line'] as String,
        description: j['description'] as String?,
        routeIds: (j['route_ids'] as List?)?.cast<String>() ?? const [],
        modeName: j['mode'] as String?,
      );

  /// Modalità dichiarata dal backend, o euristica se assente.
  LineMode get modeValue =>
      modeName != null ? _modeFromString(modeName) : modeForLine(line);

  LineMode get mode => modeValue;
}

/// Tracciato (percorso) + fermate di una linea, per la sovrimpressione mappa.
class LineShape {
  final String line;
  final List<List<List<double>>> polylines; // [ [ [lat,lon], ... ], ... ]
  final List<Stop> stops;
  const LineShape({required this.line, this.polylines = const [], this.stops = const []});

  factory LineShape.fromJson(Map<String, dynamic> j) => LineShape(
        line: j['line'] as String,
        polylines: ((j['polylines'] as List?) ?? const [])
            .map((poly) => (poly as List)
                .map((pt) => (pt as List).map((n) => (n as num).toDouble()).toList())
                .toList())
            .toList(),
        stops: ((j['stops'] as List?) ?? const [])
            .map((e) => Stop.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class Stop {
  final String stopId;
  final String? code;
  final String name;
  final String? desc; // via + comune (disambigua le omonime)
  final double? lat;
  final double? lon;
  final List<String> lines; // linee che servono la palina
  const Stop({
    required this.stopId,
    this.code,
    required this.name,
    this.desc,
    this.lat,
    this.lon,
    this.lines = const [],
  });

  factory Stop.fromJson(Map<String, dynamic> j) => Stop(
        stopId: j['stop_id'] as String,
        code: j['code'] as String?,
        name: (j['name'] as String?) ?? '',
        desc: j['desc'] as String?,
        lat: (j['lat'] as num?)?.toDouble(),
        lon: (j['lon'] as num?)?.toDouble(),
        lines: (j['lines'] as List?)?.cast<String>() ?? const [],
      );
}

class Arrival {
  final String? line;
  final String? headsign;
  final String? tripId;
  final int etaSeconds;
  final int etaMinutes;
  final int scheduledTs;
  const Arrival({
    this.line,
    this.headsign,
    this.tripId,
    required this.etaSeconds,
    required this.etaMinutes,
    required this.scheduledTs,
  });

  factory Arrival.fromJson(Map<String, dynamic> j) => Arrival(
        line: j['line'] as String?,
        headsign: j['headsign'] as String?,
        tripId: j['trip_id'] as String?,
        etaSeconds: (j['eta_seconds'] as num).toInt(),
        etaMinutes: (j['eta_minutes'] as num).toInt(),
        scheduledTs: (j['scheduled_ts'] as num).toInt(),
      );

  LineMode get mode => modeForLine(line);
}

class ArrivalsResponse {
  final String stopId;
  final String? name;
  final List<Arrival> arrivals;
  const ArrivalsResponse({required this.stopId, this.name, this.arrivals = const []});

  factory ArrivalsResponse.fromJson(Map<String, dynamic> j) => ArrivalsResponse(
        stopId: j['stop_id'] as String,
        name: j['name'] as String?,
        arrivals: ((j['arrivals'] as List?) ?? const [])
            .map((e) => Arrival.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class Vehicle {
  final String? vehicleId;
  final String? tripId;
  final String? headsign;
  final double? lat;
  final double? lon;
  final double? bearing;
  final double? speed;
  final int? ts;
  const Vehicle({
    this.vehicleId,
    this.tripId,
    this.headsign,
    this.lat,
    this.lon,
    this.bearing,
    this.speed,
    this.ts,
  });

  factory Vehicle.fromJson(Map<String, dynamic> j) => Vehicle(
        vehicleId: j['vehicle_id'] as String?,
        tripId: j['trip_id'] as String?,
        headsign: j['headsign'] as String?,
        lat: (j['lat'] as num?)?.toDouble(),
        lon: (j['lon'] as num?)?.toDouble(),
        bearing: (j['bearing'] as num?)?.toDouble(),
        speed: (j['speed'] as num?)?.toDouble(),
        ts: (j['ts'] as num?)?.toInt(),
      );

  bool get hasPosition => lat != null && lon != null;
}

class VehiclesResponse {
  final String line;
  final int count;
  final List<Vehicle> vehicles;
  const VehiclesResponse({required this.line, required this.count, this.vehicles = const []});

  factory VehiclesResponse.fromJson(Map<String, dynamic> j) => VehiclesResponse(
        line: j['line'] as String,
        count: (j['count'] as num?)?.toInt() ?? 0,
        vehicles: ((j['vehicles'] as List?) ?? const [])
            .map((e) => Vehicle.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class ServiceAlert {
  final String? header;
  final String? description;
  final String? effect;
  final List<String> lines;
  const ServiceAlert({this.header, this.description, this.effect, this.lines = const []});

  factory ServiceAlert.fromJson(Map<String, dynamic> j) => ServiceAlert(
        header: j['header'] as String?,
        description: j['description'] as String?,
        effect: j['effect'] as String?,
        lines: (j['lines'] as List?)?.cast<String>() ?? const [],
      );
}

class Strike {
  final String? startDate;
  final String? endDate;
  final String? sector;
  final String? relevance;
  final String? area;
  final String? unions;
  const Strike({this.startDate, this.endDate, this.sector, this.relevance, this.area, this.unions});

  factory Strike.fromJson(Map<String, dynamic> j) => Strike(
        startDate: j['start_date'] as String?,
        endDate: j['end_date'] as String?,
        sector: j['sector'] as String?,
        relevance: j['relevance'] as String?,
        area: j['area'] as String?,
        unions: j['unions'] as String?,
      );
}

/// Sottoscrizione ad alert (lato utente). `kind`: 'imminent' | 'strike'.
class Subscription {
  final int id;
  final String kind;
  final String? stopId;
  final String? line;
  final int? thresholdMin;
  final bool active;
  const Subscription({
    required this.id,
    required this.kind,
    this.stopId,
    this.line,
    this.thresholdMin,
    this.active = true,
  });

  factory Subscription.fromJson(Map<String, dynamic> j) => Subscription(
        id: (j['id'] as num).toInt(),
        kind: j['kind'] as String,
        stopId: j['stop_id'] as String?,
        line: j['line'] as String?,
        thresholdMin: (j['threshold_min'] as num?)?.toInt(),
        active: (j['active'] as bool?) ?? true,
      );
}

class AlertsResponse {
  final List<ServiceAlert> serviceAlerts;
  final List<Strike> strikes;
  const AlertsResponse({this.serviceAlerts = const [], this.strikes = const []});

  factory AlertsResponse.fromJson(Map<String, dynamic> j) => AlertsResponse(
        serviceAlerts: ((j['service_alerts'] as List?) ?? const [])
            .map((e) => ServiceAlert.fromJson(e as Map<String, dynamic>))
            .toList(),
        strikes: ((j['strikes'] as List?) ?? const [])
            .map((e) => Strike.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
