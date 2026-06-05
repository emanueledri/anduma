"""Test CRUD di device/preferiti/sottoscrizioni via TestClient su DB di test.

La sessione DB è sovrascritta su uno SQLite temporaneo: nessuna rete, nessun
DB di sviluppo toccato.
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.db import Base, get_session
from app.main import app


@pytest.fixture
def client(tmp_path):
    engine = create_engine(
        f"sqlite:///{tmp_path / 'me.db'}", connect_args={"check_same_thread": False}
    )
    Base.metadata.create_all(engine)
    TestSession = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)

    def override_session():
        s = TestSession()
        try:
            yield s
        finally:
            s.close()

    app.dependency_overrides[get_session] = override_session
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()


def _register(client, token="tok-1", platform="android") -> int:
    r = client.post("/me/devices", json={"platform": platform, "token": token})
    assert r.status_code == 201
    return r.json()["id"]


# --------------------------------------------------------------------- devices
def test_register_device(client):
    r = client.post("/me/devices", json={"platform": "android", "token": "abc"})
    assert r.status_code == 201
    body = r.json()
    assert body["id"] >= 1 and body["platform"] == "android" and "created_at" in body


def test_register_device_idempotent_on_token(client):
    id1 = _register(client, token="same")
    # Stesso token → stesso device (aggiorna la piattaforma, non duplica).
    r = client.post("/me/devices", json={"platform": "ios", "token": "same"})
    assert r.status_code == 201
    assert r.json()["id"] == id1 and r.json()["platform"] == "ios"


def test_register_device_validation(client):
    assert client.post("/me/devices", json={"platform": "windows", "token": "x"}).status_code == 422
    assert client.post("/me/devices", json={"platform": "android"}).status_code == 422


# ------------------------------------------------------------------- auth dep
def test_me_requires_device_header(client):
    assert client.get("/me/favorites").status_code == 401
    assert client.get("/me/favorites", headers={"X-Device-Id": "9999"}).status_code == 401


# --------------------------------------------------------- favorites lifecycle
def test_favorites_crud_and_isolation(client):
    dev = _register(client, token="dev-a")
    other = _register(client, token="dev-b")
    h = {"X-Device-Id": str(dev)}

    assert client.get("/me/favorites", headers=h).json() == []

    r = client.post("/me/favorites", json={"type": "stop", "ref": "350"}, headers=h)
    assert r.status_code == 201
    fav_id = r.json()["id"]
    client.post("/me/favorites", json={"type": "line", "ref": "10"}, headers=h)

    # Idempotente: stesso (type, ref) non duplica.
    again = client.post("/me/favorites", json={"type": "stop", "ref": "350"}, headers=h)
    assert again.json()["id"] == fav_id

    favs = client.get("/me/favorites", headers=h).json()
    assert {(f["type"], f["ref"]) for f in favs} == {("stop", "350"), ("line", "10")}

    # Un altro device non vede i preferiti del primo.
    assert client.get("/me/favorites", headers={"X-Device-Id": str(other)}).json() == []

    # Delete proprio → 204; non posso cancellare quello altrui → 404.
    assert client.delete(f"/me/favorites/{fav_id}", headers=h).status_code == 204
    assert (
        client.delete(f"/me/favorites/{fav_id}", headers={"X-Device-Id": str(other)}).status_code
        == 404
    )
    remaining = client.get("/me/favorites", headers=h).json()
    assert {(f["type"], f["ref"]) for f in remaining} == {("line", "10")}


# ----------------------------------------------------- subscriptions lifecycle
def test_subscriptions_crud_and_validation(client):
    dev = _register(client, token="dev-sub")
    h = {"X-Device-Id": str(dev)}

    # imminent ben formata.
    r = client.post(
        "/me/subscriptions",
        json={"kind": "imminent", "stop_id": "350", "line": "10", "threshold_min": 5},
        headers=h,
    )
    assert r.status_code == 201
    sub_id = r.json()["id"]
    assert r.json()["active"] is True

    # strike (solo line).
    assert (
        client.post(
            "/me/subscriptions", json={"kind": "strike", "line": "55"}, headers=h
        ).status_code
        == 201
    )

    # imminent senza i campi richiesti → 422.
    bad = client.post("/me/subscriptions", json={"kind": "imminent", "line": "10"}, headers=h)
    assert bad.status_code == 422
    # strike senza line → 422.
    assert client.post("/me/subscriptions", json={"kind": "strike"}, headers=h).status_code == 422

    subs = client.get("/me/subscriptions", headers=h).json()
    assert {s["kind"] for s in subs} == {"imminent", "strike"}

    assert client.delete(f"/me/subscriptions/{sub_id}", headers=h).status_code == 204
    assert client.delete("/me/subscriptions/999999", headers=h).status_code == 404
    subs = client.get("/me/subscriptions", headers=h).json()
    assert [s["kind"] for s in subs] == ["strike"]


def test_save_and_reread_roundtrip(client):
    """Criterio 'Fatto': un device salva preferiti e sottoscrizioni e li rilegge."""
    dev = _register(client, token="roundtrip")
    h = {"X-Device-Id": str(dev)}
    client.post("/me/favorites", json={"type": "stop", "ref": "350"}, headers=h)
    client.post(
        "/me/subscriptions",
        json={"kind": "imminent", "stop_id": "350", "line": "10", "threshold_min": 3},
        headers=h,
    )

    favs = client.get("/me/favorites", headers=h).json()
    subs = client.get("/me/subscriptions", headers=h).json()
    assert favs[0]["ref"] == "350"
    assert subs[0]["threshold_min"] == 3
