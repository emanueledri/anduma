# ROADMAP — Transito Torino

Milestone ordinate, pensate per essere eseguite una alla volta da Claude Code.
Ogni milestone ha task concreti e un criterio di "fatto". Un branch per milestone.

---

## M0 — Fondamenta backend (read-only)
Spacchettare il prototipo `torino_transit_backend.py` nella struttura modulare.

- [ ] Scaffolding `backend/` con `pyproject.toml` (deps: fastapi, uvicorn, httpx, gtfs-realtime-bindings, pydantic-settings, apscheduler; dev: pytest, ruff).
- [ ] `app/config.py`: URL feed + TTL + settings via `pydantic-settings`.
- [ ] `app/gtfs_static.py`: download/cache GTFS statico; mappa `route_short_name → route_id`.
- [ ] `app/realtime.py`: fetch+parse dei tre feed RT con cache TTL.
- [ ] `app/scioperi.py`: parser difensivo del registro MIT filtrato per Torino/Piemonte + nazionali.
- [ ] `app/models.py`: response pydantic per tutti gli endpoint.
- [ ] `app/main.py`: endpoint `/health`, `/lines`, `/stops/search`, `/stops/{id}/arrivals`, `/lines/{line}/vehicles`, `/alerts`.
- [ ] `tests/`: fixture protobuf + CSV salvate; test di parsing e di ogni endpoint **senza rete**.

**Fatto quando**: `uvicorn app.main:app` espone gli endpoint, `pytest` verde, `ruff` pulito.

## M1 — Infra & persistenza
- [ ] `infra/docker-compose.yml`: Postgres + Redis.
- [ ] `app/db.py`: sessione DB + migrazioni (Alembic). Tabelle: `devices`, `favorites`, `subscriptions`, `notified_events`.
- [ ] Cache su Redis (astrazione che in locale può restare in-memory).

**Fatto quando**: `docker compose up` avvia DB+Redis; migrazioni applicate; healthcheck DB ok.

## M2 — Utenti, preferiti, sottoscrizioni
- [ ] `POST /me/devices` (registra token FCM, device anonimo).
- [ ] CRUD `/me/favorites` (stop|line).
- [ ] CRUD `/me/subscriptions` (kind imminent|strike).
- [ ] Test CRUD su DB di test.

**Fatto quando**: un device può salvare preferiti e sottoscrizioni e rileggerli.

## M3 — Motore alert + scheduler
- [ ] `app/alerts.py`: job **imminent** (~15 s) e job **strike** (~1 h) con APScheduler.
- [ ] Deduplica via `notified_events`; logica idempotente.
- [ ] Dispatcher disaccoppiato (coda in-process per iniziare).
- [ ] Test della logica con feed/strike mockati (nessuna rete, nessun invio reale).

**Fatto quando**: con feed simulati, gli eventi corretti vengono accodati una sola volta.

## M4 — Push FCM/APNs
- [ ] `app/push.py`: invio via Firebase Admin SDK; chiavi da env.
- [ ] Collegare il dispatcher di M3 al push reale.
- [ ] Gestione token invalidi (cleanup).

**Fatto quando**: una sottoscrizione di test genera una push su un device reale.
*Richiede account Firebase + service account key (configurazione esterna).*

## M5 — WebSocket mappa
- [ ] `WS /ws/lines/{line}`: push posizioni ogni ~3–5 s dalla cache RT condivisa.
- [ ] Backpressure/cleanup connessioni; fallback REST documentato.

**Fatto quando**: un client di test riceve aggiornamenti periodici su una linea.

## M6 — Client Flutter (MVP)
- [ ] Progetto `mobile/` + client API tipizzato.
- [ ] Schermata **Ricerca/Arrivi**: cerca fermata → lista arrivi con auto-refresh.
- [ ] Schermata **Mappa**: `flutter_map` + tile OSM, marker mezzi animati via WS (fallback polling).
- [ ] Schermata **Preferiti**: salva fermate/linee; "casa" coi prossimi passaggi.
- [ ] Schermata **Avvisi**: avvisi GTT + scioperi.
- [ ] Schermata **Informazioni/Fonti** coi crediti (CC BY GTT, MIT, OSM).

**Fatto quando**: l'app gira su Android/iOS e usa solo la nostra API.

## M7 — Client Flutter (alert) + rifinitura
- [ ] Registrazione device token FCM + gestione permessi notifiche.
- [ ] UI per creare/gestire alert (imminent, strike) dai preferiti.
- [ ] Ricezione e deep-link delle push alla schermata giusta.
- [ ] Stati vuoti/errore/offline; accessibilità; icone direzione di marcia.

**Fatto quando**: un alert creato dall'app arriva come push e apre la vista corretta.

## M8 — Distribuzione
- [ ] Deploy backend (container) + scheduler attivo + monitoraggio basilare.
- [ ] Build store: privacy policy, schede, crediti dati.
- [ ] (Opzionale) beta TestFlight / Play Internal Testing.

---

### Ordine consigliato
M0 → M1 → M2 → M3 → M4 in sequenza (backend completo end-to-end), poi M5; il client M6→M7 può
iniziare in parallelo appena M0 è online (basta la API read-only per mappa e arrivi).

### Promemoria trasversali
- Nessun test deve toccare la rete: usare le fixture.
- Polling feed solo backend + cache condivisa.
- Crediti CC BY 4.0 (GTT), MIT, OSM presenti nell'app.
