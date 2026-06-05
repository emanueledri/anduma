"""Test del parsing dei tre feed GTFS-RT (da fixture protobuf, zero rete)."""

from __future__ import annotations

import pytest

from app import realtime
from app.gtfs_static import GtfsStatic

# Stesso istante usato nel generatore di fixture.
FUTURE_TS = 1893456000


def test_vehicles_filtered_by_line(gtfs: GtfsStatic, vehicle_positions_bytes: bytes):
    feed = realtime.parse_feed(vehicle_positions_bytes)
    v10 = realtime.vehicles_for_line(feed, gtfs, "10")
    # Due mezzi di linea 10 (T1 con posizione, T2 senza posizione).
    ids = {v.vehicle_id for v in v10}
    assert ids == {"BUS001", "BUS002"}

    v55 = realtime.vehicles_for_line(feed, gtfs, "55")
    assert {v.vehicle_id for v in v55} == {"BUS055"}


def test_vehicle_position_fields_and_graceful_degrade(
    gtfs: GtfsStatic, vehicle_positions_bytes: bytes
):
    feed = realtime.parse_feed(vehicle_positions_bytes)
    by_id = {v.vehicle_id: v for v in realtime.vehicles_for_line(feed, gtfs, "10")}

    full = by_id["BUS001"]
    # I float GTFS-RT sono float32: confronto con tolleranza.
    assert full.lat == pytest.approx(45.0701) and full.lon == pytest.approx(7.6601)
    assert full.bearing == 90.0 and round(full.speed, 1) == 8.5
    assert full.headsign == "Corso Settembrini"
    assert full.ts == FUTURE_TS

    # Mezzo senza posizione: campi a None, nessun crash.
    no_pos = by_id["BUS002"]
    assert no_pos.lat is None and no_pos.lon is None
    assert no_pos.bearing is None and no_pos.speed is None


def test_arrivals_at_stop_all_lines(gtfs: GtfsStatic, trip_updates_bytes: bytes):
    feed = realtime.parse_feed(trip_updates_bytes)
    arrivals = realtime.arrivals_for_stop(feed, gtfs, "350", now=FUTURE_TS)
    # Linea 55 (+120s) prima della 10 (+240s); il trip senza orario è scartato.
    assert [a.line for a in arrivals] == ["55", "10"]
    assert arrivals[0].eta_seconds == 120 and arrivals[0].eta_minutes == 2
    assert arrivals[1].eta_seconds == 240 and arrivals[1].headsign == "Corso Settembrini"


def test_arrivals_filtered_by_line(gtfs: GtfsStatic, trip_updates_bytes: bytes):
    feed = realtime.parse_feed(trip_updates_bytes)
    arrivals = realtime.arrivals_for_stop(feed, gtfs, "350", line="10", now=FUTURE_TS)
    assert len(arrivals) == 1 and arrivals[0].line == "10"


def test_arrivals_drop_past_departures(gtfs: GtfsStatic, trip_updates_bytes: bytes):
    feed = realtime.parse_feed(trip_updates_bytes)
    # 'now' dopo tutti gli arrivi: nessun arrivo futuro.
    assert realtime.arrivals_for_stop(feed, gtfs, "350", now=FUTURE_TS + 10_000) == []


def test_service_alerts(gtfs: GtfsStatic, alerts_bytes: bytes):
    feed = realtime.parse_feed(alerts_bytes)
    all_alerts = realtime.service_alerts(feed, gtfs)
    assert len(all_alerts) == 2

    only10 = realtime.service_alerts(feed, gtfs, line="10")
    assert len(only10) == 1
    a = only10[0]
    assert a.header == "Deviazione linea 10"
    assert a.description == "Lavori in corso in Corso Regina"
    assert a.effect == "DETOUR"
    assert a.lines == ["10"]
