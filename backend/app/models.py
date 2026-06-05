"""Modelli pydantic per le risposte degli endpoint.

Per spec GTFS-RT quasi tutti i campi sono opzionali: i modelli usano valori
opzionali dove la sorgente può non fornire il dato, così il codice degrada con
grazia (mezzo senza posizione, trip update senza orario, ecc.).
"""

from __future__ import annotations

import datetime as dt
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator


class Health(BaseModel):
    status: str = "ok"
    gtfs_loaded: bool = False
    routes: int = 0
    stops: int = 0
    db: bool = False
    cache: str = "memory"


class Line(BaseModel):
    line: str = Field(..., description="route_short_name, es. '10'")
    description: str | None = None
    route_ids: list[str] = Field(default_factory=list)


class Stop(BaseModel):
    stop_id: str
    code: str | None = None
    name: str
    lat: float | None = None
    lon: float | None = None


class Arrival(BaseModel):
    line: str | None = None
    headsign: str | None = None
    trip_id: str | None = None
    eta_seconds: int
    eta_minutes: int
    scheduled_ts: int


class ArrivalsResponse(BaseModel):
    stop_id: str
    name: str | None = None
    arrivals: list[Arrival] = Field(default_factory=list)


class Vehicle(BaseModel):
    vehicle_id: str | None = None
    trip_id: str | None = None
    headsign: str | None = None
    lat: float | None = None
    lon: float | None = None
    bearing: float | None = None
    speed: float | None = None
    ts: int | None = None


class VehiclesResponse(BaseModel):
    line: str
    count: int
    vehicles: list[Vehicle] = Field(default_factory=list)


class ServiceAlert(BaseModel):
    header: str | None = None
    description: str | None = None
    effect: str | None = None
    lines: list[str] = Field(default_factory=list)


class Strike(BaseModel):
    """Riga del registro MIT, normalizzata in modo difensivo.

    ``raw`` conserva l'intera riga originale: i nomi delle colonne del CSV
    possono cambiare nel tempo, quindi non perdiamo informazione.
    """

    start_date: str | None = None
    end_date: str | None = None
    sector: str | None = None
    relevance: str | None = None
    area: str | None = None
    unions: str | None = None
    category: str | None = None
    raw: dict[str, str] = Field(default_factory=dict)


class AlertsResponse(BaseModel):
    service_alerts: list[ServiceAlert] = Field(default_factory=list)
    strikes: list[Strike] = Field(default_factory=list)


# ----------------------------------------------------------------- utenti (v1)
# Per l'MVP l'identità è un device anonimo: registrato via POST /me/devices,
# poi identificato dall'header X-Device-Id nelle chiamate /me/*.


class DeviceCreate(BaseModel):
    platform: Literal["android", "ios"]
    token: str = Field(..., min_length=1, description="Token push FCM")


class DeviceOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    platform: str
    created_at: dt.datetime


class FavoriteCreate(BaseModel):
    type: Literal["stop", "line"]
    ref: str = Field(..., min_length=1, description="stop_id (es. '350') o linea (es. '10')")


class FavoriteOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    type: str
    ref: str


class SubscriptionCreate(BaseModel):
    kind: Literal["imminent", "strike"]
    stop_id: str | None = None
    line: str | None = None
    threshold_min: int | None = Field(None, ge=1, le=120)

    @model_validator(mode="after")
    def _check_required(self) -> SubscriptionCreate:
        if self.kind == "imminent":
            missing = [
                name
                for name, val in (
                    ("stop_id", self.stop_id),
                    ("line", self.line),
                    ("threshold_min", self.threshold_min),
                )
                if val is None
            ]
            if missing:
                raise ValueError(f"kind 'imminent' richiede: {', '.join(missing)}")
        elif self.kind == "strike" and not self.line:
            raise ValueError("kind 'strike' richiede 'line'")
        return self


class SubscriptionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    kind: str
    stop_id: str | None = None
    line: str | None = None
    threshold_min: int | None = None
    active: bool
