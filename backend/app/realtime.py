"""GTFS-Realtime: parsing dei tre feed protobuf + fetcher con cache TTL.

I feed sono protobuf binari (NON JSON): si parsano con ``gtfs-realtime-bindings``.
Tutti i campi sono opzionali per spec, quindi si controlla sempre ``HasField``
prima di leggere e si degrada con grazia.

Le funzioni di parsing sono pure (prendono ``bytes`` + ``GtfsStatic``) e quindi
testabili da fixture; il fetch di rete con TTL sta in ``FeedFetcher``.
"""

from __future__ import annotations

import time

import httpx
from google.transit import gtfs_realtime_pb2

from .cache import Cache, InMemoryCache
from .config import Settings, get_settings
from .gtfs_static import GtfsStatic
from .models import Arrival, ServiceAlert, Vehicle


def parse_feed(data: bytes) -> gtfs_realtime_pb2.FeedMessage:
    """Deserializza un payload GTFS-RT in ``FeedMessage``."""
    feed = gtfs_realtime_pb2.FeedMessage()
    feed.ParseFromString(data)
    return feed


def _translated(ts: gtfs_realtime_pb2.TranslatedString) -> str | None:
    """Prima traduzione disponibile di una ``TranslatedString``."""
    for tr in ts.translation:
        if tr.text:
            return tr.text
    return None


# --------------------------------------------------------------------- vehicles
def vehicles_for_line(
    feed: gtfs_realtime_pb2.FeedMessage, gtfs: GtfsStatic, line: str
) -> list[Vehicle]:
    """Posizioni dei mezzi di una linea (filtra per i suoi ``route_id``).

    Se il GTFS statico non è caricato non possiamo mappare le linee: si degrada
    restituendo tutti i mezzi. Se invece è caricato, una linea ignota dà lista
    vuota (``wanted`` vuoto → nessun match).
    """
    wanted = set(gtfs.route_ids_for_line(line))
    gtfs_loaded = bool(gtfs.routes)
    out: list[Vehicle] = []
    for entity in feed.entity:
        if not entity.HasField("vehicle"):
            continue
        vp = entity.vehicle
        route_id = vp.trip.route_id if vp.HasField("trip") else None
        trip_id = vp.trip.trip_id if vp.HasField("trip") else None
        # Filtro linea: per route_id (preferito) o, in mancanza, per trip_id→route.
        if gtfs_loaded:
            line_via_trip = gtfs.short_name_for_trip(trip_id)
            if route_id not in wanted and line_via_trip != line:
                continue

        pos = vp.position if vp.HasField("position") else None
        out.append(
            Vehicle(
                vehicle_id=vp.vehicle.id if vp.HasField("vehicle") else None,
                trip_id=trip_id or None,
                headsign=gtfs.headsign_for_trip(trip_id),
                lat=pos.latitude if pos is not None else None,
                lon=pos.longitude if pos is not None else None,
                bearing=(pos.bearing if pos is not None and pos.HasField("bearing") else None),
                speed=(pos.speed if pos is not None and pos.HasField("speed") else None),
                ts=vp.timestamp if vp.HasField("timestamp") else None,
            )
        )
    return out


# --------------------------------------------------------------------- arrivals
def arrivals_for_stop(
    feed: gtfs_realtime_pb2.FeedMessage,
    gtfs: GtfsStatic,
    stop_id: str,
    line: str | None = None,
    now: float | None = None,
) -> list[Arrival]:
    """Arrivi previsti alla fermata dai ``TripUpdate`` (ordinati per ETA)."""
    now_ts = int(now if now is not None else time.time())
    out: list[Arrival] = []
    for entity in feed.entity:
        if not entity.HasField("trip_update"):
            continue
        tu = entity.trip_update
        trip_id = tu.trip.trip_id if tu.HasField("trip") else None
        route_id = tu.trip.route_id if tu.HasField("trip") else None
        short = gtfs.short_name_for_route_id(route_id) or gtfs.short_name_for_trip(trip_id)
        if line is not None and short != line:
            continue

        for stu in tu.stop_time_update:
            if stu.stop_id != stop_id:
                continue
            sched_ts = _stop_time_ts(stu)
            if sched_ts is None:
                continue
            eta = sched_ts - now_ts
            if eta < 0:
                continue  # mezzo già passato
            out.append(
                Arrival(
                    line=short,
                    headsign=gtfs.headsign_for_trip(trip_id),
                    trip_id=trip_id or None,
                    eta_seconds=eta,
                    eta_minutes=round(eta / 60),
                    scheduled_ts=sched_ts,
                )
            )
    out.sort(key=lambda a: a.eta_seconds)
    return out


def _stop_time_ts(stu: gtfs_realtime_pb2.TripUpdate.StopTimeUpdate) -> int | None:
    """``arrival.time`` se presente, altrimenti ``departure.time``."""
    if stu.HasField("arrival") and stu.arrival.HasField("time"):
        return stu.arrival.time
    if stu.HasField("departure") and stu.departure.HasField("time"):
        return stu.departure.time
    return None


# ----------------------------------------------------------------- service alerts
def service_alerts(
    feed: gtfs_realtime_pb2.FeedMessage, gtfs: GtfsStatic, line: str | None = None
) -> list[ServiceAlert]:
    """Avvisi di servizio GTT; opzionalmente filtrati per linea."""
    out: list[ServiceAlert] = []
    for entity in feed.entity:
        if not entity.HasField("alert"):
            continue
        alert = entity.alert
        lines: list[str] = []
        for ie in alert.informed_entity:
            short = gtfs.short_name_for_route_id(ie.route_id or None)
            if short and short not in lines:
                lines.append(short)
        if line is not None and line not in lines:
            continue
        effect = (
            gtfs_realtime_pb2.Alert.Effect.Name(alert.effect) if alert.HasField("effect") else None
        )
        out.append(
            ServiceAlert(
                header=_translated(alert.header_text),
                description=_translated(alert.description_text),
                effect=effect,
                lines=lines,
            )
        )
    return out


# ------------------------------------------------------------------- TTL fetcher
class FeedFetcher:
    """Scarica i feed RT con cache TTL condivisa (un fetch per finestra).

    La cache è iniettabile: in-memory in sviluppo, Redis in produzione (la
    stessa istanza è condivisa, così il polling resta centralizzato).
    """

    def __init__(
        self,
        settings: Settings | None = None,
        client: httpx.Client | None = None,
        cache: Cache | None = None,
    ):
        self._settings = settings or get_settings()
        self._client = client or httpx.Client(timeout=self._settings.http_timeout)
        self._cache: Cache = cache or InMemoryCache()

    def _get(self, key: str, url: str, ttl: int) -> bytes:
        hit = self._cache.get(f"rt:{key}")
        if hit is not None:
            return hit
        resp = self._client.get(url, follow_redirects=True)
        resp.raise_for_status()
        self._cache.set(f"rt:{key}", resp.content, ttl)
        return resp.content

    def vehicle_positions(self) -> bytes:
        s = self._settings
        return self._get("vehicles", s.rt_vehicle_positions_url, s.ttl_vehicle_positions)

    def trip_updates(self) -> bytes:
        s = self._settings
        return self._get("trips", s.rt_trip_updates_url, s.ttl_trip_updates)

    def alerts(self) -> bytes:
        s = self._settings
        return self._get("alerts", s.rt_alerts_url, s.ttl_alerts)

    def close(self) -> None:
        self._client.close()


__all__ = [
    "parse_feed",
    "vehicles_for_line",
    "arrivals_for_stop",
    "service_alerts",
    "FeedFetcher",
]
