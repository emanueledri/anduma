# Transito Torino — backend

Backend read-only (Milestone 0) per il trasporto pubblico GTT di Torino: arrivi in
fermata, posizioni live dei mezzi e avvisi/scioperi, su open data ufficiali.

## Sviluppo

```bash
cd backend
python -m venv .venv && source .venv/bin/activate
pip install -e ".[dev]"
uvicorn app.main:app --reload   # docs: http://127.0.0.1:8000/docs
pytest                          # nessun test tocca la rete
ruff check . && ruff format .
```

## Endpoint (M0)

- `GET /health`
- `GET /lines`
- `GET /stops/search?q=&limit=`
- `GET /stops/{stop_id}/arrivals?line=`
- `GET /lines/{line}/vehicles`
- `GET /alerts?line=`

Tutti i dati provengono dai feed GTT (CC BY 4.0 — "Città di Torino / GTT") e dal
registro scioperi MIT. Vedi `../docs/DATA_SOURCES.md`.

## Utenti, preferiti, sottoscrizioni (M2)

Identità MVP: device anonimo. Si registra con `POST /me/devices` e poi ci si
identifica con l'header `X-Device-Id` nelle altre chiamate `/me/*`.

- `POST /me/devices` — registra device `{platform, token}` (idempotente sul token)
- `GET|POST /me/favorites` + `DELETE /me/favorites/{id}` — preferiti `{type: stop|line, ref}`
- `GET|POST /me/subscriptions` + `DELETE /me/subscriptions/{id}` — alert `{kind: imminent|strike, ...}`

## Infra & persistenza (M1)

Stack locale (Postgres + Redis) via docker-compose:

```bash
docker compose -f ../infra/docker-compose.yml up -d   # postgres + redis con healthcheck
```

Configurazione (env con prefisso `TT_`, vedi `.env.example`):

```bash
# Default sviluppo: SQLite + cache in-memory (nessun servizio esterno richiesto).
# Con lo stack docker-compose:
export TT_DATABASE_URL=postgresql+psycopg://transito:transito@localhost:5432/transito
export TT_REDIS_URL=redis://localhost:6379/0
```

Migrazioni (Alembic):

```bash
alembic upgrade head            # applica lo schema (devices, favorites, subscriptions, notified_events)
alembic revision --autogenerate -m "descrizione"   # nuova migrazione dai modelli ORM
```

`GET /health` riporta `db` (SELECT 1) e `cache` (`memory` | `redis` | `redis-down`).
