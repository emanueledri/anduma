// Modelli dati lato client, mappati 1:1 sulle risposte JSON del backend.

/// Modalità del mezzo (per l'icona della pill linea). Il backend non la espone
/// ancora; per Torino la inferiamo da un set noto di linee tram.
enum LineMode { tram, bus }

const _torinoTramLines = {'3', '4', '9', '10', '13', '15', '16'};

LineMode modeForLine(String? line) =>
    (line != null && _torinoTramLines.contains(line)) ? LineMode.tram : LineMode.bus;

class TransitLine {
  final String line;
  final String? description;
  final List<String> routeIds;
  const TransitLine({required this.line, this.description, this.routeIds = const []});

  factory TransitLine.fromJson(Map<String, dynamic> j) => TransitLine(
        line: j['line'] as String,
        description: j['description'] as String?,
        routeIds: (j['route_ids'] as List?)?.cast<String>() ?? const [],
      );

  LineMode get mode => modeForLine(line);
}

class Stop {
  final String stopId;
  final String? code;
  final String name;
  final double? lat;
  final double? lon;
  const Stop({required this.stopId, this.code, required this.name, this.lat, this.lon});

  factory Stop.fromJson(Map<String, dynamic> j) => Stop(
        stopId: j['stop_id'] as String,
        code: j['code'] as String?,
        name: (j['name'] as String?) ?? '',
        lat: (j['lat'] as num?)?.toDouble(),
        lon: (j['lon'] as num?)?.toDouble(),
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
