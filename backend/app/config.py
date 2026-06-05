"""Configurazione centralizzata: URL dei feed, TTL della cache, settings.

Tutti gli URL stanno qui (non sparsi nel codice): il link di download del GTFS
statico e gli endpoint GTT/MIT possono cambiare nel tempo. Override via variabili
d'ambiente con prefisso ``TT_`` o file ``.env`` (vedi pydantic-settings).
"""

from __future__ import annotations

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Settings dell'applicazione, sovrascrivibili da env (prefisso ``TT_``)."""

    model_config = SettingsConfigDict(env_prefix="TT_", env_file=".env", extra="ignore")

    # --- GTFS statico (orari, fermate, percorsi) ---
    # Trappola nota: il link diretto di download dello ZIP può cambiare (404).
    # Se cambia, aggiornare QUI (o via env TT_GTFS_STATIC_URL), non nel codice.
    gtfs_static_url: str = "http://aperto.comune.torino.it/dataset/feed-gtfs-trasporti-gtt"

    # --- GTFS-Realtime (protobuf binario, NON JSON) ---
    rt_vehicle_positions_url: str = (
        "http://percorsieorari.gtt.to.it/das_gtfsrt/vehicle_position.aspx"
    )
    rt_trip_updates_url: str = "http://percorsieorari.gtt.to.it/das_gtfsrt/trip_update.aspx"
    rt_alerts_url: str = "http://percorsieorari.gtt.to.it/das_gtfsrt/alerts.aspx"

    # --- Scioperi (registro MIT) ---
    strikes_csv_url: str = (
        "https://dati.mit.gov.it/catalog/dataset/scioperi-dei-trasporti/resource/"
        "6838feb1-1f3d-40dc-845f-d304088a92cd/download/scioperi.csv"
    )

    # --- TTL cache (secondi) ---
    ttl_vehicle_positions: int = 12
    ttl_trip_updates: int = 12
    ttl_alerts: int = 60
    ttl_strikes: int = 3600
    ttl_gtfs_static: int = 24 * 3600

    # --- HTTP ---
    http_timeout: float = 15.0

    # --- Persistenza ---
    # SQLite per iniziare; in produzione PostgreSQL via env, es.
    #   TT_DATABASE_URL=postgresql+psycopg://user:pass@host:5432/transito
    database_url: str = "sqlite:///./transito.db"
    db_echo: bool = False

    # --- Cache ---
    # Vuoto → cache in-memory (sviluppo). In produzione: redis://host:6379/0
    redis_url: str = ""

    # --- Scheduler / motore alert ---
    # Disattivato di default: i job non partono (né fanno polling) finché non
    # viene abilitato esplicitamente (es. nel processo di produzione).
    scheduler_enabled: bool = False
    imminent_interval_s: int = 15
    strike_interval_s: int = 3600

    # --- Geografia scioperi rilevanti per Torino ---
    strike_regions: tuple[str, ...] = ("piemonte", "torino")
    # Settori/rilevanze considerati "nazionali" → sempre inclusi per il TPL.
    strike_national_markers: tuple[str, ...] = ("nazionale", "generale")


@lru_cache
def get_settings() -> Settings:
    """Istanza singleton delle settings (cache per processo)."""
    return Settings()
