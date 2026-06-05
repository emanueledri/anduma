"""Genera le fixture salvate per i test (GTFS zip + payload protobuf + CSV).

Eseguire una volta per (ri)creare i file in ``tests/fixtures/``::

    python -m tests._generate_fixtures

I test NON rigenerano nulla: leggono i file salvati. Così non serve la rete e i
payload protobuf binari restano stabili e versionati.
"""

from __future__ import annotations

import io
import zipfile
from pathlib import Path

from google.transit import gtfs_realtime_pb2

FIX = Path(__file__).parent / "fixtures"

# Timestamp fisso, lontano nel futuro: l'ETA resta positivo anche se il test
# gira "oggi" senza passare un ``now`` esplicito (endpoint test).
FUTURE_TS = 1893456000  # 2030-01-01 00:00:00 UTC

ROUTES = """\
route_id,route_short_name,route_long_name,route_type
R10A,10,Linea 10 - Tram,0
R10B,10,Linea 10 - variante,0
R55,55,Autobus 55,3
"""

STOPS = """\
stop_id,stop_code,stop_name,stop_lat,stop_lon
350,0350,MASSARI CAP.,45.0700,7.6600
351,0351,PORTA NUOVA,45.0600,7.6800
400,0400,LINGOTTO,45.0300,7.6600
"""

TRIPS = """\
trip_id,route_id,trip_headsign,service_id,direction_id
T1,R10A,Corso Settembrini,S1,0
T2,R10B,Piazza Hermada,S1,1
T3,R55,Lingotto,S1,0
"""

# CSV scioperi con nomi colonna "canonici".
STRIKES = """\
data_inizio,data_fine,settore,rilevanza,regione,sindacati,categoria
2026-06-10,2026-06-10,Trasporto pubblico locale,Locale,Piemonte,FILT-CGIL,TPL
2026-07-01,2026-07-01,Trasporti,Nazionale,Tutto il territorio nazionale,USB,Generale
2026-08-01,2026-08-01,Scuola,Locale,Lombardia,FLC,Istruzione
"""

# Variante "ostile": colonne rinominate + delimitatore ';' (test difensivo).
STRIKES_RENAMED = """\
Dal;Al;Comparto;Ambito;Provincia;Organizzazioni Sindacali;Tipologia
2026-06-10;2026-06-10;Trasporto pubblico locale;Locale;Torino;CUB;TPL
2026-09-01;2026-09-01;Sanità;Locale;Veneto;NurSind;Sanità
"""


def _gtfs_zip() -> bytes:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("routes.txt", ROUTES)
        zf.writestr("stops.txt", STOPS)
        zf.writestr("trips.txt", TRIPS)
    return buf.getvalue()


def _vehicle_positions() -> bytes:
    feed = gtfs_realtime_pb2.FeedMessage()
    feed.header.gtfs_realtime_version = "2.0"
    feed.header.timestamp = FUTURE_TS

    # Mezzo linea 10 (route R10A) con posizione completa.
    e1 = feed.entity.add()
    e1.id = "v1"
    v1 = e1.vehicle
    v1.trip.trip_id = "T1"
    v1.trip.route_id = "R10A"
    v1.vehicle.id = "BUS001"
    v1.position.latitude = 45.0701
    v1.position.longitude = 7.6601
    v1.position.bearing = 90.0
    v1.position.speed = 8.5
    v1.timestamp = FUTURE_TS

    # Mezzo linea 55 (route R55).
    e2 = feed.entity.add()
    e2.id = "v2"
    v2 = e2.vehicle
    v2.trip.trip_id = "T3"
    v2.trip.route_id = "R55"
    v2.vehicle.id = "BUS055"
    v2.position.latitude = 45.04
    v2.position.longitude = 7.66

    # Mezzo linea 10 SENZA posizione (degradare con grazia).
    e3 = feed.entity.add()
    e3.id = "v3"
    v3 = e3.vehicle
    v3.trip.trip_id = "T2"
    v3.trip.route_id = "R10B"
    v3.vehicle.id = "BUS002"
    return feed.SerializeToString()


def _trip_updates() -> bytes:
    feed = gtfs_realtime_pb2.FeedMessage()
    feed.header.gtfs_realtime_version = "2.0"
    feed.header.timestamp = FUTURE_TS

    # Linea 10 (T1/R10A): arrivo a 350 (+240s) e a 351 (+600s).
    e1 = feed.entity.add()
    e1.id = "tu1"
    tu1 = e1.trip_update
    tu1.trip.trip_id = "T1"
    tu1.trip.route_id = "R10A"
    s1 = tu1.stop_time_update.add()
    s1.stop_id = "350"
    s1.arrival.time = FUTURE_TS + 240
    s2 = tu1.stop_time_update.add()
    s2.stop_id = "351"
    s2.arrival.time = FUTURE_TS + 600

    # Linea 55 (T3/R55): arrivo a 350 (+120s), solo departure (no arrival).
    e2 = feed.entity.add()
    e2.id = "tu2"
    tu2 = e2.trip_update
    tu2.trip.trip_id = "T3"
    tu2.trip.route_id = "R55"
    s3 = tu2.stop_time_update.add()
    s3.stop_id = "350"
    s3.departure.time = FUTURE_TS + 120

    # stop_time_update senza orario (degradare con grazia).
    e3 = feed.entity.add()
    e3.id = "tu3"
    tu3 = e3.trip_update
    tu3.trip.trip_id = "T2"
    tu3.trip.route_id = "R10B"
    s4 = tu3.stop_time_update.add()
    s4.stop_id = "350"
    return feed.SerializeToString()


def _alerts() -> bytes:
    feed = gtfs_realtime_pb2.FeedMessage()
    feed.header.gtfs_realtime_version = "2.0"

    e1 = feed.entity.add()
    e1.id = "a1"
    al = e1.alert
    al.effect = gtfs_realtime_pb2.Alert.Effect.DETOUR
    ie = al.informed_entity.add()
    ie.route_id = "R10A"
    al.header_text.translation.add(text="Deviazione linea 10", language="it")
    al.description_text.translation.add(text="Lavori in corso in Corso Regina", language="it")

    e2 = feed.entity.add()
    e2.id = "a2"
    al2 = e2.alert
    al2.effect = gtfs_realtime_pb2.Alert.Effect.SIGNIFICANT_DELAYS
    ie2 = al2.informed_entity.add()
    ie2.route_id = "R55"
    al2.header_text.translation.add(text="Ritardi linea 55", language="it")
    return feed.SerializeToString()


def main() -> None:
    FIX.mkdir(parents=True, exist_ok=True)
    (FIX / "gtfs_static.zip").write_bytes(_gtfs_zip())
    (FIX / "vehicle_positions.pb").write_bytes(_vehicle_positions())
    (FIX / "trip_updates.pb").write_bytes(_trip_updates())
    (FIX / "alerts.pb").write_bytes(_alerts())
    (FIX / "scioperi.csv").write_text(STRIKES, encoding="utf-8")
    (FIX / "scioperi_rinominato.csv").write_text(STRIKES_RENAMED, encoding="utf-8")
    print(f"Fixtures scritte in {FIX}")


if __name__ == "__main__":
    main()
