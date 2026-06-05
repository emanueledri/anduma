# Transito Torino

> Nome di lavoro provvisorio.

App mobile per il trasporto pubblico di Torino (GTT): **arrivi in fermata in tempo
reale**, **posizione live** di bus e tram sul percorso, **preferiti** e **notifiche
push** per passaggi imminenti e scioperi. Costruita interamente su open data ufficiali.

L'obiettivo è un'app più completa e fluida delle soluzioni esistenti (MATO Live Bus,
GTT TO Move), con — elemento distintivo — gli **alert push** per il passaggio imminente
di una linea a una fermata e per gli **scioperi** che toccano Torino/Piemonte.

## Stato

| Milestone | Descrizione | Stato |
|-----------|-------------|:-----:|
| **M0** | Fondamenta backend read-only (linee, fermate, arrivi, mezzi, avvisi) | ✅ |
| **M1** | Infra & persistenza (Postgres, Redis, migrazioni Alembic) | ✅ |
| **M2** | Utenti, preferiti, sottoscrizioni (`/me/*`, device anonimo) | ✅ |
| **M3** | Motore alert + scheduler (APScheduler, dedup idempotente) | ✅ |
| **M4** | Push FCM/APNs (Firebase Admin SDK, cleanup token) | ✅ * |
| M5 | WebSocket mappa | ⬜ |
| M6–M7 | Client Flutter | ⬜ |
| M8 | Distribuzione | ⬜ |

La roadmap dettagliata è in [`docs/ROADMAP.md`](docs/ROADMAP.md).
\* M4: codice e test (mock) completi; l'invio reale richiede una service account
Firebase (config esterna) e un device token vero (dall'app, M7).

## Architettura

```
Open data (GTFS statico + GTFS-RT GTT + registro scioperi MIT)
        │
        ▼
Backend Python (FastAPI)  ── polling centralizzato + cache TTL ──┐
  • ingestion feed (solo backend, mai dal telefono)             │
  • API REST/WebSocket                                          │
  • motore alert + scheduler → push FCM/APNs                    │
        │                                                       │
        ▼                                                       │
Client Flutter (mappa, arrivi, preferiti) ──────────────────────┘
  parla esclusivamente con la nostra API
```

**Vincolo chiave:** il polling dei feed lo fa **solo il backend**, con cache condivisa
(rate limit + batteria). I feed RT sono **protobuf binari**, non JSON.

## Stack

- **Backend**: Python 3.12, FastAPI, httpx, `gtfs-realtime-bindings` (protobuf), pydantic.
- **Cache**: in-memory in sviluppo, Redis in produzione.
- **DB**: SQLite per iniziare, PostgreSQL in produzione.
- **Scheduler**: APScheduler. **Push**: Firebase Cloud Messaging (APNs dietro FCM).
- **Client**: Flutter, mappa con `flutter_map` + tile OpenStreetMap.

## Avvio rapido (backend)

```bash
cd backend
python -m venv .venv && source .venv/bin/activate
pip install -e ".[dev]"
uvicorn app.main:app --reload     # docs interattive: http://127.0.0.1:8000/docs
pytest                            # 25 test, nessuno tocca la rete
ruff check . && ruff format .
```

### Endpoint disponibili (M0)

| Metodo | Path | Descrizione |
|--------|------|-------------|
| GET | `/health` | stato + GTFS caricato |
| GET | `/lines` | elenco linee |
| GET | `/stops/search?q=&limit=` | ricerca fermate per nome/codice palina |
| GET | `/stops/{stop_id}/arrivals?line=` | arrivi in tempo reale |
| GET | `/lines/{line}/vehicles` | posizioni live dei mezzi |
| GET | `/alerts?line=` | avvisi GTT + scioperi MIT |

Dettaglio del contratto API in [`docs/SPEC.md`](docs/SPEC.md).

## Struttura del repo

```
.
├── CLAUDE.md            # contesto progetto per Claude Code
├── docs/                # SPEC, DATA_SOURCES, ROADMAP
├── backend/             # app FastAPI + test (vedi backend/README.md)
├── mobile/              # progetto Flutter (da M6)
└── infra/               # docker-compose, deploy (da M1)
```

## Sviluppato con Claude Code

Questo progetto è sviluppato con l'assistenza di **[Claude Code](https://claude.com/claude-code)**,
la CLI agentica di Anthropic. Scaffolding del backend, parser dei feed, suite di test e
documentazione sono stati prodotti iterativamente in coppia con l'agente, seguendo le
milestone di [`docs/ROADMAP.md`](docs/ROADMAP.md) (un branch e una review per milestone).
Il file [`CLAUDE.md`](CLAUDE.md) fornisce all'agente il contesto, lo stack e i vincoli
non negoziabili del progetto.

## Dati e licenze

- **Feed GTT** (GTFS statico + Realtime): **CC BY 4.0** → credito *"Città di Torino / GTT"*.
- **Scioperi**: dati **MIT — Osservatorio sui Conflitti Sindacali**.
- **Mappa**: tile **OpenStreetMap** → *"© OpenStreetMap contributors"*.

Tutte le sorgenti, con formati e trappole note, sono documentate in
[`docs/DATA_SOURCES.md`](docs/DATA_SOURCES.md). I crediti compariranno in una schermata
"Informazioni / Fonti dati" dell'app.

## Licenza

Codice: MIT. I dati restano soggetti alle rispettive licenze sopra.
