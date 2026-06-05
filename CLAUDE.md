# Transito Torino — contesto progetto

> Nome di lavoro provvisorio. App mobile per il trasporto pubblico di Torino (GTT):
> arrivi in fermata in tempo reale, posizione live di bus/tram sul percorso, preferiti
> e notifiche push per passaggi imminenti e scioperi. Costruita su open data ufficiali.

Questo file è il contesto di partenza per Claude Code. I dettagli stanno in `docs/`:
- `docs/SPEC.md` — specifica prodotto + contratto API
- `docs/DATA_SOURCES.md` — feed, formati, licenze, trappole note
- `docs/ROADMAP.md` — milestone in task concreti e ordinati

## Stack

- **Backend**: Python 3.12, FastAPI, httpx, `gtfs-realtime-bindings` (protobuf).
- **Cache**: in-memory per lo sviluppo, Redis in produzione (polling dei feed centralizzato).
- **DB**: SQLite per iniziare, PostgreSQL in produzione (utenti, preferiti, sottoscrizioni).
- **Scheduler**: APScheduler per valutare le sottoscrizioni e accodare le notifiche.
- **Push**: Firebase Cloud Messaging (Android/iOS); APNs dietro FCM.
- **Client**: Flutter (un solo codice per Android/iOS). Mappa con `flutter_map` + tile OSM.
  - Scelta consigliata, non obbligata: se si preferisce React Native o PWA, il backend resta identico.

## Struttura repo (target)

```
.
├── CLAUDE.md
├── docs/
│   ├── SPEC.md
│   ├── DATA_SOURCES.md
│   └── ROADMAP.md
├── backend/
│   ├── app/
│   │   ├── main.py            # FastAPI app + router
│   │   ├── config.py          # URL feed, TTL, settings (pydantic-settings)
│   │   ├── gtfs_static.py     # download/cache GTFS statico
│   │   ├── realtime.py        # fetch/parse feed GTFS-RT
│   │   ├── scioperi.py        # registro scioperi MIT
│   │   ├── alerts.py          # motore alert + scheduler
│   │   ├── push.py            # dispatcher FCM/APNs
│   │   ├── models.py          # modelli pydantic (response) + ORM
│   │   └── db.py              # sessione DB, migrazioni
│   └── tests/
├── mobile/                    # progetto Flutter
└── infra/                     # docker-compose (postgres, redis), deploy
```

Punto di partenza già pronto: il prototipo read-only `torino_transit_backend.py` (allegato alla
conversazione) contiene cache TTL, loader GTFS statico, parsing dei tre feed RT, filtro scioperi
MIT e gli endpoint `/lines`, `/stops/search`, `/stops/{id}/arrivals`, `/lines/{line}/vehicles`,
`/alerts`. Va spacchettato nei moduli di `backend/app/` come Milestone 0 (vedi ROADMAP).

## Comandi di sviluppo

```bash
# Backend
cd backend
python -m venv .venv && source .venv/bin/activate
pip install -e ".[dev]"          # fastapi httpx uvicorn gtfs-realtime-bindings apscheduler ...
uvicorn app.main:app --reload    # docs interattive su http://127.0.0.1:8000/docs
pytest                           # i test NON devono dipendere dalla rete (vedi sotto)
ruff check . && ruff format .

# Infra locale
docker compose -f infra/docker-compose.yml up -d   # postgres + redis

# Mobile
cd mobile && flutter pub get && flutter run
```

## Convenzioni

- Python con type hints ovunque; formattazione e lint con **ruff**; response tipizzate con **pydantic**.
- Niente segreti nel repo: FCM key e DSN del DB via variabili d'ambiente / `.env` non versionato.
- Commit piccoli e tematici; un branch per milestone.

## Vincoli importanti (non negoziabili)

- **Il polling dei feed lo fa SOLO il backend**, con cache condivisa. Mai dal singolo telefono
  (rate limit + batteria). Il client parla esclusivamente con la nostra API.
- **I feed RT sono protobuf binari** (non JSON): vanno parsati con `gtfs-realtime-bindings`.
- Il feed RT usa `route_id`/`trip_id` interni: per filtrare "linea 10" serve mappare
  `route_short_name` → `route_id` dal GTFS statico (`routes.txt`). Vedi DATA_SOURCES.
- **Licenza CC BY 4.0**: citare "Città di Torino / GTT" nei crediti dell'app. Scioperi: fonte MIT.
- **I domini dei feed possono non essere raggiungibili da CI o da alcune reti.** Tutti i test
  devono usare fixture/mock di payload protobuf e CSV, mai chiamate di rete reali.
- Il link di download del GTFS statico può cambiare: tenerlo in `config.py`, non sparso nel codice.
