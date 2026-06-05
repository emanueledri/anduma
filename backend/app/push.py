"""Invio push (FCM/APNs via Firebase Admin SDK) e cleanup dei token invalidi.

Collega la coda disaccoppiata di M3 (``InProcessDispatcher``) all'invio reale:
il ``PushService`` svuota la coda, risolve il ``device_id`` nel suo token FCM,
invia, e in caso di token non più valido rimuove il device (cleanup).

``firebase_admin`` viene importato pigramente dentro ``FirebaseSender`` così che
il modulo (e i test) non richiedano l'SDK né credenziali reali: nei test si usa
un sender fake. APNs è gestito da FCM dietro le quinte (chiave APNs caricata su
Firebase, configurazione esterna).
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Protocol

from sqlalchemy.orm import Session, sessionmaker

from .alerts import Dispatcher, InProcessDispatcher, PushMessage
from .config import Settings, get_settings
from .db import Device


class InvalidTokenError(Exception):
    """Il token FCM non è più valido (device disinstallato / token ruotato)."""


class PushSender(Protocol):
    def send(self, token: str, message: PushMessage) -> None:
        """Invia. Solleva ``InvalidTokenError`` se il token è da rimuovere."""
        ...


@dataclass
class PushResult:
    sent: int = 0
    failed: int = 0
    invalid_tokens: list[str] = field(default_factory=list)


class FirebaseSender:
    """Sender reale: Firebase Admin SDK. Inizializzazione pigra e idempotente."""

    def __init__(self, credentials_file: str, app_name: str = "transito"):
        self._credentials_file = credentials_file
        self._app_name = app_name
        self._app = None

    def _ensure_app(self):
        if self._app is not None:
            return self._app
        import firebase_admin
        from firebase_admin import credentials

        cred = credentials.Certificate(self._credentials_file)
        try:
            self._app = firebase_admin.get_app(self._app_name)
        except ValueError:
            self._app = firebase_admin.initialize_app(cred, name=self._app_name)
        return self._app

    def send(self, token: str, message: PushMessage) -> None:
        from firebase_admin import messaging

        app = self._ensure_app()
        fcm_message = messaging.Message(
            token=token,
            notification=messaging.Notification(title=message.title, body=message.body),
            data={k: str(v) for k, v in message.data.items()},
        )
        try:
            messaging.send(fcm_message, app=app)
        except (messaging.UnregisteredError, messaging.SenderIdMismatchError) as exc:
            raise InvalidTokenError(token) from exc
        except ValueError as exc:
            # Token malformato → da rimuovere.
            raise InvalidTokenError(token) from exc


class PushService:
    """Svuota il dispatcher e invia le push, con cleanup dei token invalidi."""

    def __init__(self, sender: PushSender):
        self._sender = sender

    def process(self, session: Session, dispatcher: Dispatcher) -> PushResult:
        result = PushResult()
        messages = dispatcher.drain() if hasattr(dispatcher, "drain") else []
        invalid_device_ids: set[int] = set()
        for msg in messages:
            device = session.get(Device, msg.device_id)
            if device is None:
                result.failed += 1
                continue
            token = device.fcm_token
            try:
                self._sender.send(token, msg)
                result.sent += 1
            except InvalidTokenError:
                result.invalid_tokens.append(token)
                invalid_device_ids.add(device.id)
            except Exception:
                result.failed += 1

        # Cleanup: rimuove i device con token non più valido (cascade su
        # preferiti/sottoscrizioni).
        for device_id in invalid_device_ids:
            device = session.get(Device, device_id)
            if device is not None:
                session.delete(device)
        session.commit()
        return result


def build_push_service(settings: Settings | None = None) -> PushService | None:
    """Crea il PushService reale se FCM è abilitato, altrimenti None."""
    settings = settings or get_settings()
    if not settings.fcm_enabled:
        return None
    return PushService(FirebaseSender(settings.fcm_credentials_file))


def make_push_processor(
    push_service: PushService,
    dispatcher: InProcessDispatcher,
    session_factory: sessionmaker[Session],
):
    """Callable a zero argomenti per lo scheduler: processa la coda push."""

    def _tick() -> PushResult:
        with session_factory() as session:
            return push_service.process(session, dispatcher)

    return _tick


__all__ = [
    "InvalidTokenError",
    "PushSender",
    "PushResult",
    "FirebaseSender",
    "PushService",
    "build_push_service",
    "make_push_processor",
]
