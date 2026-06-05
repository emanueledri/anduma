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

## Motore alert + scheduler (M3)

Due valutazioni periodiche (APScheduler), disattivate di default:

- **imminent** (~15 s): se un mezzo della linea sottoscritta è entro `threshold_min`
  dalla fermata e non già notificato per quel `trip_id` → accoda una push.
- **strike** (~1 h): per ogni nuovo sciopero rilevante per Torino → accoda una push
  alle sottoscrizioni `strike`.

La deduplica è idempotente (tabella `notified_events`, chiave `(subscription_id,
dedup_key)` con TTL). Il dispatcher è disaccoppiato (coda in-process `InProcessDispatcher`):
qui si accoda soltanto, l'invio reale (FCM/APNs) arriva in M4.

```bash
# Abilita lo scheduler nel processo (di default è spento, nessun polling):
export TT_SCHEDULER_ENABLED=true
export TT_IMMINENT_INTERVAL_S=15
export TT_STRIKE_INTERVAL_S=3600
```

## Push FCM/APNs (M4)

Il `PushService` svuota la coda del dispatcher (M3), risolve il `device_id` nel
token FCM, invia via **Firebase Admin SDK**, e in caso di token non più valido
rimuove il device (cleanup, cascade su preferiti/sottoscrizioni). APNs è gestito
da FCM dietro le quinte.

Richiede una **service account** Firebase (config esterna, vedi `secrets/README.md`):

```bash
export TT_FCM_ENABLED=true
export TT_FCM_CREDENTIALS_FILE=secrets/firebase-admin.json
export TT_SCHEDULER_ENABLED=true   # il job 'push' gira solo con lo scheduler attivo
export TT_PUSH_INTERVAL_S=10
```

Senza chiave (`TT_FCM_ENABLED=false`, default) il backend funziona normalmente:
gli alert vengono solo accodati, non inviati. I test usano un sender fake.

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
