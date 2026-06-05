"""Verifica che le migrazioni Alembic si applichino e creino lo schema atteso.

Gira in un subprocess con ``TT_DATABASE_URL`` su uno SQLite temporaneo, così non
tocca il DB di sviluppo né la rete.
"""

from __future__ import annotations

import os
import sqlite3
import subprocess
import sys
from pathlib import Path

BACKEND = Path(__file__).parent.parent

UPGRADE = """
from alembic.config import Config
from alembic import command

command.upgrade(Config("alembic.ini"), "head")
"""


def test_migrations_create_schema(tmp_path):
    db = tmp_path / "migrated.db"
    env = {**os.environ, "TT_DATABASE_URL": f"sqlite:///{db}"}
    result = subprocess.run(
        [sys.executable, "-c", UPGRADE],
        cwd=BACKEND,
        env=env,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stderr

    con = sqlite3.connect(db)
    try:
        tables = {
            row[0] for row in con.execute("SELECT name FROM sqlite_master WHERE type='table'")
        }
    finally:
        con.close()

    assert {"devices", "favorites", "subscriptions", "notified_events"} <= tables
    assert "alembic_version" in tables
