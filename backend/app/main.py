"""FastAPI app read-only (Milestone 0): linee, fermate, arrivi, mezzi, avvisi.

Il polling dei feed lo fa SOLO il backend (cache condivisa nel provider): il
client parla esclusivamente con questa API.
"""

from __future__ import annotations

import asyncio
from contextlib import asynccontextmanager, suppress

from fastapi import Depends, FastAPI, HTTPException, Query, WebSocket, WebSocketDisconnect
from starlette.concurrency import run_in_threadpool

from . import realtime, scioperi
from .alerts import InProcessDispatcher, build_scheduler
from .cache import RedisCache
from .config import get_settings
from .db import SessionLocal, db_healthcheck
from .me import router as me_router
from .models import (
    AlertsResponse,
    ArrivalsResponse,
    Health,
    Line,
    Stop,
    VehiclesResponse,
)
from .provider import DataProvider, LiveProvider
from .push import build_push_service, make_push_processor
from .ws import ConnectionManager

ATTRIBUTION = "Dati: Città di Torino / GTT (CC BY 4.0); scioperi MIT; mappa © OpenStreetMap"


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()
    provider = LiveProvider()
    app.state.provider = provider
    app.state.dispatcher = InProcessDispatcher()
    app.state.scheduler = None
    app.state.ws_manager = ConnectionManager(settings.ws_max_connections)
    app.state.ws_interval_s = settings.ws_interval_s
    # Pre-carica il GTFS statico (tollerante a rete assente).
    with suppress(Exception):
        provider.gtfs()
    # Scheduler alert: disattivato di default (non fa polling finché non abilitato).
    if settings.scheduler_enabled:
        push_service = build_push_service(settings)  # None se FCM non abilitato
        push_processor = (
            make_push_processor(push_service, app.state.dispatcher, SessionLocal)
            if push_service is not None
            else None
        )
        scheduler = build_scheduler(
            provider, app.state.dispatcher, SessionLocal, settings, push_processor=push_processor
        )
        scheduler.start()
        app.state.scheduler = scheduler
    try:
        yield
    finally:
        if app.state.scheduler is not None:
            with suppress(Exception):
                app.state.scheduler.shutdown(wait=False)
        with suppress(Exception):
            provider.close()


app = FastAPI(
    title="Transito Torino — backend",
    version="0.0.1",
    summary="Arrivi, mezzi live e avvisi del trasporto pubblico GTT di Torino.",
    description=ATTRIBUTION,
    lifespan=lifespan,
)

app.include_router(me_router)


def get_provider() -> DataProvider:
    """Dependency: provider dati. Sovrascritta nei test con un fake da fixture."""
    return app.state.provider


@app.get("/health", response_model=Health)
def health(provider: DataProvider = Depends(get_provider)) -> Health:
    gtfs = provider.gtfs()
    cache_backend = "memory"
    cache = getattr(provider, "cache", None)
    if isinstance(cache, RedisCache):
        cache_backend = "redis" if cache.ping() else "redis-down"
    return Health(
        status="ok",
        gtfs_loaded=bool(gtfs.routes),
        routes=len(gtfs.routes),
        stops=len(gtfs.stops),
        db=db_healthcheck(),
        cache=cache_backend,
    )


@app.get("/lines", response_model=list[Line])
def lines(provider: DataProvider = Depends(get_provider)) -> list[Line]:
    return provider.gtfs().lines()


@app.get("/stops/search", response_model=list[Stop])
def stops_search(
    q: str = Query(..., min_length=1, description="Nome fermata o codice palina"),
    limit: int = Query(20, ge=1, le=100),
    provider: DataProvider = Depends(get_provider),
) -> list[Stop]:
    return provider.gtfs().search_stops(q, limit=limit)


@app.get("/stops/{stop_id}/arrivals", response_model=ArrivalsResponse)
def stop_arrivals(
    stop_id: str,
    line: str | None = Query(None, description="Filtra per linea, es. '10'"),
    provider: DataProvider = Depends(get_provider),
) -> ArrivalsResponse:
    gtfs = provider.gtfs()
    stop = gtfs.stop(stop_id)
    if stop is None and gtfs.stops:
        raise HTTPException(status_code=404, detail="Fermata non trovata")
    feed = realtime.parse_feed(provider.trip_updates_bytes())
    arrivals = realtime.arrivals_for_stop(feed, gtfs, stop_id, line=line)
    return ArrivalsResponse(
        stop_id=stop_id,
        name=stop.name if stop else None,
        arrivals=arrivals,
    )


def _vehicles_response(provider: DataProvider, line: str) -> VehiclesResponse:
    """Posizioni dei mezzi di una linea dalla cache RT condivisa (REST e WS)."""
    gtfs = provider.gtfs()
    feed = realtime.parse_feed(provider.vehicle_positions_bytes())
    vehicles = realtime.vehicles_for_line(feed, gtfs, line)
    return VehiclesResponse(line=line, count=len(vehicles), vehicles=vehicles)


@app.get("/lines/{line}/vehicles", response_model=VehiclesResponse)
def line_vehicles(
    line: str,
    provider: DataProvider = Depends(get_provider),
) -> VehiclesResponse:
    return _vehicles_response(provider, line)


@app.websocket("/ws/lines/{line}")
async def ws_line_vehicles(
    websocket: WebSocket,
    line: str,
    provider: DataProvider = Depends(get_provider),
) -> None:
    """Spinge le posizioni della linea ogni ~3–5 s dalla cache RT condivisa.

    Fallback se il WS non è disponibile: polling REST di
    ``GET /lines/{line}/vehicles`` (stesso schema del messaggio).
    """
    await websocket.accept()
    manager: ConnectionManager = websocket.app.state.ws_manager
    if not manager.register(websocket):
        # Tetto connessioni raggiunto: chiudi invitando a riprovare.
        await websocket.close(code=1013)  # Try Again Later
        return
    interval = getattr(websocket.app.state, "ws_interval_s", 4.0)
    try:
        while True:
            # Letture potenzialmente bloccanti (cache/parse) fuori dall'event loop.
            resp = await run_in_threadpool(_vehicles_response, provider, line)
            await websocket.send_json(resp.model_dump())
            await asyncio.sleep(interval)
    except WebSocketDisconnect:
        pass
    finally:
        manager.unregister(websocket)


@app.get("/alerts", response_model=AlertsResponse)
def alerts(
    line: str | None = Query(None, description="Filtra avvisi per linea"),
    provider: DataProvider = Depends(get_provider),
) -> AlertsResponse:
    gtfs = provider.gtfs()
    feed = realtime.parse_feed(provider.alerts_bytes())
    service = realtime.service_alerts(feed, gtfs, line=line)
    strikes = scioperi.filter_for_torino(scioperi.parse_strikes_csv(provider.strikes_csv()))
    return AlertsResponse(service_alerts=service, strikes=strikes)
