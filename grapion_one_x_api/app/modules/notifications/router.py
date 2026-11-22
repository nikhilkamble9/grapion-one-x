# //Added By Nikhil 22Nov26 00:10 For notification bell + push device tokens + notify helper
import logging
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select, text, update
from sqlalchemy.exc import ProgrammingError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core import push
from app.core.dependencies import get_current_user
from app.db.models import Notification, User
from app.db.session import get_db
from app.modules.workspaces.access import now_tz

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/notifications", tags=["Notifications"])


# ---------------- helper used by holidays, expiry reminders, invites … ----------------

async def notify_users(
    db: AsyncSession,
    user_ids: list[UUID],
    *,
    category: str,
    title: str,
    message: str,
    workspace_id=None,
    branch_id=None,
    dedupe_prefix: str | None = None,
    actor_id=None,
) -> None:
    """Writes the in-app bell rows (always) and pushes to every active device (best effort).

    Caller commits. Push runs after the rows are added; a push failure never fails the request.
    """
    now = now_tz()
    ids = list(dict.fromkeys(user_ids))  # de-duplicate, keep order
    for uid in ids:
        db.add(Notification(
            user_id=uid, workspace_id=workspace_id, branch_id=branch_id, category=category, title=title,
            message=message, dedupe_key=f"{dedupe_prefix}:{uid}" if dedupe_prefix else None,
            created_at=now, created_by=actor_id,
        ))
    if not ids:
        return
    try:
        # Savepoint: if the token table is not there yet, only this query is undone — the bell rows stay.
        async with db.begin_nested():
            rows = (await db.execute(
                text("SELECT token FROM grapion_one_x.user_push_tokens WHERE is_active AND user_id = ANY(:ids)"),
                {"ids": ids},
            )).all()
    except ProgrammingError:
        return  # push not enabled yet → bell only
    tokens = [r[0] for r in rows]
    for i in range(0, len(tokens), 500):  # FCM multicast limit
        dead = await push.send_push(tokens[i:i + 500], title, message, {"category": category})
        if dead:
            await db.execute(
                text("UPDATE grapion_one_x.user_push_tokens SET is_active = FALSE, updated_at = now() WHERE token = ANY(:t)"),
                {"t": dead},
            )


# ---------------- bell ----------------

@router.get("")
async def my_notifications(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    rows = (await db.execute(
        select(Notification).where(Notification.user_id == user.id).order_by(Notification.created_at.desc()).limit(50)
    )).scalars().all()
    unread = sum(1 for n in rows if not n.is_read)
    return {
        "unread": unread,
        "items": [{
            "id": str(n.id), "category": n.category, "title": n.title, "message": n.message,
            "is_read": n.is_read, "created_at": n.created_at.astimezone(now_tz().tzinfo).isoformat() if n.created_at else None,
        } for n in rows],
    }


@router.post("/{notification_id}/read")
async def mark_read(notification_id: str, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    try:
        nid = UUID(notification_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="Notification not found")
    res = await db.execute(
        update(Notification)
        .where(Notification.id == nid, Notification.user_id == user.id)  # ownership
        .values(is_read=True, read_at=now_tz())
    )
    if res.rowcount == 0:
        raise HTTPException(status_code=404, detail="Notification not found")
    await db.commit()
    return {"status": "read"}


@router.post("/read-all")
async def mark_all_read(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    await db.execute(
        update(Notification).where(Notification.user_id == user.id, Notification.is_read == False)
        .values(is_read=True, read_at=now_tz())
    )
    await db.commit()
    return {"status": "read"}


# ---------------- device tokens ----------------

class TokenRequest(BaseModel):
    token: str = Field(..., min_length=20, max_length=4096)
    platform: str = Field("android", pattern="^(android|ios|web)$")


class TokenRemoveRequest(BaseModel):
    token: str = Field(..., min_length=20, max_length=4096)


@router.post("/push-token")
async def save_token(req: TokenRequest, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    try:
        # One row per device; if the phone changes hands the token moves to the new user.
        await db.execute(text("""
            INSERT INTO grapion_one_x.user_push_tokens (user_id, token, platform, is_active, last_seen_at, created_by, modified_by)
            VALUES (:u, :t, :p, TRUE, now(), :u, :u)
            ON CONFLICT (token) DO UPDATE
               SET user_id = EXCLUDED.user_id, platform = EXCLUDED.platform, is_active = TRUE,
                   last_seen_at = now(), updated_at = now(), modified_by = EXCLUDED.modified_by
        """), {"u": user.id, "t": req.token, "p": req.platform})
        await db.commit()
    except ProgrammingError:
        await db.rollback()
        raise HTTPException(status_code=503, detail="Push notifications are not enabled yet")
    return {"status": "registered"}


@router.post("/push-token/remove")
async def remove_token(req: TokenRemoveRequest, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    try:
        await db.execute(text(
            "UPDATE grapion_one_x.user_push_tokens SET is_active = FALSE, updated_at = now(), modified_by = :u "
            "WHERE token = :t AND user_id = :u"), {"u": user.id, "t": req.token})
        await db.commit()
    except ProgrammingError:
        await db.rollback()
    return {"status": "removed"}
