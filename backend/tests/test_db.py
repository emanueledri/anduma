"""Test dei modelli ORM e della sessione su un DB di test (SQLite temporaneo)."""

from __future__ import annotations

import datetime as dt

import pytest
from sqlalchemy import create_engine, select
from sqlalchemy.orm import sessionmaker

from app.db import (
    Base,
    Device,
    Favorite,
    NotifiedEvent,
    Subscription,
    db_healthcheck,
)


@pytest.fixture
def session_factory(tmp_path):
    engine = create_engine(
        f"sqlite:///{tmp_path / 'test.db'}", connect_args={"check_same_thread": False}
    )
    Base.metadata.create_all(engine)
    return sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


def test_device_with_favorites_and_subscriptions(session_factory):
    with session_factory() as s:
        dev = Device(platform="android", fcm_token="tok-123")
        dev.favorites.append(Favorite(type="stop", ref="350"))
        dev.favorites.append(Favorite(type="line", ref="10"))
        dev.subscriptions.append(
            Subscription(kind="imminent", stop_id="350", line="10", threshold_min=5)
        )
        dev.subscriptions.append(Subscription(kind="strike", line="10"))
        s.add(dev)
        s.commit()
        dev_id = dev.id

    with session_factory() as s:
        dev = s.get(Device, dev_id)
        assert dev.platform == "android"
        assert {f.ref for f in dev.favorites} == {"350", "10"}
        kinds = {sub.kind for sub in dev.subscriptions}
        assert kinds == {"imminent", "strike"}
        imminent = next(sub for sub in dev.subscriptions if sub.kind == "imminent")
        assert imminent.threshold_min == 5 and imminent.active is True


def test_cascade_delete_device(session_factory):
    with session_factory() as s:
        dev = Device(platform="ios", fcm_token="tok-xyz")
        dev.favorites.append(Favorite(type="stop", ref="400"))
        dev.subscriptions.append(Subscription(kind="strike", line="55"))
        s.add(dev)
        s.commit()
        s.delete(dev)
        s.commit()

    with session_factory() as s:
        assert s.scalars(select(Device)).all() == []
        assert s.scalars(select(Favorite)).all() == []
        assert s.scalars(select(Subscription)).all() == []


def test_notified_event_dedup(session_factory):
    with session_factory() as s:
        dev = Device(platform="android", fcm_token="tok-evt")
        sub = Subscription(kind="imminent", stop_id="350", line="10", threshold_min=5)
        dev.subscriptions.append(sub)
        s.add(dev)
        s.commit()
        expires = dt.datetime.now(dt.UTC) + dt.timedelta(minutes=30)
        s.add(NotifiedEvent(subscription_id=sub.id, dedup_key="trip-T1", expires_at=expires))
        s.commit()

    with session_factory() as s:
        ev = s.scalars(select(NotifiedEvent).where(NotifiedEvent.dedup_key == "trip-T1")).one()
        assert ev.subscription.stop_id == "350"


def test_unique_fcm_token(session_factory):
    from sqlalchemy.exc import IntegrityError

    with session_factory() as s:
        s.add(Device(platform="android", fcm_token="dup"))
        s.commit()
    with session_factory() as s:
        s.add(Device(platform="ios", fcm_token="dup"))
        with pytest.raises(IntegrityError):
            s.commit()


def test_db_healthcheck(session_factory):
    assert db_healthcheck(session_factory) is True
