"""Test del WebSocket mappa: streaming periodico, cleanup, capacità.

Usa il provider fake (fixture protobuf): nessuna rete. L'intervallo viene
abbassato sull'app per non rallentare i test.
"""

from __future__ import annotations


def test_ws_streams_vehicles_for_line(client):
    client.app.state.ws_interval_s = 0.05
    with client.websocket_connect("/ws/lines/10") as ws:
        msg = ws.receive_json()
        assert msg["line"] == "10"
        assert msg["count"] == 2
        assert {v["vehicle_id"] for v in msg["vehicles"]} == {"BUS001", "BUS002"}


def test_ws_sends_periodic_frames(client):
    client.app.state.ws_interval_s = 0.05
    with client.websocket_connect("/ws/lines/55") as ws:
        first = ws.receive_json()
        second = ws.receive_json()  # secondo frame periodico
        assert first["line"] == "55" and second["line"] == "55"
        assert {v["vehicle_id"] for v in first["vehicles"]} == {"BUS055"}


def test_ws_unknown_line_streams_empty(client):
    client.app.state.ws_interval_s = 0.05
    with client.websocket_connect("/ws/lines/999") as ws:
        msg = ws.receive_json()
        assert msg["line"] == "999" and msg["count"] == 0 and msg["vehicles"] == []


def test_ws_connection_cleanup(client):
    client.app.state.ws_interval_s = 0.05
    manager = client.app.state.ws_manager
    assert manager.count == 0
    with client.websocket_connect("/ws/lines/10") as ws:
        ws.receive_json()
        assert manager.count == 1
    # Alla chiusura la connessione viene rimossa dal registro.
    assert manager.count == 0


def test_ws_capacity_limit_rejects(client):
    client.app.state.ws_interval_s = 0.05
    # Saturazione artificiale del registro: la prossima connessione viene chiusa.
    manager = client.app.state.ws_manager
    saved_max = manager._max
    manager._max = 0
    try:
        with client.websocket_connect("/ws/lines/10") as ws:
            # Il server accetta e poi chiude (1013): la receive deve fallire.
            import pytest
            from starlette.websockets import WebSocketDisconnect

            with pytest.raises(WebSocketDisconnect):
                ws.receive_json()
    finally:
        manager._max = saved_max
