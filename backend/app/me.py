"""Endpoint utente (v1): device anonimo, preferiti, sottoscrizioni.

Identità MVP: il client registra un device via ``POST /me/devices`` e poi si
identifica con l'header ``X-Device-Id`` nelle altre chiamate ``/me/*``. Nessun
account: l'autenticazione vera arriverà dopo (vedi SPEC §4).
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, Header, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from .db import Device, Favorite, Subscription, get_session
from .models import (
    DeviceCreate,
    DeviceOut,
    FavoriteCreate,
    FavoriteOut,
    SubscriptionCreate,
    SubscriptionOut,
)

router = APIRouter(prefix="/me", tags=["me"])


def get_current_device(
    x_device_id: int | None = Header(None, alias="X-Device-Id"),
    session: Session = Depends(get_session),
) -> Device:
    """Risolve il device dall'header ``X-Device-Id`` (401 se assente/ignoto)."""
    if x_device_id is None:
        raise HTTPException(status_code=401, detail="Header X-Device-Id mancante")
    device = session.get(Device, x_device_id)
    if device is None:
        raise HTTPException(status_code=401, detail="Device non registrato")
    return device


# --------------------------------------------------------------------- devices
@router.post("/devices", response_model=DeviceOut, status_code=201)
def register_device(body: DeviceCreate, session: Session = Depends(get_session)) -> DeviceOut:
    """Registra (o aggiorna) un device anonimo. Idempotente sul token FCM."""
    existing = session.scalar(select(Device).where(Device.fcm_token == body.token))
    if existing is not None:
        existing.platform = body.platform
        session.commit()
        return DeviceOut.model_validate(existing)
    device = Device(platform=body.platform, fcm_token=body.token)
    session.add(device)
    session.commit()
    session.refresh(device)
    return DeviceOut.model_validate(device)


# ------------------------------------------------------------------- favorites
@router.get("/favorites", response_model=list[FavoriteOut])
def list_favorites(
    device: Device = Depends(get_current_device),
    session: Session = Depends(get_session),
) -> list[FavoriteOut]:
    rows = session.scalars(
        select(Favorite).where(Favorite.device_id == device.id).order_by(Favorite.id)
    ).all()
    return [FavoriteOut.model_validate(r) for r in rows]


@router.post("/favorites", response_model=FavoriteOut, status_code=201)
def add_favorite(
    body: FavoriteCreate,
    device: Device = Depends(get_current_device),
    session: Session = Depends(get_session),
) -> FavoriteOut:
    # Idempotente: stesso (device, type, ref) → ritorna l'esistente.
    existing = session.scalar(
        select(Favorite).where(
            Favorite.device_id == device.id,
            Favorite.type == body.type,
            Favorite.ref == body.ref,
        )
    )
    if existing is not None:
        return FavoriteOut.model_validate(existing)
    fav = Favorite(device_id=device.id, type=body.type, ref=body.ref)
    session.add(fav)
    session.commit()
    session.refresh(fav)
    return FavoriteOut.model_validate(fav)


@router.delete("/favorites/{favorite_id}", status_code=204)
def delete_favorite(
    favorite_id: int,
    device: Device = Depends(get_current_device),
    session: Session = Depends(get_session),
) -> None:
    fav = session.get(Favorite, favorite_id)
    if fav is None or fav.device_id != device.id:
        raise HTTPException(status_code=404, detail="Preferito non trovato")
    session.delete(fav)
    session.commit()


# --------------------------------------------------------------- subscriptions
@router.get("/subscriptions", response_model=list[SubscriptionOut])
def list_subscriptions(
    device: Device = Depends(get_current_device),
    session: Session = Depends(get_session),
) -> list[SubscriptionOut]:
    rows = session.scalars(
        select(Subscription).where(Subscription.device_id == device.id).order_by(Subscription.id)
    ).all()
    return [SubscriptionOut.model_validate(r) for r in rows]


@router.post("/subscriptions", response_model=SubscriptionOut, status_code=201)
def add_subscription(
    body: SubscriptionCreate,
    device: Device = Depends(get_current_device),
    session: Session = Depends(get_session),
) -> SubscriptionOut:
    sub = Subscription(
        device_id=device.id,
        kind=body.kind,
        stop_id=body.stop_id,
        line=body.line,
        threshold_min=body.threshold_min,
        active=True,
    )
    session.add(sub)
    session.commit()
    session.refresh(sub)
    return SubscriptionOut.model_validate(sub)


@router.delete("/subscriptions/{subscription_id}", status_code=204)
def delete_subscription(
    subscription_id: int,
    device: Device = Depends(get_current_device),
    session: Session = Depends(get_session),
) -> None:
    sub = session.get(Subscription, subscription_id)
    if sub is None or sub.device_id != device.id:
        raise HTTPException(status_code=404, detail="Sottoscrizione non trovata")
    session.delete(sub)
    session.commit()


__all__ = ["router", "get_current_device"]
