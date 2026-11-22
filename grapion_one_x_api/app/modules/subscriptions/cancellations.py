# //Added By Nikhil 21Nov26 22:44 For subscription cancellation (user side) + shared helpers
"""Cancellation flow.

* Pending request  → user cancels with a reason; until the admin acts the user can "Keep Subscription"
  (withdraw). Admin Approve on that request = activate anyway (cancellation rejected),
  admin Reject = request ends (cancellation approved).
* Active module    → user cancels with a reason; the SERVER freezes a pro-rated refund
  (paid after discount × unused days ÷ total days, today counts as used). Admin approves (module switched
  off, back-office refund recorded) or rejects (module runs to its end date).
* Every action is written to subscription_cancellation_events, so the full history is kept.
"""
import math
import random
from datetime import datetime
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.config import settings
from app.core.dependencies import get_current_user
from app.db.models import (
    Module,
    SubscriptionCancellation,
    SubscriptionCancellationEvent,
    SubscriptionRequest,
    SubscriptionRequestItem,
    User,
    UserModuleSubscription,
)
from app.db.session import get_db

router = APIRouter(prefix="/subscriptions/cancellations", tags=["Cancellations"])


def now_tz() -> datetime:
    return datetime.now(ZoneInfo(settings.APP_TIMEZONE))


async def new_cancellation_number(db: AsyncSession, now: datetime) -> str:
    # GOX-C-YYMMDD-XXXX (server time zone) — retried until unique.
    for _ in range(10):
        number = f"GOX-C-{now.strftime('%y%m%d')}-{random.randint(1000, 9999)}"
        exists = await db.execute(
            select(SubscriptionCancellation.id).where(SubscriptionCancellation.cancellation_number == number)
        )
        if not exists.first():
            return number
    raise HTTPException(status_code=500, detail="Could not allocate a cancellation number")


def log_event(db: AsyncSession, c: SubscriptionCancellation, event: str, actor: User, note: str | None, now: datetime):
    db.add(SubscriptionCancellationEvent(
        cancellation_id=c.id,
        event=event,
        actor_id=actor.id,
        actor_role=actor.role,
        note=note,
        created_at=now,
        created_by=actor.id,
    ))


#Modified By Nikhil 22Nov26 10:47 For renewal-only refund window. Old: def compute_refund(sub, req, item_price_paise, now)
def compute_refund(sub: UserModuleSubscription, req: SubscriptionRequest, item_price_paise: int, now: datetime,
                   covers: tuple[datetime | None, datetime | None] | None = None) -> dict:
    """Pro-rated refund frozen at the moment of cancellation (all in INR paise)."""
    #Modified By Nikhil 22Nov26 10:47 For refund of only the latest renewal's own period. Old: whole sub.starts_at → sub.expires_at, used always ≥ 1
    start, end = (covers if covers and covers[0] and covers[1] else (sub.starts_at, sub.expires_at))
    total_days = max(1, round((end - start).total_seconds() / 86400))
    used_days = 0 if now < start else min(total_days, max(1, math.ceil((now - start).total_seconds() / 86400)))  # today counts; renewal not started → full refund
    # What the user actually paid for this module = its list price × (final ÷ base) of the request.
    paid = item_price_paise if req.base_amount_paise <= 0 else (item_price_paise * req.final_amount_paise) // req.base_amount_paise
    refund = (paid * (total_days - used_days)) // total_days
    return {"total_days": total_days, "used_days": used_days, "paid_amount_paise": paid, "refund_amount_paise": refund}


def serialize(c: SubscriptionCancellation, module_name: str | None = None) -> dict:
    tz = ZoneInfo(settings.APP_TIMEZONE)
    return {
        "id": str(c.id),
        "cancellation_number": c.cancellation_number,
        "cancel_type": c.cancel_type,
        "status": c.status,
        "reason": c.reason,
        "module_name": module_name,
        "total_days": c.total_days,
        "used_days": c.used_days,
        "paid_amount": (c.paid_amount_paise or 0) // 100 if c.paid_amount_paise is not None else None,
        "refund_amount": (c.refund_amount_paise or 0) // 100 if c.refund_amount_paise is not None else None,
        "created_at": c.created_at.astimezone(tz).isoformat() if c.created_at else None,
    }


async def open_cancellation_for_request(db: AsyncSession, request_id) -> SubscriptionCancellation | None:
    res = await db.execute(
        select(SubscriptionCancellation).where(
            SubscriptionCancellation.request_id == request_id,
            SubscriptionCancellation.cancel_type == "pending_request",
            SubscriptionCancellation.status == "requested",
        )
    )
    return res.scalar_one_or_none()


# ---------------- user endpoints ----------------

class CreateCancellationRequest(BaseModel):
    target: str = Field(..., pattern="^(pending_request|active_module)$")
    module_code: str | None = Field(None, max_length=50)
    reason: str = Field(..., min_length=2, max_length=500)


@router.post("", status_code=201)
async def create_cancellation(
    req: CreateCancellationRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    now = now_tz()
    reason = req.reason.strip()

    if req.target == "pending_request":
        res = await db.execute(
            select(SubscriptionRequest).where(SubscriptionRequest.user_id == user.id, SubscriptionRequest.status == "pending")
        )
        sub_req = res.scalar_one_or_none()
        if not sub_req:
            raise HTTPException(status_code=404, detail="No pending subscription request to cancel")
        if await open_cancellation_for_request(db, sub_req.id):
            raise HTTPException(status_code=400, detail="Cancellation already requested for this request")
        c = SubscriptionCancellation(
            cancellation_number=await new_cancellation_number(db, now),
            user_id=user.id,
            request_id=sub_req.id,
            cancel_type="pending_request",
            reason=reason,
            status="requested",
            created_at=now,
            updated_at=now,
            created_by=user.id,
            modified_by=user.id,
        )
        module_name = None
    else:
        if not req.module_code:
            raise HTTPException(status_code=400, detail="Module is required")
        res = await db.execute(
            select(UserModuleSubscription)
            .join(Module, Module.id == UserModuleSubscription.module_id)
            .options(selectinload(UserModuleSubscription.module))
            .where(
                UserModuleSubscription.user_id == user.id,  # ownership: only the caller's own subscription
                Module.code == req.module_code,
                UserModuleSubscription.is_active == True,
                UserModuleSubscription.expires_at >= now,
            )
        )
        sub = res.scalar_one_or_none()
        if not sub:
            raise HTTPException(status_code=404, detail="No active subscription for this module")
        open_res = await db.execute(
            select(SubscriptionCancellation.id).where(
                SubscriptionCancellation.user_module_subscription_id == sub.id,
                SubscriptionCancellation.status == "requested",
            )
        )
        if open_res.first():
            raise HTTPException(status_code=400, detail="Cancellation already requested for this module")
        req_res = await db.execute(select(SubscriptionRequest).where(SubscriptionRequest.id == sub.request_id))
        sub_req = req_res.scalar_one()
        item_res = await db.execute(
            #Modified By Nikhil 22Nov26 10:47 For covered dates of the latest renewal. Old: select(SubscriptionRequestItem.price_paise)
            select(SubscriptionRequestItem.price_paise, SubscriptionRequestItem.covers_from, SubscriptionRequestItem.covers_to).where(
                SubscriptionRequestItem.request_id == sub.request_id,
                SubscriptionRequestItem.module_id == sub.module_id,
            )
        )
        item_row = item_res.first()  #Modified By Nikhil 22Nov26 10:47 For covers. Old: item_price = item_res.scalar_one_or_none() or 0
        item_price = (item_row.price_paise if item_row else 0) or 0  #Added By Nikhil 22Nov26 10:47 For covers
        refund = compute_refund(sub, sub_req, item_price, now, (item_row.covers_from, item_row.covers_to) if item_row else None)  #Modified By Nikhil 22Nov26 10:47 For renewal-only refund. Old: compute_refund(sub, sub_req, item_price, now)
        c = SubscriptionCancellation(
            cancellation_number=await new_cancellation_number(db, now),
            user_id=user.id,
            request_id=sub.request_id,
            user_module_subscription_id=sub.id,
            cancel_type="active_module",
            reason=reason,
            status="requested",
            created_at=now,
            updated_at=now,
            created_by=user.id,
            modified_by=user.id,
            **refund,
        )
        module_name = sub.module.name

    db.add(c)
    await db.flush()
    log_event(db, c, "requested", user, reason, now)
    await db.commit()
    return serialize(c, module_name)


@router.post("/{cancellation_id}/withdraw")
async def withdraw_cancellation(
    cancellation_id: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """"Keep Subscription": the user takes back an open cancellation (history is kept)."""
    try:
        import uuid as _uuid
        cid = _uuid.UUID(cancellation_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="Cancellation not found")
    res = await db.execute(
        select(SubscriptionCancellation).where(
            SubscriptionCancellation.id == cid,
            SubscriptionCancellation.user_id == user.id,  # ownership check (no IDOR)
        )
    )
    c = res.scalar_one_or_none()
    if not c:
        raise HTTPException(status_code=404, detail="Cancellation not found")
    if c.status != "requested":
        raise HTTPException(status_code=400, detail="This cancellation has already been reviewed")
    now = now_tz()
    c.status = "withdrawn"
    c.updated_at = now
    c.modified_by = user.id
    log_event(db, c, "withdrawn", user, "Keep Subscription", now)
    await db.commit()
    return {"status": "withdrawn", "message": "Your subscription will continue"}


@router.get("")
async def list_my_cancellations(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """Open cancellations of the signed-in user (shown on the gate / profile / my modules)."""
    res = await db.execute(
        select(SubscriptionCancellation)
        .options(selectinload(SubscriptionCancellation.module_subscription).selectinload(UserModuleSubscription.module))
        .where(SubscriptionCancellation.user_id == user.id, SubscriptionCancellation.status == "requested")
        .order_by(SubscriptionCancellation.created_at.desc())
    )
    out = []
    for c in res.scalars().all():
        ms = c.module_subscription
        item = serialize(c, ms.module.name if ms else None)
        item["module_code"] = ms.module.code if ms else None
        out.append(item)
    return {"open": out}
