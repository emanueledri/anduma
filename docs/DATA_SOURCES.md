# DATA_SOURCES — Transito Torino

Tutte le sorgenti, con formato, licenza e trappole note. Tenere gli URL in `backend/app/config.py`.

## GTFS statico (orari, fermate, percorsi)

- Dataset: http://aperto.comune.torino.it/dataset/feed-gtfs-trasporti-gtt
- Formato: ZIP di file `.txt` (CSV) secondo specifica GTFS.
- Licenza: **CC BY 4.0** (attribuzione "Città di Torino / GTT").
- File usati: `routes.txt`, `stops.txt`, `trips.txt` (e `shapes.txt` per disegnare i percorsi).
- **Trappola**: il link diretto di *download* dello ZIP può cambiare. Se dà 404, riprenderlo dalla
  pagina del dataset (sezione "Dati e Risorse" → risorsa "Feed GTFS … statico"). Tenerlo in config.
- `stop_times.txt` è grande: **non serve** per gli arrivi in tempo reale (si usano i trip update RT).
  Caricarlo solo se in futuro servono gli orari programmati offline.

### Mappatura linea → route_id (fondamentale)
I feed RT identificano le corse con `route_id`/`trip_id` interni, non con l'etichetta "10".
Per filtrare una linea: leggere `routes.txt`, prendere le righe con `route_short_name == "10"`,
raccogliere i relativi `route_id` (possono essere più d'uno per varianti di percorso).

## GTFS-Realtime (protobuf binario)

Tre endpoint, tutti formato **GTFS-RT** (protobuf, NON JSON). Parsare con `gtfs-realtime-bindings`:
`from google.transit import gtfs_realtime_pb2`.

| Feed | URL | Contenuto |
|------|-----|-----------|
| Posizioni mezzi | https://percorsieorari.gtt.to.it/das_gtfsrt/vehicle_position.aspx | `VehiclePosition`: lat/lon, bearing, speed, trip, vehicle id |
| Trip update | https://percorsieorari.gtt.to.it/das_gtfsrt/trip_update.aspx | `TripUpdate`: per ogni `stop_time_update` arrivo/partenza previsti |
| Alerts | https://percorsieorari.gtt.to.it/das_gtfsrt/alerts.aspx | `Alert`: deviazioni/avvisi, con `informed_entity` (route/stop) |

**Nota**: il server risponde solo su HTTPS (porta 443). Le URL con `http://` vanno in timeout
senza errore. La homepage `https://percorsieorari.gtt.to.it/` non risponde (normale: è un
server API puro, non un sito web). Dataset ufficiale su Open Data Torino:
https://aperto.comune.torino.it/en/dataset/feed-gtfs-real-time-trasporti-gtt

- Cache TTL consigliata: ~10–15 s per posizioni/trip update, ~60 s per gli alerts.
- Arrivi alla fermata = scorrere i `TripUpdate`, filtrare gli `stop_time_update` con `stop_id` target,
  prendere `arrival.time` (o `departure.time`), sottrarre `now`. Arricchire con `route_short_name`
  (via `route_id`/`trip_id` → GTFS statico) e `trip_headsign`.
- Tutti i campi sono opzionali per spec: controllare sempre `HasField(...)` prima di leggere.

## Scioperi (registro MIT)

- Osservatorio sui Conflitti Sindacali del MIT — fonte ufficiale, preavviso ≥ 10 giorni per legge.
- Dataset open data (CSV): https://dati.mit.gov.it/catalog/dataset/scioperi-dei-trasporti
  - CSV: …/resource/6838feb1-1f3d-40dc-845f-d304088a92cd/download/scioperi.csv
- Feed RSS (più semplice da filtrare per testo):
  https://scioperi.mit.gov.it/mit2/public/scioperi/rss
- Consultazione umana: http://scioperi.mit.gov.it/mit2/public/scioperi
- Campi utili: data inizio/fine, **settore** (filtrare "Trasporto pubblico locale" + "Generale"),
  **rilevanza** (Locale/Nazionale), **regione/provincia** (Piemonte / Torino), sindacati, categoria.
- **Trappola**: i nomi esatti delle colonne del CSV possono variare nel tempo. Scrivere il parser in
  modo difensivo (match testuale case-insensitive) e coprirlo con una fixture del CSV reale.
- Per Torino includere: scioperi con area Piemonte/Torino **e** scioperi nazionali/generali del TPL.

## Riepilogo licenze / crediti

- Feed GTT (statico + RT): **CC BY 4.0** → credito "Città di Torino / GTT".
- Scioperi: dati **MIT — Osservatorio sui Conflitti Sindacali**.
- Mappa: tile **OpenStreetMap** → credito "© OpenStreetMap contributors".
Inserire tutti i crediti in una schermata "Informazioni / Fonti dati" dell'app.
