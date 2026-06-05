"""Registro scioperi MIT: parser difensivo del CSV + filtro per Torino.

I nomi esatti delle colonne possono variare nel tempo: il match è testuale e
case-insensitive, su più alias per campo. Per Torino si includono gli scioperi
con area Piemonte/Torino **e** quelli nazionali/generali del TPL.
"""

from __future__ import annotations

import csv
import io

import httpx

from .config import Settings, get_settings
from .models import Strike

# Alias (lowercase, match per sottostringa) per ciascun campo logico.
_FIELD_ALIASES: dict[str, tuple[str, ...]] = {
    "start_date": ("data_inizio", "data inizio", "dal", "inizio", "data_sciopero", "data"),
    "end_date": ("data_fine", "data fine", "al", "fine", "termine"),
    "sector": ("settore", "comparto"),
    "relevance": ("rilevanza", "ambito"),
    "area": ("regione", "provincia", "area", "territorio", "localizzazione", "luogo"),
    "unions": ("sindacati", "sindacato", "organizzazioni", "oo.ss", "oss"),
    "category": ("categoria", "tipologia", "motivazione"),
}


def _build_column_map(fieldnames: list[str]) -> dict[str, str]:
    """Mappa campo-logico → nome-colonna-reale, con match case-insensitive."""
    mapping: dict[str, str] = {}
    norm = {fn: (fn or "").strip().lower() for fn in fieldnames}
    for field, aliases in _FIELD_ALIASES.items():
        for fn, low in norm.items():
            if any(alias in low for alias in aliases):
                mapping[field] = fn
                break
    return mapping


def parse_strikes_csv(text: str) -> list[Strike]:
    """Parsa il CSV del registro MIT in modo difensivo (delimiter auto)."""
    text = text.lstrip("﻿")
    if not text.strip():
        return []
    try:
        dialect = csv.Sniffer().sniff(text[:4096], delimiters=",;\t")
    except csv.Error:
        dialect = csv.excel  # fallback: virgola
    reader = csv.DictReader(io.StringIO(text), dialect=dialect)
    fieldnames = reader.fieldnames or []
    colmap = _build_column_map(fieldnames)

    out: list[Strike] = []
    for row in reader:
        clean = {(k or "").strip(): (v or "").strip() for k, v in row.items() if k is not None}
        out.append(
            Strike(
                start_date=_pick(clean, colmap, "start_date"),
                end_date=_pick(clean, colmap, "end_date"),
                sector=_pick(clean, colmap, "sector"),
                relevance=_pick(clean, colmap, "relevance"),
                area=_pick(clean, colmap, "area"),
                unions=_pick(clean, colmap, "unions"),
                category=_pick(clean, colmap, "category"),
                raw=clean,
            )
        )
    return out


def _pick(row: dict[str, str], colmap: dict[str, str], field: str) -> str | None:
    col = colmap.get(field)
    if not col:
        return None
    val = (row.get(col) or "").strip()
    return val or None


def is_relevant_for_torino(strike: Strike, settings: Settings | None = None) -> bool:
    """True se lo sciopero tocca Torino/Piemonte o è nazionale/generale."""
    settings = settings or get_settings()
    # Tutto il testo della riga, per essere robusti a colonne mancanti/rinominate.
    blob = " ".join(
        [
            strike.area or "",
            strike.relevance or "",
            strike.sector or "",
            strike.category or "",
            *strike.raw.values(),
        ]
    ).lower()
    if any(region in blob for region in settings.strike_regions):
        return True
    if any(marker in blob for marker in settings.strike_national_markers):
        return True
    return False


def filter_for_torino(strikes: list[Strike], settings: Settings | None = None) -> list[Strike]:
    settings = settings or get_settings()
    return [s for s in strikes if is_relevant_for_torino(s, settings)]


def download_strikes_csv(settings: Settings | None = None) -> str:
    """Scarica il CSV scioperi (rete). Isolato per testabilità."""
    settings = settings or get_settings()
    resp = httpx.get(settings.strikes_csv_url, timeout=settings.http_timeout, follow_redirects=True)
    resp.raise_for_status()
    resp.encoding = resp.encoding or "utf-8"
    return resp.text


__all__ = [
    "parse_strikes_csv",
    "is_relevant_for_torino",
    "filter_for_torino",
    "download_strikes_csv",
]
