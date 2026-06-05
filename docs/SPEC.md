# SPEC — Transito Torino

Specifica prodotto e tecnica. Riferimento per implementazione e test.

## 1. Obiettivo

App mobile per muoversi col trasporto pubblico GTT a Torino, più completa delle soluzioni
esistenti (MATO Live Bus, GTT TO Move): mappa mezzi fluida, arrivi in tempo reale, preferiti
e — elemento distintivo — notifiche push per passaggi imminenti e per scioperi.

## 2. Funzionalità

### MVP
1. **Ricerca fermata** per nome o codice palina.
2. **Arrivi in fermata** in tempo reale (linea, capolinea, minuti all'arrivo), auto-refresh.
3. **Mappa live** dei mezzi di una linea, con direzione di marcia.
4. **Avvisi di servizio** GTT (deviazioni/guasti) e **scioperi** che riguardano Torino/Piemonte.

### v1 (completa)
5. **Preferiti**: fermate e linee salvate, schermata "casa" con i prossimi passaggi dei preferiti.
6. **Alert passaggio imminente**: push quando un mezzo di linea X è a ≤ N minuti dalla fermata Y.
7. **Alert sciopero**: push quando viene proclamato/si avvicina uno sciopero che tocca le linee preferite.
8. **Calcolo a colpo d'occhio** della prossima corsa utile per una coppia (fermata, linea).

### Idee future (non vincolanti)
- Storicizzazione passaggi → statistiche di puntualità/regolarità per linea e tratta.
- Stima congestione/velocità per tratta dalle posizioni successive + `shapes.txt`.
- Pianificazione viaggio (richiede un routing engine, es. OpenTripPlanner sul GTFS).

## 3. Architettura (sintesi)

Sorgenti open data → **backend Python** (ingestion + cache TTL, API REST/WebSocket, motore alert,
dispatcher push, DB) → **client Flutter** (mappa, arrivi, preferiti). Le push partono dal backend
via FCM/APNs. Dettaglio sorgenti in `DATA_SOURCES.md`.

## 4. Contratto API (REST)

Tutte le risposte sono JSON. Base path `/v1` in produzione (omesso qui per brevità).

### `GET /lines`
Elenco linee. → `[{ "line": "10", "description": "...", "route_ids": ["..."] }]`

### `GET /stops/search?q={testo}&limit={n}`
Ricerca fermate. → `[{ "stop_id", "code", "name", "lat", "lon" }]`

### `GET /stops/{stop_id}/arrivals?line={opt}`
Passaggi previsti in tempo reale (dai trip update GTFS-RT).
```json
{
  "stop_id": "350",
  "name": "MASSARI CAP.",
  "arrivals": [
    { "line": "10", "headsign": "Corso Settembrini", "trip_id": "...",
      "eta_seconds": 240, "eta_minutes": 4, "scheduled_ts": 1780000000 }
  ]
}
```

### `GET /lines/{line}/vehicles`
Posizioni live dei mezzi della linea.
```json
{ "line": "10", "count": 7,
  "vehicles": [ { "vehicle_id", "trip_id", "headsign",
                  "lat", "lon", "bearing", "speed", "ts" } ] }
```

### `GET /alerts?line={opt}`
Avvisi GTT + scioperi MIT.
```json
{ "service_alerts": [ { "header", "description", "effect", "lines": ["10"] } ],
  "strikes":        [ { /* riga registro MIT: data inizio/fine, settore, area, sindacati */ } ] }
```

### Utenti & sottoscrizioni (v1)
- `POST /me/devices` — registra device token FCM. Body: `{ "platform": "android|ios", "token": "..." }`
- `GET|POST|DELETE /me/favorites` — preferiti `{ "type": "stop|line", "ref": "350|10" }`
- `POST /me/subscriptions` — alert. Body:
  ```json
  { "kind": "imminent", "stop_id": "350", "line": "10", "threshold_min": 5 }
  { "kind": "strike",   "line": "10" }
  ```
- `DELETE /me/subscriptions/{id}`

Autenticazione: per l'MVP basta un ID dispositivo anonimo; account opzionale dopo.

## 5. WebSocket (mappa fluida)

`WS /ws/lines/{line}` — il server spinge un array di posizioni ogni ~3–5 s (legge dalla cache RT,
non un fetch per connessione). Messaggio: stesso schema di `vehicles` sopra. Il client disegna/anima
i marker. Fallback: polling REST di `/lines/{line}/vehicles` se il WS non è disponibile.

## 6. Motore alert (backend)

Scheduler APScheduler:
- **imminent** (ogni ~15 s): per ogni sottoscrizione, leggi gli arrivi previsti alla `stop_id` per la
  `line`; se `eta_minutes <= threshold_min` e non già notificato per quel `trip_id`, accoda push.
  Deduplica per `(subscription_id, trip_id)` con TTL finché il mezzo non è passato.
- **strike** (ogni ~1 h): confronta il set scioperi MIT con lo snapshot precedente; per ogni nuovo
  sciopero che tocca Torino/Piemonte (o nazionale/generale), notifica le sottoscrizioni `strike`
  e gli utenti con preferiti potenzialmente interessati. Reminder il giorno prima e il mattino stesso.

Stato in DB: `notified_events` per evitare duplicati; le valutazioni sono idempotenti.

## 7. Modello dati (DB)

- `devices(id, platform, fcm_token, created_at)`
- `favorites(id, device_id, type, ref)` — type ∈ {stop, line}
- `subscriptions(id, device_id, kind, stop_id?, line?, threshold_min?, active)` — kind ∈ {imminent, strike}
- `notified_events(id, subscription_id, dedup_key, expires_at)`

## 8. Note di qualità

- Tutti i campi RT sono opzionali per spec GTFS-RT: il codice deve degradare con grazia (mezzi senza
  posizione, trip update senza orario, ecc.).
- I test usano payload protobuf/CSV salvati come fixture in `backend/tests/fixtures/`. Zero rete nei test.
- Performance: il GTFS statico si carica una volta e si tiene in cache (TTL ~24 h, refresh in background).
