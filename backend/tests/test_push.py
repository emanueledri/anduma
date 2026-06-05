"""Test dell'invio push con un sender fake: nessun SDK reale, nessuna rete.

Copre il collegamento dispatcher→push e il cleanup dei token invalidi (M4).
"""

from __future__ import annotations

import pytest
from sqlalchemy import create_engine, select
from sqlalchemy.orm import sessionmaker

from app.alerts import InProcessDispatcher, PushMessage
from app.db import Base, Device, Favorite, Subscription
from app.push import InvalidTokenError, PushService, make_push_processor


@pytest.fixture
def session_factory(tmp_path):
    engine = create_engine(
        f"sqlite:///{tmp_path / 'push.db'}", connect_args={"check_same_thread": False}
    )
    Base.metadata.create_all(engine)
    return sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


class FakeSender:
    """Registra gli invii; può marcare alcuni token come invalidi."""

    def __init__(self, invalid: set[str] | None = None):
        self.invalid = invalid or set()
        self.sent: list[tuple[str, PushMessage]] = []

    def send(self, token: str, message: PushMessage) -> None:
        if token in self.invalid:
            raise InvalidTokenError(token)
        self.sent.append((token, message))


def _make_device(session_factory, token: str) -> int:
    with session_factory() as s:
        dev = Device(platform="android", fcm_token=token)
        s.add(dev)
        s.commit()
        return dev.id


def test_process_sends_and_resolves_token(session_factory):
    dev_id = _make_device(session_factory, "tok-ok")
    dispatcher = InProcessDispatcher()
    dispatcher.enqueue(PushMessage(device_id=dev_id, title="Linea 10", body="~3 min"))

    sender = FakeSender()
    with session_factory() as s:
        result = PushService(sender).process(s, dispatcher)

    assert result.sent == 1 and result.failed == 0
    assert sender.sent[0][0] == "tok-ok"
    # La coda è stata svuotata.
    assert dispatcher.pending == []


def test_invalid_token_triggers_device_cleanup(session_factory):
    dev_id = _make_device(session_factory, "tok-bad")
    # Aggiungo preferito + sottoscrizione: devono sparire col device (cascade).
    with session_factory() as s:
        dev = s.get(Device, dev_id)
        dev.favorites.append(Favorite(type="stop", ref="350"))
        dev.subscriptions.append(Subscription(kind="strike", line="10"))
        s.commit()

    dispatcher = InProcessDispatcher()
    dispatcher.enqueue(PushMessage(device_id=dev_id, title="x", body="y"))

    sender = FakeSender(invalid={"tok-bad"})
    with session_factory() as s:
        result = PushService(sender).process(s, dispatcher)

    assert result.sent == 0
    assert result.invalid_tokens == ["tok-bad"]
    # Device rimosso, e con esso preferiti e sottoscrizioni.
    with session_factory() as s:
        assert s.get(Device, dev_id) is None
        assert s.scalars(select(Favorite)).all() == []
        assert s.scalars(select(Subscription)).all() == []


def test_unknown_device_counts_as_failed(session_factory):
    dispatcher = InProcessDispatcher()
    dispatcher.enqueue(PushMessage(device_id=999999, title="x", body="y"))
    sender = FakeSender()
    with session_factory() as s:
        result = PushService(sender).process(s, dispatcher)
    assert result.failed == 1 and result.sent == 0


def test_mixed_batch(session_factory):
    ok = _make_device(session_factory, "ok-1")
    bad = _make_device(session_factory, "bad-1")
    dispatcher = InProcessDispatcher()
    dispatcher.enqueue(PushMessage(device_id=ok, title="a", body="b"))
    dispatcher.enqueue(PushMessage(device_id=bad, title="c", body="d"))

    sender = FakeSender(invalid={"bad-1"})
    with session_factory() as s:
        result = PushService(sender).process(s, dispatcher)
    assert result.sent == 1
    assert result.invalid_tokens == ["bad-1"]


def test_push_processor_tick(session_factory):
    dev_id = _make_device(session_factory, "tick-tok")
    dispatcher = InProcessDispatcher()
    dispatcher.enqueue(PushMessage(device_id=dev_id, title="t", body="b"))
    sender = FakeSender()
    tick = make_push_processor(PushService(sender), dispatcher, session_factory)

    result = tick()
    assert result.sent == 1
    assert dispatcher.pending == []
