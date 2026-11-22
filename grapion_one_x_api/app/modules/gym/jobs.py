# //Added By Nikhil 22Nov26 18:05 For "you forgot to check out" reminders (members check out themselves; nothing is closed automatically)
"""Forgot-check-out reminders.

A member visit is "forgotten" when it is still open and either started on an earlier day, or today's closing time
of that branch has passed. The member gets ONE bell + push per visit (dedupe key); the visit stays open — the member
checks out from the app. Triggered when the member opens the app, and by POST /api/v1/jobs/forgot-checkout (called by
an external scheduler with the X-Cron-Key header, e.g. every 30 minutes). No secret = endpoint disabled.
"""
import hmac

from fastapi import APIRouter, Depends, Header, HTTPException
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.db.session import get_db
from app.modules.notifications.router import notify_users
from app.modules.workspaces.access import now_tz

S = "grapion_one_x."
router = APIRouter(prefix="/jobs", tags=["Scheduled jobs"])


async def notify_forgot_checkouts(db: AsyncSession, member_profile_id=None) -> int:
    """Send the reminder for every forgotten visit (or only this member's). Caller commits. Returns how many were sent."""
    now = now_tz()
    rows = (await db.execute(text(f"""
        SELECT a.id, a.check_in_at, wm.user_id, w.id AS workspace_id, w.name AS gym, a.branch_id, h.close_time
          FROM {S}gym_member_attendance a
          JOIN {S}gym_member_profiles p ON p.id = a.member_profile_id
          JOIN {S}workspace_members wm ON wm.id = p.workspace_member_id AND wm.status = 'active'
          JOIN {S}module_workspaces w ON w.id = wm.workspace_id
          LEFT JOIN {S}gym_branch_hours h ON h.branch_id = a.branch_id
                AND h.weekday = EXTRACT(ISODOW FROM (a.check_in_at AT TIME ZONE :tz))
         WHERE a.check_out_at IS NULL AND (CAST(:p AS uuid) IS NULL OR a.member_profile_id = CAST(:p AS uuid))"""),
        {"tz": settings.APP_TIMEZONE, "p": str(member_profile_id) if member_profile_id else None})).mappings().all()
    sent = 0
    for r in rows:
        cin = r["check_in_at"].astimezone(now.tzinfo)
        same_day = cin.date() == now.date()
        if same_day and (r["close_time"] is None or now.time() < r["close_time"]):
            continue  # still within today's opening hours (no hours set = only remind from the next day)
        key = f"forgot_checkout:{r['id']}"
        if (await db.execute(text(f"SELECT 1 FROM {S}notifications WHERE dedupe_key = :k"), {"k": f"{key}:{r['user_id']}"})).first():
            continue  # already reminded for this visit
        day = "today" if same_day else f"on {cin.strftime('%d %b')}"
        await notify_users(db, [r["user_id"]], category="checkout", title=f"{r['gym']}: you forgot to check out",
                           message=f"You checked in {day} at {cin.strftime('%I:%M %p').lstrip('0')} but did not check out. "
                                   "Open the app and tap Check Out.",
                           workspace_id=r["workspace_id"], branch_id=r["branch_id"], dedupe_prefix=key)
        sent += 1
    return sent


@router.post("/forgot-checkout")
async def forgot_checkout_job(x_cron_key: str | None = Header(None), db: AsyncSession = Depends(get_db)):
    if not settings.CRON_KEY or not x_cron_key or not hmac.compare_digest(x_cron_key, settings.CRON_KEY):
        raise HTTPException(status_code=404, detail="Not found")  # looks absent to anyone without the key
    sent = await notify_forgot_checkouts(db)
    await db.commit()
    return {"reminders_sent": sent}
