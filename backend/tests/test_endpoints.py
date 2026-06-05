"""Test degli endpoint via TestClient con provider fake (zero rete)."""

from __future__ import annotations


def test_health(client):
    r = client.get("/health")
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "ok"
    assert body["gtfs_loaded"] is True
    assert body["routes"] == 3 and body["stops"] == 3


def test_lines(client):
    r = client.get("/lines")
    assert r.status_code == 200
    lines = r.json()
    assert [line["line"] for line in lines] == ["10", "55"]


def test_stops_search(client):
    r = client.get("/stops/search", params={"q": "massari"})
    assert r.status_code == 200
    res = r.json()
    assert len(res) == 1 and res[0]["stop_id"] == "350"

    # q obbligatorio.
    assert client.get("/stops/search").status_code == 422


def test_arrivals(client):
    r = client.get("/stops/350/arrivals")
    assert r.status_code == 200
    body = r.json()
    assert body["stop_id"] == "350" and body["name"] == "MASSARI CAP."
    assert [a["line"] for a in body["arrivals"]] == ["55", "10"]

    r10 = client.get("/stops/350/arrivals", params={"line": "10"})
    arr = r10.json()["arrivals"]
    assert len(arr) == 1 and arr[0]["line"] == "10"


def test_arrivals_unknown_stop_404(client):
    assert client.get("/stops/99999/arrivals").status_code == 404


def test_vehicles(client):
    r = client.get("/lines/10/vehicles")
    assert r.status_code == 200
    body = r.json()
    assert body["line"] == "10" and body["count"] == 2
    assert {v["vehicle_id"] for v in body["vehicles"]} == {"BUS001", "BUS002"}


def test_alerts(client):
    r = client.get("/alerts")
    assert r.status_code == 200
    body = r.json()
    assert len(body["service_alerts"]) == 2
    # Scioperi filtrati per Torino: Piemonte + nazionale.
    assert len(body["strikes"]) == 2

    r10 = client.get("/alerts", params={"line": "10"})
    body10 = r10.json()
    assert len(body10["service_alerts"]) == 1
    assert body10["service_alerts"][0]["effect"] == "DETOUR"
