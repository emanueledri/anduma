"""Test del parsing GTFS statico e della mappa linea → route_id."""

from __future__ import annotations

from app.gtfs_static import GtfsStatic


def test_route_short_name_maps_to_multiple_route_ids(gtfs: GtfsStatic):
    # La linea 10 ha due varianti di percorso (R10A, R10B).
    assert sorted(gtfs.route_ids_for_line("10")) == ["R10A", "R10B"]
    assert gtfs.route_ids_for_line("55") == ["R55"]
    assert gtfs.route_ids_for_line("999") == []


def test_short_name_lookups(gtfs: GtfsStatic):
    assert gtfs.short_name_for_route_id("R10A") == "10"
    assert gtfs.short_name_for_trip("T3") == "55"
    assert gtfs.short_name_for_route_id(None) is None


def test_headsign_for_trip(gtfs: GtfsStatic):
    assert gtfs.headsign_for_trip("T1") == "Corso Settembrini"
    assert gtfs.headsign_for_trip("ignoto") is None


def test_lines_listing_sorted_numerically(gtfs: GtfsStatic):
    lines = gtfs.lines()
    names = [line.line for line in lines]
    assert names == ["10", "55"]
    ten = next(line for line in lines if line.line == "10")
    assert ten.description  # long_name presente
    assert sorted(ten.route_ids) == ["R10A", "R10B"]


def test_search_stops_by_name_and_code(gtfs: GtfsStatic):
    by_name = gtfs.search_stops("massari")
    assert len(by_name) == 1 and by_name[0].stop_id == "350"
    assert by_name[0].lat == 45.07

    by_code = gtfs.search_stops("0351")
    assert by_code[0].stop_id == "351"

    assert gtfs.search_stops("") == []
    assert gtfs.search_stops("zzz") == []


def test_search_stops_limit(gtfs: GtfsStatic):
    # Tutte e tre le fermate contengono lettere comuni? usiamo limit.
    res = gtfs.search_stops("a", limit=1)
    assert len(res) == 1


def test_empty_gtfs_is_safe():
    empty = GtfsStatic()
    assert empty.lines() == []
    assert empty.search_stops("x") == []
    assert empty.stop("350") is None
