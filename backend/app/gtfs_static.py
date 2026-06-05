"""GTFS statico: parsing dello ZIP e mappatura ``route_short_name → route_id``.

I feed RT identificano le corse con ``route_id``/``trip_id`` interni, non con
l'etichetta "10". Per filtrare una linea serve la mappa, costruita da
``routes.txt``. Servono inoltre ``stops.txt`` (ricerca fermate) e ``trips.txt``
(``trip_id`` → headsign/route).

Il parsing (``GtfsStatic.from_zip_bytes``) è puro e testabile da fixture; il
download di rete sta in ``download_zip_bytes`` ed è isolato.
"""

from __future__ import annotations

import csv
import io
import zipfile
from dataclasses import dataclass, field

import httpx

from .config import Settings, get_settings
from .models import Line, Stop


def _read_csv(zf: zipfile.ZipFile, name: str) -> list[dict[str, str]]:
    """Legge un file CSV dello ZIP GTFS; ritorna [] se assente."""
    if name not in zf.namelist():
        return []
    with zf.open(name) as fh:
        # GTFS è UTF-8 (a volte con BOM): utf-8-sig pulisce il BOM.
        text = io.TextIOWrapper(fh, encoding="utf-8-sig", newline="")
        return list(csv.DictReader(text))


@dataclass
class GtfsStatic:
    """Snapshot in memoria dei dati GTFS statici utili al backend."""

    # route_id -> {short_name, long_name, ...}
    routes: dict[str, dict[str, str]] = field(default_factory=dict)
    # route_short_name -> [route_id, ...]
    short_name_to_route_ids: dict[str, list[str]] = field(default_factory=dict)
    # stop_id -> {name, code, lat, lon}
    stops: dict[str, dict[str, str]] = field(default_factory=dict)
    # trip_id -> {route_id, headsign}
    trips: dict[str, dict[str, str]] = field(default_factory=dict)

    # ------------------------------------------------------------------ build
    @classmethod
    def from_zip_bytes(cls, data: bytes) -> GtfsStatic:
        """Costruisce lo snapshot da un GTFS ZIP (bytes)."""
        gtfs = cls()
        with zipfile.ZipFile(io.BytesIO(data)) as zf:
            for row in _read_csv(zf, "routes.txt"):
                route_id = row.get("route_id", "").strip()
                if not route_id:
                    continue
                short = row.get("route_short_name", "").strip()
                gtfs.routes[route_id] = row
                if short:
                    gtfs.short_name_to_route_ids.setdefault(short, []).append(route_id)

            for row in _read_csv(zf, "stops.txt"):
                stop_id = row.get("stop_id", "").strip()
                if stop_id:
                    gtfs.stops[stop_id] = row

            for row in _read_csv(zf, "trips.txt"):
                trip_id = row.get("trip_id", "").strip()
                if trip_id:
                    gtfs.trips[trip_id] = row
        return gtfs

    # --------------------------------------------------------------- lookups
    def route_ids_for_line(self, short_name: str) -> list[str]:
        """``route_id`` (anche più d'uno) per una linea es. "10"."""
        return list(self.short_name_to_route_ids.get(short_name, []))

    def short_name_for_route_id(self, route_id: str | None) -> str | None:
        if not route_id:
            return None
        row = self.routes.get(route_id)
        if not row:
            return None
        return row.get("route_short_name") or None

    def short_name_for_trip(self, trip_id: str | None) -> str | None:
        if not trip_id:
            return None
        trip = self.trips.get(trip_id)
        if not trip:
            return None
        return self.short_name_for_route_id(trip.get("route_id"))

    def headsign_for_trip(self, trip_id: str | None) -> str | None:
        if not trip_id:
            return None
        trip = self.trips.get(trip_id)
        if not trip:
            return None
        return (trip.get("trip_headsign") or "").strip() or None

    # ---------------------------------------------------------------- output
    def lines(self) -> list[Line]:
        """Elenco linee ordinate (numerico quando possibile, poi alfabetico)."""
        out: list[Line] = []
        for short, route_ids in self.short_name_to_route_ids.items():
            # descrizione = long_name della prima route con quel short_name
            desc = None
            for rid in route_ids:
                long_name = (self.routes.get(rid, {}).get("route_long_name") or "").strip()
                if long_name:
                    desc = long_name
                    break
            out.append(Line(line=short, description=desc, route_ids=list(route_ids)))
        out.sort(key=_line_sort_key)
        return out

    def search_stops(self, query: str, limit: int = 20) -> list[Stop]:
        """Ricerca fermate per nome o codice palina (case-insensitive)."""
        q = (query or "").strip().lower()
        if not q:
            return []
        matches: list[Stop] = []
        for stop_id, row in self.stops.items():
            name = (row.get("stop_name") or "").strip()
            code = (row.get("stop_code") or "").strip()
            if q in name.lower() or q in code.lower() or q == stop_id.lower():
                matches.append(_to_stop(stop_id, row))
        # i match per codice/id esatto vengono prima
        matches.sort(
            key=lambda s: (q not in (s.code or "").lower() and q != s.stop_id.lower(), s.name or "")
        )
        return matches[:limit]

    def stop(self, stop_id: str) -> Stop | None:
        row = self.stops.get(stop_id)
        return _to_stop(stop_id, row) if row else None


def _to_stop(stop_id: str, row: dict[str, str]) -> Stop:
    return Stop(
        stop_id=stop_id,
        code=(row.get("stop_code") or "").strip() or None,
        name=(row.get("stop_name") or "").strip(),
        lat=_to_float(row.get("stop_lat")),
        lon=_to_float(row.get("stop_lon")),
    )


def _to_float(value: str | None) -> float | None:
    if value is None or value == "":
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _line_sort_key(line: Line) -> tuple[int, float, str]:
    """Ordina: prima le linee numeriche per valore, poi quelle alfanumeriche."""
    name = line.line
    try:
        return (0, float(name), name)
    except ValueError:
        return (1, 0.0, name)


def download_zip_bytes(settings: Settings | None = None) -> bytes:
    """Scarica lo ZIP GTFS statico (rete). Isolato per testabilità."""
    settings = settings or get_settings()
    resp = httpx.get(settings.gtfs_static_url, timeout=settings.http_timeout, follow_redirects=True)
    resp.raise_for_status()
    return resp.content


__all__ = ["GtfsStatic", "download_zip_bytes"]
