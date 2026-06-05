"""Sessione DB e modelli ORM (utenti, preferiti, sottoscrizioni, eventi notificati).

SQLite per iniziare, PostgreSQL in produzione (stesso schema, driver via URL).
Le migrazioni sono gestite da Alembic (vedi ``migrations/``); ``Base.metadata``
qui è la sorgente di verità per l'autogenerazione.
"""

from __future__ import annotations

import datetime as dt
from collections.abc import Iterator

from sqlalchemy import (
    Boolean,
    DateTime,
    ForeignKey,
    Integer,
    String,
    create_engine,
    text,
)
from sqlalchemy.orm import (
    DeclarativeBase,
    Mapped,
    Session,
    mapped_column,
    relationship,
    sessionmaker,
)

from .config import Settings, get_settings


class Base(DeclarativeBase):
    pass


def _utcnow() -> dt.datetime:
    return dt.datetime.now(dt.UTC)


class Device(Base):
    __tablename__ = "devices"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    platform: Mapped[str] = mapped_column(String(16))  # 'android' | 'ios'
    fcm_token: Mapped[str] = mapped_column(String(512), unique=True)
    created_at: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True), default=_utcnow)

    favorites: Mapped[list[Favorite]] = relationship(
        back_populates="device", cascade="all, delete-orphan"
    )
    subscriptions: Mapped[list[Subscription]] = relationship(
        back_populates="device", cascade="all, delete-orphan"
    )


class Favorite(Base):
    __tablename__ = "favorites"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    device_id: Mapped[int] = mapped_column(ForeignKey("devices.id", ondelete="CASCADE"), index=True)
    type: Mapped[str] = mapped_column(String(8))  # 'stop' | 'line'
    ref: Mapped[str] = mapped_column(String(64))  # stop_id o line short_name

    device: Mapped[Device] = relationship(back_populates="favorites")


class Subscription(Base):
    __tablename__ = "subscriptions"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    device_id: Mapped[int] = mapped_column(ForeignKey("devices.id", ondelete="CASCADE"), index=True)
    kind: Mapped[str] = mapped_column(String(16))  # 'imminent' | 'strike'
    stop_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    line: Mapped[str | None] = mapped_column(String(64), nullable=True)
    threshold_min: Mapped[int | None] = mapped_column(Integer, nullable=True)
    active: Mapped[bool] = mapped_column(Boolean, default=True)

    device: Mapped[Device] = relationship(back_populates="subscriptions")
    notified_events: Mapped[list[NotifiedEvent]] = relationship(
        back_populates="subscription", cascade="all, delete-orphan"
    )


class NotifiedEvent(Base):
    """Deduplica delle notifiche: una riga per (subscription, dedup_key)."""

    __tablename__ = "notified_events"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    subscription_id: Mapped[int] = mapped_column(
        ForeignKey("subscriptions.id", ondelete="CASCADE"), index=True
    )
    dedup_key: Mapped[str] = mapped_column(String(128), index=True)
    expires_at: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True))

    subscription: Mapped[Subscription] = relationship(back_populates="notified_events")


# --------------------------------------------------------------- engine/session
def make_engine(settings: Settings | None = None):
    settings = settings or get_settings()
    connect_args = {}
    if settings.database_url.startswith("sqlite"):
        # SQLite + thread di FastAPI/scheduler.
        connect_args["check_same_thread"] = False
    return create_engine(settings.database_url, echo=settings.db_echo, connect_args=connect_args)


# Engine/sessionmaker di default del processo (override-abili nei test).
engine = make_engine()
SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


def get_session() -> Iterator[Session]:
    """Dependency FastAPI: una sessione per richiesta."""
    session = SessionLocal()
    try:
        yield session
    finally:
        session.close()


def db_healthcheck(session_factory: sessionmaker[Session] | None = None) -> bool:
    """True se il DB risponde a un ``SELECT 1``."""
    factory = session_factory or SessionLocal
    try:
        with factory() as s:
            s.execute(text("SELECT 1"))
        return True
    except Exception:
        return False


__all__ = [
    "Base",
    "Device",
    "Favorite",
    "Subscription",
    "NotifiedEvent",
    "make_engine",
    "engine",
    "SessionLocal",
    "get_session",
    "db_healthcheck",
]
