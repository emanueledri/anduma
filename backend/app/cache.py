"""Astrazione di cache a TTL: in-memory in sviluppo, Redis in produzione.

Il polling dei feed è centralizzato sul backend e i payload (bytes protobuf,
CSV) vengono messi qui con un TTL. In locale basta ``InMemoryCache``; se è
configurato ``redis_url`` si usa ``RedisCache`` con la stessa interfaccia.
"""

from __future__ import annotations

import time
from dataclasses import dataclass
from typing import Protocol

from .config import Settings, get_settings


class Cache(Protocol):
    """Interfaccia minima: byte con TTL in secondi."""

    def get(self, key: str) -> bytes | None: ...
    def set(self, key: str, value: bytes, ttl: int) -> None: ...


@dataclass
class _Entry:
    value: bytes
    expires_at: float


class InMemoryCache:
    """Cache di processo con scadenza. Adatta allo sviluppo e ai test."""

    def __init__(self) -> None:
        self._store: dict[str, _Entry] = {}

    def get(self, key: str, now: float | None = None) -> bytes | None:
        now_ts = now if now is not None else time.time()
        entry = self._store.get(key)
        if entry is None:
            return None
        if entry.expires_at <= now_ts:
            self._store.pop(key, None)
            return None
        return entry.value

    def set(self, key: str, value: bytes, ttl: int, now: float | None = None) -> None:
        now_ts = now if now is not None else time.time()
        self._store[key] = _Entry(value, now_ts + ttl)


class RedisCache:
    """Cache su Redis (chiavi byte con ``SETEX``)."""

    def __init__(self, url: str) -> None:
        import redis  # import locale: dipendenza usata solo in questo backend

        self._client = redis.Redis.from_url(url)

    def get(self, key: str) -> bytes | None:
        return self._client.get(key)

    def set(self, key: str, value: bytes, ttl: int) -> None:
        self._client.setex(key, ttl, value)

    def ping(self) -> bool:
        try:
            return bool(self._client.ping())
        except Exception:
            return False


def get_cache(settings: Settings | None = None) -> Cache:
    """Factory: Redis se ``redis_url`` è configurato, altrimenti in-memory."""
    settings = settings or get_settings()
    if settings.redis_url:
        return RedisCache(settings.redis_url)
    return InMemoryCache()


__all__ = ["Cache", "InMemoryCache", "RedisCache", "get_cache"]
