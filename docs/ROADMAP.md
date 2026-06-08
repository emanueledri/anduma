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

## M6 — Client Flutter (MVP) ✅
- [x] Progetto `mobile/` + client API tipizzato.
- [x] Schermata **Ricerca/Arrivi**: cerca fermata → lista arrivi con auto-refresh.
- [x] Schermata **Mappa**: `flutter_map` + tile OSM, marker mezzi animati via WS (fallback polling).
- [x] Schermata **Preferiti**: `FavoritesStore` locale (SharedPreferences); salva fermate/linee con stella da Arrivi e Mappa; card con arrivi inline auto-refresh; swipe-to-dismiss.
- [x] Schermata **Avvisi**: avvisi GTT + scioperi; pull-to-refresh corretto.
- [x] Schermata **Informazioni/Fonti** coi crediti (CC BY GTT, MIT, OSM).

**Validato**: `flutter analyze` 0 warning; `flutter build apk --debug` ok; app testata su
emulatore Pixel 9 (Android 15, API 35); dati reali GTT caricati (205 avvisi, 1543 scioperi).

Bug risolti durante il testing:
- `setState(() => _future = next)` restituiva Future come callback value → cambiato in block body.
- `_reload()` non era `async` → `RefreshIndicator` non aspettava il completamento.
- `FeedFetcher._get()` non catturava `httpx.TransportError`/`HTTPStatusError` → crash 500 → ora 503.
- URL feed GTT usavano `http://` → timeout silenzioso → corretti in `https://` (server HTTPS-only).
- Aggiunto `User-Agent: Mozilla/5.0` al client httpx (alcuni endpoint GTT filtrano per UA).

## M7 — Client Flutter (alert) + rifinitura
- [x] Registrazione device token FCM + gestione permessi notifiche (`PushManager`).
- [x] UI per creare/gestire alert (imminent, strike) dai preferiti (campana + bottom sheet).
- [x] Ricezione e deep-link delle push alla schermata giusta (Arrivi fermata / Avvisi).
- [x] Stati vuoti/errore/offline; degrado se Firebase non configurato; icone modalità reali.

**Fatto quando**: un alert creato dall'app arriva come push e apre la vista corretta.
> Codice completo e degrada con grazia senza Firebase. Test end-to-end richiede
> `google-services.json` + backend con `TT_FCM_ENABLED`/`TT_SCHEDULER_ENABLED` — vedi
> [docs/FIREBASE_SETUP.md](FIREBASE_SETUP.md).

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
