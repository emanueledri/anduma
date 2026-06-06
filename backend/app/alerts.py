"""Motore alert + scheduler.

Due valutazioni periodiche (APScheduler):

- **imminent** (~15 s): per ogni sottoscrizione, legge gli arrivi previsti alla
  fermata per la linea; se l'ETA è entro la soglia e non già notificato per quel
  ``trip_id``, accoda una push.
- **strike** (~1 h): per ogni nuovo sciopero rilevante per Torino, notifica le
  sottoscrizioni ``strike`` (una sola volta per sciopero).

La logica è **idempotente**: la deduplica passa da ``notified_events`` (chiave
``(subscription_id, dedup_key)`` con TTL). Il dispatcher è **disaccoppiato**: qui
si accoda soltanto; l'invio reale (FCM/APNs) arriva in M4. Le funzioni di
valutazione sono pure rispetto a feed/scioperi passati come argomento, quindi
testabili senza rete né invii reali.
"""

from __future__ import annotations

import datetime as dt
import hashlib
import time
from collections.abc import Callable
from dataclasses import dataclass, field
from typing import Protocol

from google.transit import gtfs_realtime_pb2
from sqlalchemy import select
from sqlalchemy.orm import Session, sessionmaker

from .config import Settings, get_settings
from .db import NotifiedEvent, Subscription
from .gtfs_static import GtfsStatic
from .models import Strike
from .realtime import arrivals_for_stop, parse_feed
from .scioperi import filter_for_torino, filter_upcoming, parse_strikes_csv

# Buffer oltre l'ETA stimato prima che la dedup scada (il mezzo è passato).
_IMMINENT_TTL_BUFFER_S = 120
# Per gli scioperi non abbiamo sempre una data di fine affidabile: TTL lungo.
_STRIKE_TTL_DAYS = 30


@dataclass
class PushMessage:
    """Notifica da inviare (consumata dal push reale in M4)."""

    device_id: int
    title: str
    body: str
    data: dict[str, str] = field(default_factory=dict)


class Dispatcher(Protocol):
    def enqueue(self, message: PushMessage) -> None: ...


class InProcessDispatcher:
    """Coda in-process: punto di disaccoppiamento prima del push reale (M4)."""

    def __init__(self) -> None:
        self._queue: list[PushMessage] = []

    def enqueue(self, message: PushMessage) -> None:
        self._queue.append(message)

    def drain(self) -> list[PushMessage]:
        """Restituisce e svuota la coda (lo userà il dispatcher push)."""
        items, self._queue = self._queue, []
        return items

    @property
    def pending(self) -> list[PushMessage]:
        return list(self._queue)


def _now_dt(now_ts: float) -> dt.datetime:
    return dt.datetime.fromtimestamp(now_ts, dt.UTC)


def _already_notified(
    session: Session, subscription_id: int, dedup_key: str, now_dt: dt.datetime
) -> bool:
    return (
        session.scalar(
            select(NotifiedEvent).where(
                NotifiedEvent.subscription_id == subscription_id,
                NotifiedEvent.dedup_key == dedup_key,
                NotifiedEvent.expires_at > now_dt,
            )
        )
        is not None
    )


# ------------------------------------------------------------------- imminent
def evaluate_imminent(
    session: Session,
    feed: gtfs_realtime_pb2.FeedMessage,
    gtfs: GtfsStatic,
    dispatcher: Dispatcher,
    now: float | None = None,
) -> int:
    """Valuta le sottoscrizioni ``imminent`` sul feed dato. Ritorna gli accodati."""
    now_ts = now if now is not None else time.time()
    now_dt = _now_dt(now_ts)
    subs = session.scalars(
        select(Subscription).where(Subscription.kind == "imminent", Subscription.active.is_(True))
    ).all()

    enqueued = 0
    for sub in subs:
        if not sub.stop_id:
            continue
        arrivals = arrivals_for_stop(feed, gtfs, sub.stop_id, line=sub.line, now=now_ts)
        for arr in arrivals:
            if arr.trip_id is None:
                continue
            if sub.threshold_min is not None and arr.eta_minutes > sub.threshold_min:
                continue
            dedup_key = f"imminent:{arr.trip_id}"
            if _already_notified(session, sub.id, dedup_key, now_dt):
                continue
            expires = now_dt + dt.timedelta(seconds=arr.eta_seconds + _IMMINENT_TTL_BUFFER_S)
            session.add(
                NotifiedEvent(subscription_id=sub.id, dedup_key=dedup_key, expires_at=expires)
            )
            line = arr.line or sub.line or "?"
            dispatcher.enqueue(
                PushMessage(
                    device_id=sub.device_id,
                    title=f"Linea {line} in arrivo",
                    body=f"~{arr.eta_minutes} min alla fermata {sub.stop_id}"
                    + (f" → {arr.headsign}" if arr.headsign else ""),
                    data={
                        "kind": "imminent",
                        "line": line,
                        "stop_id": sub.stop_id,
                        "trip_id": arr.trip_id,
                        "eta_seconds": str(arr.eta_seconds),
                    },
                )
            )
            enqueued += 1
    session.commit()
    return enqueued


# --------------------------------------------------------------------- strike
def strike_key(strike: Strike) -> str:
    """Identità stabile di uno sciopero (per la deduplica)."""
    base = "|".join(
        [
            strike.start_date or "",
            strike.end_date or "",
            strike.area or "",
            strike.sector or "",
        ]
    )
    digest = hashlib.sha1(base.encode("utf-8")).hexdigest()[:16]
    return f"strike:{digest}"


def evaluate_strikes(
    session: Session,
    strikes: list[Strike],
    dispatcher: Dispatcher,
    now: float | None = None,
) -> int:
    """Notifica le sottoscrizioni ``strike`` per ogni nuovo sciopero. Idempotente."""
    now_ts = now if now is not None else time.time()
    now_dt = _now_dt(now_ts)
    expires = now_dt + dt.timedelta(days=_STRIKE_TTL_DAYS)
    subs = session.scalars(
        select(Subscription).where(Subscription.kind == "strike", Subscription.active.is_(True))
    ).all()

    enqueued = 0
    for strike in strikes:
        key = strike_key(strike)
        for sub in subs:
            if _already_notified(session, sub.id, key, now_dt):
                continue
            session.add(NotifiedEvent(subscription_id=sub.id, dedup_key=key, expires_at=expires))
            when = strike.start_date or "prossimamente"
            dispatcher.enqueue(
                PushMessage(
                    device_id=sub.device_id,
                    title="Sciopero trasporto pubblico",
                    body=f"Sciopero TPL ({strike.area or 'nazionale'}) — {when}",
                    data={
                        "kind": "strike",
                        "line": sub.line or "",
                        "area": strike.area or "",
                        "start_date": strike.start_date or "",
                    },
                )
            )
            enqueued += 1
    session.commit()
    return enqueued


# ----------------------------------------------------------- scheduler wiring
def run_imminent(provider, dispatcher: Dispatcher, session_factory: sessionmaker[Session]) -> int:
    """Job imminent: legge i trip update dal provider e valuta (tollerante a errori)."""
    try:
        feed = parse_feed(provider.trip_updates_bytes())
        gtfs = provider.gtfs()
    except Exception:
        return 0  # sorgente irraggiungibile: salta questo giro
    with session_factory() as session:
        return evaluate_imminent(session, feed, gtfs, dispatcher)


def run_strikes(provider, dispatcher: Dispatcher, session_factory: sessionmaker[Session]) -> int:
    """Job strike: legge il registro MIT dal provider e valuta (tollerante a errori)."""
    try:
        strikes = filter_upcoming(filter_for_torino(parse_strikes_csv(provider.strikes_csv())))
    except Exception:
        return 0
    with session_factory() as session:
        return evaluate_strikes(session, strikes, dispatcher)


def build_scheduler(
    provider,
    dispatcher: Dispatcher,
    session_factory: sessionmaker[Session],
    settings: Settings | None = None,
    push_processor: Callable[[], object] | None = None,
):
    """Crea (senza avviare) un BackgroundScheduler con i job alert.

    Se ``push_processor`` è fornito (callable a zero argomenti), aggiunge anche un
    job ``push`` che svuota la coda del dispatcher e invia (vedi M4).
    """
    from apscheduler.schedulers.background import BackgroundScheduler

    settings = settings or get_settings()
    scheduler = BackgroundScheduler(timezone="Europe/Rome")
    scheduler.add_job(
        run_imminent,
        "interval",
        seconds=settings.imminent_interval_s,
        args=[provider, dispatcher, session_factory],
        id="imminent",
        max_instances=1,
        coalesce=True,
    )
    scheduler.add_job(
        run_strikes,
        "interval",
        seconds=settings.strike_interval_s,
        args=[provider, dispatcher, session_factory],
        id="strike",
        max_instances=1,
        coalesce=True,
    )
    if push_processor is not None:
        scheduler.add_job(
            push_processor,
            "interval",
            seconds=settings.push_interval_s,
            id="push",
            max_instances=1,
            coalesce=True,
        )
    return scheduler


__all__ = [
    "PushMessage",
    "Dispatcher",
    "InProcessDispatcher",
    "evaluate_imminent",
    "evaluate_strikes",
    "strike_key",
    "run_imminent",
    "run_strikes",
    "build_scheduler",
]
