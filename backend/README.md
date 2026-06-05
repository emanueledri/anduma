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
