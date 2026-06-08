"""Test del motore alert con feed/scioperi mockati: nessuna rete, nessun invio.

Verifica il criterio M3 'Fatto quando': con feed simulati, gli eventi corretti
vengono accodati **una sola volta** (logica idempotente, dedup su notified_events).
"""

from __future__ import annotations

import pytest
from sqlalchemy import create_engine, select
from sqlalchemy.orm import sessionmaker

from app.alerts import (
    InProcessDispatcher,
    build_scheduler,
    evaluate_imminent,
    evaluate_service_alerts,
    evaluate_strikes,
    strike_key,
)
from app.db import Base, Device, NotifiedEvent, Subscription
from app.realtime import parse_feed
from app.scioperi import filter_for_torino, parse_strikes_csv

# Stesso istante delle fixture: gli arrivi cadono a +120s / +240s.
FUTURE_TS = 1893456000


@pytest.fixture
def session_factory(tmp_path):
    engine = create_engine(
        f"sqlite:///{tmp_path / 'alerts.db'}", connect_args={"check_same_thread": False}
    )
    Base.metadata.create_all(engine)
    return sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


def _device_with_sub(session_factory, **sub_kwargs) -> tuple[int, int]:
    with session_factory() as s:
        dev = Device(platform="android", fcm_token=f"tok-{sub_kwargs.get('kind')}-{id(sub_kwargs)}")
        sub = Subscription(**sub_kwargs)
        dev.subscriptions.append(sub)
        s.add(dev)
        s.commit()
        return dev.id, sub.id


# ------------------------------------------------------------------- imminent
def test_imminent_enqueues_once(session_factory, gtfs, trip_updates_bytes):
    _device_with_sub(session_factory, kind="imminent", stop_id="350", line="10", threshold_min=5)
    feed = parse_feed(trip_updates_bytes)
    dispatcher = InProcessDispatcher()

    with session_factory() as s:
        # Linea 10 alla 350: arrivo a 4 min ≤ soglia 5 → 1 accodato.
        n = evaluate_imminent(s, feed, gtfs, dispatcher, now=FUTURE_TS)
    assert n == 1
    assert len(dispatcher.pending) == 1
    msg = dispatcher.pending[0]
    assert msg.data["kind"] == "imminent" and msg.data["line"] == "10"

    # Secondo giro con lo stesso feed → idempotente: niente nuovi accodamenti.
    with session_factory() as s:
        n2 = evaluate_imminent(s, feed, gtfs, dispatcher, now=FUTURE_TS)
    assert n2 == 0
    assert len(dispatcher.pending) == 1

    # Una sola riga di dedup registrata.
    with session_factory() as s:
        events = s.scalars(select(NotifiedEvent)).all()
    assert len(events) == 1 and events[0].dedup_key.startswith("imminent:")


def test_imminent_respects_threshold(session_factory, gtfs, trip_updates_bytes):
    # Soglia 3 min: l'arrivo di linea 10 è a 4 min → escluso.
    _device_with_sub(session_factory, kind="imminent", stop_id="350", line="10", threshold_min=3)
    feed = parse_feed(trip_updates_bytes)
    dispatcher = InProcessDispatcher()
    with session_factory() as s:
        assert evaluate_imminent(s, feed, gtfs, dispatcher, now=FUTURE_TS) == 0
    assert dispatcher.pending == []


def test_imminent_all_lines_when_no_line_filter(session_factory, gtfs, trip_updates_bytes):
    # Senza filtro linea: alla 350 arrivano linea 55 (2 min) e linea 10 (4 min).
    _device_with_sub(session_factory, kind="imminent", stop_id="350", line=None, threshold_min=5)
    feed = parse_feed(trip_updates_bytes)
    dispatcher = InProcessDispatcher()
    with session_factory() as s:
        assert evaluate_imminent(s, feed, gtfs, dispatcher, now=FUTURE_TS) == 2


def test_imminent_no_subscriptions(session_factory, gtfs, trip_updates_bytes):
    feed = parse_feed(trip_updates_bytes)
    dispatcher = InProcessDispatcher()
    with session_factory() as s:
        assert evaluate_imminent(s, feed, gtfs, dispatcher, now=FUTURE_TS) == 0


# --------------------------------------------------------------------- strike
def test_strikes_enqueue_once(session_factory, strikes_csv):
    _device_with_sub(session_factory, kind="strike", line="10")
    strikes = filter_for_torino(parse_strikes_csv(strikes_csv))
    assert len(strikes) == 2  # Piemonte + nazionale (Lombardia/scuola escluso)
    dispatcher = InProcessDispatcher()

    with session_factory() as s:
        n = evaluate_strikes(s, strikes, dispatcher, now=FUTURE_TS)
    assert n == 2
    assert {m.data["kind"] for m in dispatcher.pending} == {"strike"}

    # Idempotente: stessi scioperi → nessun nuovo accodamento.
    with session_factory() as s:
        assert evaluate_strikes(s, strikes, dispatcher, now=FUTURE_TS) == 0
    assert len(dispatcher.pending) == 2


def test_strike_key_stable_and_distinct(strikes_csv):
    strikes = filter_for_torino(parse_strikes_csv(strikes_csv))
    keys = {strike_key(s) for s in strikes}
    assert len(keys) == 2  # i due scioperi hanno chiavi diverse
    # Stabile: stessa riga → stessa chiave.
    assert strike_key(strikes[0]) == strike_key(strikes[0])


# ------------------------------------------------------------------- dispatcher
def test_service_alerts_enqueue_once(session_factory, gtfs, alerts_bytes):
    # La fixture alerts ha un avviso sulla linea 10 (DETOUR).
    _device_with_sub(session_factory, kind="line_alert", line="10")
    feed = parse_feed(alerts_bytes)
    dispatcher = InProcessDispatcher()
    with session_factory() as s:
        n = evaluate_service_alerts(s, feed, gtfs, dispatcher, now=FUTURE_TS)
    assert n == 1
    drained = dispatcher.drain()
    assert drained[0].data["kind"] == "line_alert" and drained[0].data["line"] == "10"
    # Idempotente: stesso avviso → niente seconda push.
    with session_factory() as s:
        assert evaluate_service_alerts(s, feed, gtfs, dispatcher, now=FUTURE_TS) == 0


def test_service_alerts_ignores_other_lines(session_factory, gtfs, alerts_bytes):
    _device_with_sub(session_factory, kind="line_alert", line="99")  # linea senza avvisi
    feed = parse_feed(alerts_bytes)
    dispatcher = InProcessDispatcher()
    with session_factory() as s:
        assert evaluate_service_alerts(s, feed, gtfs, dispatcher, now=FUTURE_TS) == 0


def test_dispatcher_drain():
    d = InProcessDispatcher()
    from app.alerts import PushMessage

    d.enqueue(PushMessage(device_id=1, title="t", body="b"))
    drained = d.drain()
    assert len(drained) == 1
    assert d.pending == []  # svuotata


# -------------------------------------------------------------------- scheduler
def test_build_scheduler_has_alert_jobs(session_factory):
    scheduler = build_scheduler(
        provider=None, dispatcher=InProcessDispatcher(), session_factory=session_factory
    )
    job_ids = {j.id for j in scheduler.get_jobs()}
    assert job_ids == {"imminent", "strike", "service_alert"}
    # Non avviato: nessun polling, nessun thread.
    assert not scheduler.running
