"""Test del parser difensivo del registro scioperi MIT e del filtro per Torino."""

from __future__ import annotations

from pathlib import Path

from app.scioperi import filter_for_torino, is_relevant_for_torino, parse_strikes_csv

FIX = Path(__file__).parent / "fixtures"


def test_parse_canonical_csv(strikes_csv: str):
    strikes = parse_strikes_csv(strikes_csv)
    assert len(strikes) == 3
    first = strikes[0]
    assert first.start_date == "2026-06-10"
    assert first.sector == "Trasporto pubblico locale"
    assert first.area == "Piemonte"
    assert first.unions == "FILT-CGIL"
    assert first.raw  # riga grezza conservata


def test_filter_keeps_piemonte_and_national(strikes_csv: str):
    strikes = parse_strikes_csv(strikes_csv)
    kept = filter_for_torino(strikes)
    # Piemonte (locale) + Nazionale/Generale; esclude Lombardia/Scuola.
    relevances = {s.relevance for s in kept}
    assert len(kept) == 2
    assert "Locale" in relevances and "Nazionale" in relevances
    assert all(s.area != "Lombardia" for s in kept)


def test_defensive_parsing_renamed_columns_and_semicolon():
    text = (FIX / "scioperi_rinominato.csv").read_text(encoding="utf-8")
    strikes = parse_strikes_csv(text)
    assert len(strikes) == 2
    # Colonne rinominate ('Dal', 'Provincia', ...) comunque mappate.
    torino = strikes[0]
    assert torino.start_date == "2026-06-10"
    assert torino.area == "Torino"
    assert torino.sector == "Trasporto pubblico locale"

    kept = filter_for_torino(strikes)
    assert len(kept) == 1 and kept[0].area == "Torino"


def test_relevance_helper():
    from app.models import Strike

    assert is_relevant_for_torino(Strike(area="Piemonte"))
    assert is_relevant_for_torino(Strike(relevance="Nazionale"))
    assert is_relevant_for_torino(Strike(category="Sciopero generale"))
    assert not is_relevant_for_torino(Strike(area="Sicilia", relevance="Locale"))


def test_empty_csv_is_safe():
    assert parse_strikes_csv("") == []
    assert parse_strikes_csv("   \n") == []
