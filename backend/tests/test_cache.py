"""Test della cache in-memory a TTL (la variante Redis richiede un server)."""

from __future__ import annotations

from app.cache import InMemoryCache, get_cache
from app.config import Settings


def test_set_get_roundtrip():
    cache = InMemoryCache()
    cache.set("k", b"payload", ttl=30, now=1000.0)
    assert cache.get("k", now=1010.0) == b"payload"


def test_expiry():
    cache = InMemoryCache()
    cache.set("k", b"v", ttl=10, now=1000.0)
    # Ancora valida appena prima della scadenza...
    assert cache.get("k", now=1009.9) == b"v"
    # ...e assente allo scadere (>=).
    assert cache.get("k", now=1010.0) is None


def test_missing_key():
    assert InMemoryCache().get("nope") is None


def test_factory_defaults_to_memory():
    cache = get_cache(Settings(redis_url=""))
    assert isinstance(cache, InMemoryCache)
