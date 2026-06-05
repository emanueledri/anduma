"""Provider dati: astrazione tra gli endpoint e le sorgenti (rete/cache).

Gli endpoint dipendono da ``DataProvider`` (interfaccia minima). In produzione
si usa ``LiveProvider`` (scarica GTFS + feed RT + CSV con cache TTL); nei test si
inietta un fake che legge le fixture, così nessun test tocca la rete.
"""

from __future__ import annotations

import time
from typing import Protocol

from .config import Settings, get_settings
from .gtfs_static import GtfsStatic, download_zip_bytes
from .realtime import FeedFetcher
from .scioperi import download_strikes_csv


class DataProvider(Protocol):
    def gtfs(self) -> GtfsStatic: ...
    def vehicle_positions_bytes(self) -> bytes: ...
    def trip_updates_bytes(self) -> bytes: ...
    def alerts_bytes(self) -> bytes: ...
    def strikes_csv(self) -> str: ...


class LiveProvider:
    """Provider di produzione: rete + cache TTL. Tollera sorgenti irraggiungibili."""

    def __init__(self, settings: Settings | None = None):
        self._settings = settings or get_settings()
        self._fetcher = FeedFetcher(self._settings)
        self._gtfs: GtfsStatic | None = None
        self._gtfs_expires_at: float = 0.0
        self._strikes: str = ""
        self._strikes_expires_at: float = 0.0

    def gtfs(self) -> GtfsStatic:
        now = time.time()
        if self._gtfs is not None and self._gtfs_expires_at > now:
            return self._gtfs
        try:
            data = download_zip_bytes(self._settings)
            self._gtfs = GtfsStatic.from_zip_bytes(data)
            self._gtfs_expires_at = now + self._settings.ttl_gtfs_static
        except Exception:
            # Sorgente irraggiungibile: mantieni lo snapshot precedente (o vuoto).
            if self._gtfs is None:
                self._gtfs = GtfsStatic()
        return self._gtfs

    def vehicle_positions_bytes(self) -> bytes:
        return self._fetcher.vehicle_positions()

    def trip_updates_bytes(self) -> bytes:
        return self._fetcher.trip_updates()

    def alerts_bytes(self) -> bytes:
        return self._fetcher.alerts()

    def strikes_csv(self) -> str:
        now = time.time()
        if self._strikes_expires_at > now:
            return self._strikes
        try:
            self._strikes = download_strikes_csv(self._settings)
            self._strikes_expires_at = now + self._settings.ttl_strikes
        except Exception:
            pass  # mantieni l'ultimo snapshot disponibile
        return self._strikes

    def close(self) -> None:
        self._fetcher.close()


__all__ = ["DataProvider", "LiveProvider"]
