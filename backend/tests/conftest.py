"""Fixture pytest comuni: dati salvati + provider fake (zero rete)."""

from __future__ import annotations

from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.gtfs_static import GtfsStatic
from app.main import app, get_provider

FIX = Path(__file__).parent / "fixtures"


@pytest.fixture(scope="session")
def gtfs() -> GtfsStatic:
    return GtfsStatic.from_zip_bytes((FIX / "gtfs_static.zip").read_bytes())


@pytest.fixture(scope="session")
def vehicle_positions_bytes() -> bytes:
    return (FIX / "vehicle_positions.pb").read_bytes()


@pytest.fixture(scope="session")
def trip_updates_bytes() -> bytes:
    return (FIX / "trip_updates.pb").read_bytes()


@pytest.fixture(scope="session")
def alerts_bytes() -> bytes:
    return (FIX / "alerts.pb").read_bytes()


@pytest.fixture(scope="session")
def strikes_csv() -> str:
    return (FIX / "scioperi.csv").read_text(encoding="utf-8")


class FakeProvider:
    """Provider che legge le fixture salvate (nessuna chiamata di rete)."""

    def __init__(self, gtfs: GtfsStatic):
        self._gtfs = gtfs

    def gtfs(self) -> GtfsStatic:
        return self._gtfs

    def vehicle_positions_bytes(self) -> bytes:
        return (FIX / "vehicle_positions.pb").read_bytes()

    def trip_updates_bytes(self) -> bytes:
        return (FIX / "trip_updates.pb").read_bytes()

    def alerts_bytes(self) -> bytes:
        return (FIX / "alerts.pb").read_bytes()

    def strikes_csv(self) -> str:
        return (FIX / "scioperi.csv").read_text(encoding="utf-8")


@pytest.fixture
def client(gtfs: GtfsStatic):
    provider = FakeProvider(gtfs)
    app.dependency_overrides[get_provider] = lambda: provider
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()
