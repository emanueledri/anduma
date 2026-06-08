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
import datetime as dt
import io
import re
import sys
import zipfile
from dataclasses import dataclass, field

import httpx

from .config import Settings, get_settings
from .models import Line, Stop

_WEEKDAYS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")

# GTFS route_type → modalità (per l'icona client). Coprono i codici base e i
# principali "extended" (HVT) usati da alcune agenzie. Default: "bus".
_MODE_BY_ROUTE_TYPE = {
    0: "tram",
    1: "metro",
    2: "rail",
    3: "bus",
    4: "ferry",
    5: "tram",  # cable tram
    6: "bus",  # aerial lift → nessuna icona dedicata
    7: "funicular",
    11: "bus",  # trolleybus
    12: "rail",  # monorail
}


def _mode_for_route_type(value: str | None) -> str:
    """Normalizza ``route_type`` GTFS (anche extended) in una modalità nota."""
    try:
        rt = int((value or "").strip())
    except (ValueError, AttributeError):
        return "bus"
    if rt in _MODE_BY_ROUTE_TYPE:
        return _MODE_BY_ROUTE_TYPE[rt]
    # Extended route types (HVT): si classifica per centinaia.
    bucket = (rt // 100) * 100
    return {
        100: "rail",
        400: "metro",
        700: "bus",
        900: "tram",
        1000: "ferry",
        1400: "funicular",
    }.get(bucket, "bus")


def _read_csv(zf: zipfile.ZipFile, name: str) -> list[dict[str, str]]:
    """Legge un file CSV dello ZIP GTFS; ritorna [] se assente."""
    if name not in zf.namelist():
        return []
    with zf.open(name) as fh:
        # GTFS è UTF-8 (a volte con BOM): utf-8-sig pulisce il BOM.
        text = io.TextIOWrapper(fh, encoding="utf-8-sig", newline="")
        return list(csv.DictReader(text))


def _hms_to_secs(value: str) -> int | None:
    """'HH:MM:SS' → secondi dalla mezzanotte (gestisce ore ≥ 24)."""
    try:
        h, m, s = value.split(":")
        return int(h) * 3600 + int(m) * 60 + int(s)
    except (ValueError, AttributeError):
        return None


def _active_services(zf: zipfile.ZipFile, on_date: dt.date) -> set[str]:
    """Service_id attivi in una data, da ``calendar.txt`` + ``calendar_dates.txt``."""
    ymd = on_date.strftime("%Y%m%d")
    weekday = _WEEKDAYS[on_date.weekday()]
    active: set[str] = set()
    for row in _read_csv(zf, "calendar.txt"):
        sid = (row.get("service_id") or "").strip()
        if not sid:
            continue
        start = (row.get("start_date") or "").strip()
        end = (row.get("end_date") or "").strip()
        if start and end and not (start <= ymd <= end):
            continue
        if (row.get(weekday) or "0").strip() == "1":
            active.add(sid)
    # Eccezioni: 1 = servizio aggiunto, 2 = servizio rimosso.
    for row in _read_csv(zf, "calendar_dates.txt"):
        if (row.get("date") or "").strip() != ymd:
            continue
        sid = (row.get("service_id") or "").strip()
        exc = (row.get("exception_type") or "").strip()
        if exc == "1":
            active.add(sid)
        elif exc == "2":
            active.discard(sid)
    return active


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
    # Orari programmati delle SOLE corse attive nella data: serve perché i feed
    # RT di GTT indicano la fermata con stop_sequence (non stop_id) e spesso solo
    # col delay. trip_id -> {stop_sequence: (stop_id, arrival_secs|None)}
    schedule: dict[str, dict[int, tuple[str, int | None]]] = field(default_factory=dict)
    # Data di servizio per cui è costruito ``schedule`` (base per il delay).
    schedule_date: dt.date | None = None
    # Tracciati: shape_id -> [(lat, lon), ...] ordinati per sequenza (per la
    # sovrimpressione del percorso sulla mappa). Da ``shapes.txt``.
    shapes: dict[str, list[tuple[float, float]]] = field(default_factory=dict)
    # Linee che servono ogni palina (per disambiguare le fermate omonime):
    # stop_id -> [short_name, ...]. Costruito dallo schedule (corse attive).
    stop_lines: dict[str, list[str]] = field(default_factory=dict)

    # ------------------------------------------------------------------ build
    @classmethod
    def from_zip_bytes(cls, data: bytes, schedule_for_date: dt.date | None = None) -> GtfsStatic:
        """Costruisce lo snapshot da un GTFS ZIP (bytes).

        Se ``schedule_for_date`` è fornita, costruisce anche l'indice orari per le
        sole corse in servizio quel giorno (così resta leggero: ~1/7 del totale).
        """
        gtfs = cls()
        gtfs.schedule_date = schedule_for_date
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

            if schedule_for_date is not None:
                gtfs._build_schedule(zf, schedule_for_date)
            gtfs._build_shapes(zf)
        return gtfs

    def _build_shapes(self, zf: zipfile.ZipFile) -> None:
        """Indicizza ``shapes.txt``: shape_id -> punti ordinati per sequenza."""
        if "shapes.txt" not in zf.namelist():
            return
        # Accumula (seq, lat, lon) per ordinare alla fine senza ri-scansioni.
        tmp: dict[str, list[tuple[int, float, float]]] = {}
        with zf.open("shapes.txt") as fh:
            reader = csv.reader(io.TextIOWrapper(fh, encoding="utf-8-sig"))
            header = next(reader, None)
            if not header:
                return
            idx = {name: i for i, name in enumerate(header)}
            i_id = idx.get("shape_id")
            i_lat, i_lon = idx.get("shape_pt_lat"), idx.get("shape_pt_lon")
            i_seq = idx.get("shape_pt_sequence")
            if None in (i_id, i_lat, i_lon, i_seq):
                return
            for r in reader:
                try:
                    sid = r[i_id]
                    pt = (int(r[i_seq]), float(r[i_lat]), float(r[i_lon]))
                except (ValueError, IndexError):
                    continue
                tmp.setdefault(sys.intern(sid), []).append(pt)
        for sid, pts in tmp.items():
            pts.sort(key=lambda p: p[0])
            self.shapes[sid] = [(lat, lon) for _seq, lat, lon in pts]

    def _build_schedule(self, zf: zipfile.ZipFile, on_date: dt.date) -> None:
        """Indicizza ``stop_times.txt`` per le corse attive in ``on_date`` (streaming)."""
        if "stop_times.txt" not in zf.namelist():
            return
        services = _active_services(zf, on_date)
        active_trips = {
            tid
            for tid, row in self.trips.items()
            if (row.get("service_id") or "").strip() in services
        }
        if not active_trips:
            return
        with zf.open("stop_times.txt") as fh:
            reader = csv.reader(io.TextIOWrapper(fh, encoding="utf-8-sig"))
            header = next(reader, None)
            if not header:
                return
            idx = {name: i for i, name in enumerate(header)}
            i_trip, i_arr = idx.get("trip_id"), idx.get("arrival_time")
            i_stop, i_seq = idx.get("stop_id"), idx.get("stop_sequence")
            if None in (i_trip, i_stop, i_seq):
                return
            for r in reader:
                tid = r[i_trip]
                if tid not in active_trips:
                    continue
                try:
                    seq = int(r[i_seq])
                except (ValueError, IndexError):
                    continue
                sid = sys.intern(r[i_stop])
                secs = _hms_to_secs(r[i_arr]) if i_arr is not None else None
                self.schedule.setdefault(sys.intern(tid), {})[seq] = (sid, secs)
        self._build_stop_lines()

    def _build_stop_lines(self) -> None:
        """Indice palina -> linee servite (dalle corse indicizzate)."""
        acc: dict[str, list[str]] = {}
        for tid, stops in self.schedule.items():
            short = self.short_name_for_trip(tid)
            if not short:
                continue
            for _seq, (sid, _secs) in stops.items():
                lst = acc.setdefault(sid, [])
                if short not in lst:
                    lst.append(short)
        for lines in acc.values():
            lines.sort(key=_line_sort_key_str)
        self.stop_lines = acc

    def lines_for_stop(self, stop_id: str) -> list[str]:
        return list(self.stop_lines.get(stop_id, []))

    def resolve_seq(self, trip_id: str | None, stop_sequence: int) -> tuple[str, int | None] | None:
        """``(stop_id, arrival_secs)`` per (corsa, sequenza) dall'indice orari."""
        if not trip_id:
            return None
        return self.schedule.get(trip_id, {}).get(stop_sequence)

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

    def mode_for_route_id(self, route_id: str | None) -> str:
        """Modalità (tram/metro/bus/...) di una route dal suo ``route_type``."""
        if not route_id:
            return "bus"
        return _mode_for_route_type(self.routes.get(route_id, {}).get("route_type"))

    def mode_for_line(self, short_name: str) -> str:
        """Modalità di una linea: dalla prima route con quel ``short_name``."""
        ids = self.short_name_to_route_ids.get(short_name)
        return self.mode_for_route_id(ids[0]) if ids else "bus"

    def _trip_ids_for_line(self, short_name: str) -> list[str]:
        """trip_id delle corse di una linea (per shape/fermate)."""
        route_ids = set(self.short_name_to_route_ids.get(short_name, []))
        if not route_ids:
            return []
        return [
            tid
            for tid, row in self.trips.items()
            if (row.get("route_id") or "") in route_ids
        ]

    def shape_for_line(self, short_name: str, limit: int = 8) -> list[list[tuple[float, float]]]:
        """Tracciati distinti di una linea (i più lunghi prima), per la mappa."""
        seen: set[str] = set()
        polylines: list[list[tuple[float, float]]] = []
        for tid in self._trip_ids_for_line(short_name):
            sid = (self.trips.get(tid, {}).get("shape_id") or "").strip()
            if not sid or sid in seen:
                continue
            pts = self.shapes.get(sid)
            if not pts:
                continue
            seen.add(sid)
            polylines.append(pts)
        polylines.sort(key=len, reverse=True)
        return polylines[:limit]

    def stops_for_line(self, short_name: str) -> list[Stop]:
        """Fermate servite da una linea (dalle corse attive indicizzate)."""
        stop_ids: list[str] = []
        seen: set[str] = set()
        for tid in self._trip_ids_for_line(short_name):
            for _seq, (sid, _secs) in sorted(self.schedule.get(tid, {}).items()):
                if sid not in seen and sid in self.stops:
                    seen.add(sid)
                    stop_ids.append(sid)
        return [_to_stop(sid, self.stops[sid]) for sid in stop_ids]

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
            mode = self.mode_for_route_id(route_ids[0]) if route_ids else "bus"
            out.append(
                Line(line=short, description=desc, route_ids=list(route_ids), mode=mode)
            )
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
                matches.append(self._to_stop(stop_id, row))
        # i match per codice/id esatto vengono prima
        matches.sort(
            key=lambda s: (q not in (s.code or "").lower() and q != s.stop_id.lower(), s.name or "")
        )
        return matches[:limit]

    def stop(self, stop_id: str) -> Stop | None:
        row = self.stops.get(stop_id)
        return self._to_stop(stop_id, row) if row else None

    def _to_stop(self, stop_id: str, row: dict[str, str]) -> Stop:
        return _to_stop(stop_id, row, lines=self.lines_for_stop(stop_id))


def _to_stop(stop_id: str, row: dict[str, str], lines: list[str] | None = None) -> Stop:
    return Stop(
        stop_id=stop_id,
        code=(row.get("stop_code") or "").strip() or None,
        name=_clean_stop_name(row.get("stop_name")),
        desc=_normalize_desc(row.get("stop_desc")),
        lat=_to_float(row.get("stop_lat")),
        lon=_to_float(row.get("stop_lon")),
        lines=lines or [],
    )


# "Fermata 350 - MASSARI" → "MASSARI" (il numero palina resta in `code`).
_STOP_NAME_PREFIX = re.compile(r"^fermata\s+\S+\s*-\s*", re.IGNORECASE)

# Abbreviazioni toponomastiche GTT (stop_desc è in MAIUSCOLO).
_DESC_ABBR = {
    "V.": "Via", "V": "Via", "VIA": "Via",
    "C.": "Corso", "C.SO": "Corso", "CSO": "Corso", "CORSO": "Corso",
    "V.LE": "Viale", "VLE": "Viale", "VIALE": "Viale",
    "P.": "Piazza", "P.ZA": "Piazza", "P.ZZA": "Piazza", "PZA": "Piazza", "PIAZZA": "Piazza",
    "STR.": "Strada", "STRADA": "Strada", "LARGO": "Largo",
}


def _clean_stop_name(raw: str | None) -> str:
    s = (raw or "").strip()
    cleaned = _STOP_NAME_PREFIX.sub("", s).strip()
    return cleaned or s


def _normalize_desc(raw: str | None) -> str | None:
    """``stop_desc`` (MAIUSCOLO, abbreviato) → leggibile: 'Via Giusti 6 · Nichelino'."""
    s = (raw or "").strip()
    if not s:
        return None
    out: list[str] = []
    for tok in s.split():
        out.append(_DESC_ABBR.get(tok.upper(), tok if not tok.isalpha() else tok.capitalize()))
    return " ".join(out)


def _line_sort_key_str(name: str) -> tuple[int, float, str]:
    """Come ``_line_sort_key`` ma su una stringa-linea."""
    try:
        return (0, float(name), name)
    except ValueError:
        return (1, 0.0, name)


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
