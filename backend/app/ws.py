"""Gestione delle connessioni WebSocket per la mappa live.

Il server spinge le posizioni dei mezzi leggendo dalla **cache RT condivisa** (un
solo polling centralizzato, non un fetch per connessione). ``ConnectionManager``
tiene traccia delle connessioni attive e applica un tetto (backpressure); la
pulizia avviene alla disconnessione.
"""

from __future__ import annotations

from fastapi import WebSocket


class ConnectionManager:
    """Registro delle connessioni WS attive con limite di capacità."""

    def __init__(self, max_connections: int = 500) -> None:
        self._max = max_connections
        self._active: set[WebSocket] = set()

    def register(self, websocket: WebSocket) -> bool:
        """Aggiunge la connessione; ``False`` se si è raggiunto il tetto."""
        if len(self._active) >= self._max:
            return False
        self._active.add(websocket)
        return True

    def unregister(self, websocket: WebSocket) -> None:
        self._active.discard(websocket)

    @property
    def count(self) -> int:
        return len(self._active)


__all__ = ["ConnectionManager"]
