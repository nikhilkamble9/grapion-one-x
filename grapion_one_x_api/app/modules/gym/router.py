# //Added By Nikhil 22Nov26 08:41 For Grapion Gym owner API: dashboard, branches, timings, holidays, plans, batches, shifts, staff, members, memberships, payments, check-in
"""Every route: load_access (member of this business + owner's subscription active) → permission for the branch.

All SQL is parameterised (text() with bind values). Money is integer paise; the API takes whole rupees
(or rupees with 2 decimals for payments) and converts. Dates are IST business dates.
"""
import calendar
import re
import secrets
import string
from datetime import date, datetime, time, timedelta
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field, field_validator, model_validator
from sqlalchemy import select, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.dependencies import get_current_user
from app.core.security import hash_password
from app.db.models import ModuleRole, User, WorkspaceMember
from app.db.session import get_db
from app.modules.notifications.router import notify_users
from app.modules.workspaces.access import Access, audit, load_access, now_tz
from app.modules.workspaces.router import init_gym_branch

router = APIRouter(prefix="/gym/{workspace_id}", tags=["Grapion Gym"])
S = "grapion_one_x."


# ======================= helpers =======================

def _uuid(v: str | None, what: str) -> UUID:
    try:
        return UUID(str(v))
    except (ValueError, TypeError):
        raise HTTPException(status_code=404, detail=f"{what} not found")


def _today() -> date:
    return now_tz().date()


def _day_bounds(d: date) -> tuple[datetime, datetime]:
    tz = now_tz().tzinfo
    start = datetime.combine(d, time(0, 0), tz)
    return start, start + timedelta(days=1)


def _add_months(d: date, months: int) -> date:
    m = d.month - 1 + months
    y, m = d.year + m // 12, m % 12 + 1
    return date(y, m, min(d.day, calendar.monthrange(y, m)[1]))


def _rupees_to_paise(v: float) -> int:
    return int(round(v * 100))


def _t(v) -> str | None:
    return v.strftime("%H:%M") if v else None


async def _branches(db: AsyncSession, acc: Access) -> list[dict]:
    """Branches the caller can see: owner → all active branches; others → branches they hold a role in."""
    rows = (await db.execute(text(
        f"SELECT id, name, address, phone, status FROM {S}workspace_branches "
        "WHERE workspace_id = :w AND status = 'active' ORDER BY created_at"), {"w": acc.workspace.id})).mappings().all()
    if acc.is_owner:
        return [dict(r) for r in rows]
    mine = {r.branch_id for r in acc.roles}
    return [dict(r) for r in rows if r["id"] in mine]


async def _branch(db: AsyncSession, acc: Access, branch_id, perm: str | None) -> UUID:
    """Branch must belong to this business (stops cross-business IDOR) and caller must hold `perm` there."""
    bid = _uuid(branch_id, "Branch")
    ok = (await db.execute(text(
        f"SELECT 1 FROM {S}workspace_branches WHERE id = :b AND workspace_id = :w AND status = 'active'"),
        {"b": bid, "w": acc.workspace.id})).first()
    if not ok:
        raise HTTPException(status_code=404, detail="Branch not found")
    if perm is None:
        if not acc.is_owner and bid not in {r.branch_id for r in acc.roles}:
            raise HTTPException(status_code=404, detail="Branch not found")
    elif not acc.can(perm, bid):
        raise HTTPException(status_code=403, detail="You do not have permission for this action")
    return bid


async def _scope(db: AsyncSession, acc: Access, branch_id: str | None, perm: str) -> list[UUID]:
    """One branch (checked) or every visible branch where the caller has `perm`."""
    if branch_id:
        return [await _branch(db, acc, branch_id, perm)]
    ids = [b["id"] for b in await _branches(db, acc) if acc.can(perm, b["id"])]
    if not ids:
        raise HTTPException(status_code=403, detail="You do not have permission for this action")
    return ids


async def _branch_people(db: AsyncSession, branch_ids: list[UUID]) -> list[UUID]:
    """Everyone active in these branches (members + staff) — used for holiday / timing notices."""
    rows = (await db.execute(text(
        f"SELECT DISTINCT user_id FROM {S}workspace_members WHERE branch_id = ANY(:b) AND status = 'active'"),
        {"b": branch_ids})).all()
    return [r[0] for r in rows]


async def _role(db: AsyncSession, acc: Access, code: str) -> ModuleRole:
    r = (await db.execute(select(ModuleRole).where(
        ModuleRole.module_id == acc.workspace.module_id, ModuleRole.code == code, ModuleRole.is_active == True
    ))).scalar_one_or_none()
    if not r:
        raise HTTPException(status_code=400, detail="Invalid role")
    return r


# ---- new login with a temporary password (no OTP; owner shares it in person) ----

class NewLogin(BaseModel):
    first_name: str = Field(..., min_length=1, max_length=100)
    last_name: str = Field(..., min_length=1, max_length=100)
    username: str = Field(..., min_length=3, max_length=50, pattern=r"^[A-Za-z0-9_.]+$")
    country_code: str = Field("IN", min_length=2, max_length=10)
    dial_code: str = Field("+91", pattern=r"^\+[0-9]{1,4}$")
    mobile_number: str = Field(..., min_length=6, max_length=20)
    email: str | None = Field(None, max_length=255, pattern=r"^$|^[^@\s]+@[^@\s]+\.[^@\s]+$")

    @field_validator("mobile_number")
    @classmethod
    def digits(cls, v: str) -> str:
        v = re.sub(r"[\s-]", "", v)
        if not v.isdigit():
            raise ValueError("Mobile number must contain digits only")
        return v


def _temp_password() -> str:
    # 10 chars, always has upper, lower, digit — shown once to the owner, never stored in plain text or logged.
    alphabet = string.ascii_letters + string.digits
    while True:
        p = "".join(secrets.choice(alphabet) for _ in range(10))
        if any(c.islower() for c in p) and any(c.isupper() for c in p) and any(c.isdigit() for c in p):
            return p


async def _create_login(db: AsyncSession, req: NewLogin) -> tuple[User, str]:
    uname = req.username.strip()
    email = (req.email or "").strip() or f"{uname.lower()}@members.invalid"  # reserved TLD: no real mailbox; user can change it in Profile
    if (await db.execute(select(User.id).where(User.username_clean == uname.lower()))).first():
        raise HTTPException(status_code=400, detail="Username already taken")
    if (await db.execute(select(User.id).where(User.email_clean == email.lower()))).first():
        raise HTTPException(status_code=400, detail="Email already registered")
    if (await db.execute(select(User.id).where(User.dial_code == req.dial_code, User.mobile_number == req.mobile_number))).first():
        raise HTTPException(status_code=400, detail="This mobile number already has an account — add them with Search instead")
    pwd = _temp_password()
    now = now_tz()
    u = User(first_name=req.first_name.strip(), last_name=req.last_name.strip(), username=uname, email=email,
             password_hash=hash_password(pwd), country_code=req.country_code.strip().upper(), dial_code=req.dial_code,
             mobile_number=req.mobile_number, role="user", is_active=True, must_change_password=True,
             created_at=now, updated_at=now)
    db.add(u)
    await db.flush()
    return u, pwd


# ======================= dashboard =======================

@router.get("/overview")
async def overview(workspace_id: str, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    acc = await load_access(db, user, workspace_id)
    branches = await _branches(db, acc)
    ids = [b["id"] for b in branches if acc.can("gym.members.view", b["id"])]
    today = _today()
    start, end = _day_bounds(today)
    month_start = today.replace(day=1)
    stats = {}
    if ids:
        rows = (await db.execute(text(f"""
            WITH latest AS (
                SELECT DISTINCT ON (ms.member_profile_id) ms.member_profile_id, ms.branch_id, ms.start_date, ms.expiry_date
                  FROM {S}gym_memberships ms
                 WHERE ms.status = 'active' AND ms.branch_id = ANY(:b)
                 ORDER BY ms.member_profile_id, ms.expiry_date DESC)
            SELECT b.id,
                   (SELECT count(*) FROM {S}gym_member_profiles p JOIN {S}workspace_members wm ON wm.id = p.workspace_member_id
                     WHERE p.branch_id = b.id AND wm.status IN ('active','invited')) AS members,
                   (SELECT count(DISTINCT ms.member_profile_id) FROM {S}gym_memberships ms WHERE ms.branch_id = b.id AND ms.status = 'active'
                       AND ms.start_date <= :today AND ms.expiry_date >= :today) AS active,  -- any plan covering today (a future renewal must not hide it)
                   (SELECT count(*) FROM latest l WHERE l.branch_id = b.id AND l.expiry_date >= :today
                       AND l.expiry_date <= CAST(:today AS date) + COALESCE(s.reminder_lead_days, 7)) AS expiring,
                   (SELECT count(*) FROM latest l WHERE l.branch_id = b.id AND l.expiry_date < :today) AS expired,
                   (SELECT count(*) FROM {S}gym_member_attendance a WHERE a.branch_id = b.id AND a.check_in_at >= :ds AND a.check_in_at < :de) AS visits_today,
                   (SELECT count(*) FROM {S}gym_member_attendance a WHERE a.branch_id = b.id AND a.check_out_at IS NULL) AS inside_now,
                   (SELECT count(*) FROM {S}gym_payments p WHERE p.branch_id = b.id AND p.status = 'pending') AS pending_payments,
                   (SELECT COALESCE(sum(amount_paise), 0) FROM {S}gym_payments p WHERE p.branch_id = b.id AND p.status = 'verified'
                       AND p.paid_on >= :ms) AS month_revenue_paise,
                   (SELECT count(*) FROM {S}workspace_members wm JOIN {S}module_roles r ON r.id = wm.role_id
                     WHERE wm.branch_id = b.id AND wm.status = 'active' AND r.is_staff) AS staff,
                   (SELECT h.reason FROM {S}gym_holidays h WHERE h.branch_id = b.id AND h.is_active AND h.holiday_date = :today LIMIT 1) AS holiday_today
              FROM {S}workspace_branches b LEFT JOIN {S}gym_branch_settings s ON s.branch_id = b.id
             WHERE b.id = ANY(:b)"""), {"b": ids, "today": today, "ds": start, "de": end, "ms": month_start})).mappings().all()
        can_money = {bid for bid in ids if acc.can("gym.reports.view", bid) or acc.can("gym.payments.verify", bid)}
        for r in rows:
            d = {k: (int(v) if isinstance(v, int) else v) for k, v in r.items() if k != "id"}
            if r["id"] not in can_money:
                d["month_revenue_paise"] = None  # receptionists / trainers do not see revenue
            stats[r["id"]] = d
    keys = ("members", "active", "expiring", "expired", "visits_today", "inside_now", "pending_payments", "staff")
    totals = {k: sum((s[k] or 0) for s in stats.values()) for k in keys}
    money = [s["month_revenue_paise"] for s in stats.values() if s["month_revenue_paise"] is not None]
    totals["month_revenue_paise"] = sum(money) if money else None
    return {
        "today": today.isoformat(),
        "workspace": {"id": str(acc.workspace.id), "name": acc.workspace.name},
        "is_owner": acc.is_owner,
        "permissions": sorted(set().union(*acc.permissions.values())) if acc.permissions else [],
        "branches": [{**{k: (str(v) if k == "id" else v) for k, v in b.items()}, "stats": stats.get(b["id"])} for b in branches],
        "totals": totals,
    }


# ======================= branches, settings, timings =======================

class BranchRequest(BaseModel):
    name: str = Field(..., min_length=2, max_length=120)
    address: str | None = Field(None, max_length=500)
    phone: str | None = Field(None, max_length=20, pattern=r"^[0-9+\-\s]*$")


@router.get("/branches")
async def list_branches(workspace_id: str, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    acc = await load_access(db, user, workspace_id)
    return {"branches": [{**b, "id": str(b["id"])} for b in await _branches(db, acc)],
            "can_add": acc.can("gym.business.manage") and acc.is_owner}


@router.post("/branches", status_code=201)
async def add_branch(workspace_id: str, req: BranchRequest, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    acc = await load_access(db, user, workspace_id)
    if not acc.is_owner:
        raise HTTPException(status_code=403, detail="Only the owner can add branches")
    now = now_tz()
    bid = (await db.execute(text(
        f"INSERT INTO {S}workspace_branches (workspace_id, name, address, phone, status, created_at, updated_at, created_by, modified_by) "
        "VALUES (:w, :n, :a, :p, 'active', :now, :now, :u, :u) RETURNING id"),
        {"w": acc.workspace.id, "n": req.name.strip(), "a": req.address, "p": req.phone, "now": now, "u": user.id})).scalar_one()
    await init_gym_branch(db, bid, user.id)
    audit(db, user, "branch.created", "workspace_branches", bid, acc.workspace.id, {"name": req.name})
    await db.commit()
    return {"id": str(bid)}


@router.put("/branches/{branch_id}")
async def edit_branch(workspace_id: str, branch_id: str, req: BranchRequest, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    acc = await load_access(db, user, workspace_id)
    bid = await _branch(db, acc, branch_id, "gym.business.manage")
    await db.execute(text(
        f"UPDATE {S}workspace_branches SET name = :n, address = :a, phone = :p, updated_at = :now, modified_by = :u WHERE id = :b"),
        {"n": req.name.strip(), "a": req.address, "p": req.phone, "now": now_tz(), "u": user.id, "b": bid})
    audit(db, user, "branch.updated", "workspace_branches", bid, acc.workspace.id, req.model_dump())
    await db.commit()
    return {"status": "updated"}


@router.get("/branches/{branch_id}/setup")
async def branch_setup(workspace_id: str, branch_id: str, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """Settings + weekly timings. Everyone in the branch can read timings; settings only with business.manage."""
    acc = await load_access(db, user, workspace_id)
    bid = await _branch(db, acc, branch_id, None)
    hours = (await db.execute(text(
        f"SELECT weekday, is_closed, open_time, close_time FROM {S}gym_branch_hours WHERE branch_id = :b ORDER BY weekday"),
        {"b": bid})).mappings().all()
    out = {"hours": [{"weekday": h["weekday"], "is_closed": h["is_closed"], "open": _t(h["open_time"]), "close": _t(h["close_time"])} for h in hours],
           "can_edit_hours": acc.can("gym.holidays.edit", bid), "can_edit_settings": acc.can("gym.business.manage", bid)}
    if out["can_edit_settings"]:
        s = (await db.execute(text(
            f"SELECT late_grace_minutes, half_day_after_minutes, early_out_grace_minutes, reminder_lead_days, upi_id, upi_payee_name "
            f"FROM {S}gym_branch_settings WHERE branch_id = :b"), {"b": bid})).mappings().first()
        out["settings"] = dict(s) if s else None
    return out


class HourRow(BaseModel):
    weekday: int = Field(..., ge=1, le=7)
    is_closed: bool
    open: str | None = Field(None, pattern=r"^([01][0-9]|2[0-3]):[0-5][0-9]$")
    close: str | None = Field(None, pattern=r"^([01][0-9]|2[0-3]):[0-5][0-9]$")

    @model_validator(mode="after")
    def check(self):
        if not self.is_closed and (not self.open or not self.close or self.close <= self.open):
            raise ValueError("Open days need an opening time before the closing time")
        return self


class HoursRequest(BaseModel):
    hours: list[HourRow] = Field(..., min_length=7, max_length=7)
    notify: bool = True


@router.put("/branches/{branch_id}/hours")
async def set_hours(workspace_id: str, branch_id: str, req: HoursRequest, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    acc = await load_access(db, user, workspace_id)
    bid = await _branch(db, acc, branch_id, "gym.holidays.edit")
    if sorted(h.weekday for h in req.hours) != list(range(1, 8)):
        raise HTTPException(status_code=400, detail="Send all 7 days once")
    for h in req.hours:
        await db.execute(text(
            f"INSERT INTO {S}gym_branch_hours (branch_id, weekday, is_closed, open_time, close_time, created_by, modified_by) "
            "VALUES (:b, :wd, :c, :o, :cl, :u, :u) ON CONFLICT (branch_id, weekday) DO UPDATE SET is_closed = EXCLUDED.is_closed, "
            "open_time = EXCLUDED.open_time, close_time = EXCLUDED.close_time, updated_at = now(), modified_by = EXCLUDED.modified_by"),
            {"b": bid, "wd": h.weekday, "c": h.is_closed,
             "o": None if h.is_closed else time.fromisoformat(h.open), "cl": None if h.is_closed else time.fromisoformat(h.close), "u": user.id})
    audit(db, user, "branch.hours_updated", "gym_branch_hours", bid, acc.workspace.id, req.model_dump())
    if req.notify:
        name = (await db.execute(text(f"SELECT name FROM {S}workspace_branches WHERE id = :b"), {"b": bid})).scalar_one()
        await notify_users(db, [u for u in await _branch_people(db, [bid]) if u != user.id], category="timings",
                           title=f"{acc.workspace.name}: timings updated",
                           message=f"{name} has new opening hours. Open the app to see them.",
                           workspace_id=acc.workspace.id, branch_id=bid, actor_id=user.id)
    await db.commit()
    return {"status": "updated"}


class SettingsRequest(BaseModel):
    late_grace_minutes: int = Field(..., ge=0, le=120)
    half_day_after_minutes: int = Field(..., ge=0, le=240)
    early_out_grace_minutes: int = Field(..., ge=0, le=120)
    reminder_lead_days: int = Field(..., ge=1, le=60)
    upi_id: str | None = Field(None, max_length=100, pattern=r"^$|^[A-Za-z0-9.\-_]{2,}@[A-Za-z]{2,}$")
    upi_payee_name: str | None = Field(None, max_length=100)

    @model_validator(mode="after")
    def check(self):
        if self.half_day_after_minutes < self.late_grace_minutes:
            raise ValueError("Half-day minutes must be at least the late grace minutes")
        return self


@router.put("/branches/{branch_id}/settings")
async def set_settings(workspace_id: str, branch_id: str, req: SettingsRequest, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    acc = await load_access(db, user, workspace_id)
    bid = await _branch(db, acc, branch_id, "gym.business.manage")
    await db.execute(text(
        f"UPDATE {S}gym_branch_settings SET late_grace_minutes = :lg, half_day_after_minutes = :hd, early_out_grace_minutes = :eo, "
        "reminder_lead_days = :rd, upi_id = NULLIF(:upi, ''), upi_payee_name = NULLIF(:payee, ''), updated_at = now(), modified_by = :u WHERE branch_id = :b"),
        {"lg": req.late_grace_minutes, "hd": req.half_day_after_minutes, "eo": req.early_out_grace_minutes,
         "rd": req.reminder_lead_days, "upi": req.upi_id or "", "payee": req.upi_payee_name or "", "u": user.id, "b": bid})
    audit(db, user, "branch.settings_updated", "gym_branch_settings", bid, acc.workspace.id, req.model_dump())
    await db.commit()
    return {"status": "updated"}


# ======================= holidays =======================

class HolidayRequest(BaseModel):
    holiday_date: date
    reason: str = Field(..., min_length=2, max_length=200)
    branch_id: str | None = None  # None = every branch (owner only)


@router.get("/holidays")
async def list_holidays(workspace_id: str, branch_id: str | None = None, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    acc = await load_access(db, user, workspace_id)
    ids = [await _branch(db, acc, branch_id, None)] if branch_id else [b["id"] for b in await _branches(db, acc)]
    rows = (await db.execute(text(
        f"SELECT h.id, h.branch_id, b.name AS branch_name, h.holiday_date, h.reason FROM {S}gym_holidays h "
        f"JOIN {S}workspace_branches b ON b.id = h.branch_id WHERE h.branch_id = ANY(:b) AND h.is_active "
        "AND h.holiday_date >= :from ORDER BY h.holiday_date, b.name LIMIT 200"),
        {"b": ids, "from": _today() - timedelta(days=30)})).mappings().all()
    return {"holidays": [{"id": str(r["id"]), "branch_id": str(r["branch_id"]), "branch_name": r["branch_name"],
                          "date": r["holiday_date"].isoformat(), "reason": r["reason"],
                          "can_remove": acc.can("gym.holidays.edit", r["branch_id"])} for r in rows]}


@router.post("/holidays", status_code=201)
async def add_holiday(workspace_id: str, req: HolidayRequest, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    acc = await load_access(db, user, workspace_id)
    if req.holiday_date < _today():
        raise HTTPException(status_code=400, detail="Pick today or a future date")
    if req.branch_id:
        ids = [await _branch(db, acc, req.branch_id, "gym.holidays.edit")]
    else:
        if not acc.is_owner:
            raise HTTPException(status_code=403, detail="Only the owner can set a holiday for every branch")
        ids = [b["id"] for b in await _branches(db, acc)]
    added = []
    for bid in ids:
        r = (await db.execute(text(
            f"INSERT INTO {S}gym_holidays (branch_id, holiday_date, reason, created_by, modified_by) VALUES (:b, :d, :r, :u, :u) "
            "ON CONFLICT (branch_id, holiday_date) WHERE is_active DO NOTHING RETURNING id"),
            {"b": bid, "d": req.holiday_date, "r": req.reason.strip(), "u": user.id})).first()
        if r:
            added.append(bid)
    if not added:
        raise HTTPException(status_code=400, detail="A holiday is already set on this date")
    audit(db, user, "holiday.added", "gym_holidays", None, acc.workspace.id,
          {"date": req.holiday_date.isoformat(), "reason": req.reason, "branches": [str(b) for b in added]})
    people = [u for u in await _branch_people(db, added) if u != user.id]
    await notify_users(db, people, category="holiday", title=f"{acc.workspace.name}: holiday on {req.holiday_date.strftime('%d %b %Y')}",
                       message=f"The gym will be closed on {req.holiday_date.strftime('%A, %d %b %Y')} — {req.reason.strip()}.",
                       workspace_id=acc.workspace.id, actor_id=user.id,
                       dedupe_prefix=f"holiday:{acc.workspace.id}:{req.holiday_date.isoformat()}")
    await db.commit()
    return {"added_branches": len(added), "notified": len(people)}


@router.post("/holidays/{holiday_id}/remove")
async def remove_holiday(workspace_id: str, holiday_id: str, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    acc = await load_access(db, user, workspace_id)
    hid = _uuid(holiday_id, "Holiday")
    h = (await db.execute(text(
        f"SELECT h.branch_id, h.holiday_date, h.reason FROM {S}gym_holidays h JOIN {S}workspace_branches b ON b.id = h.branch_id "
        "WHERE h.id = :h AND b.workspace_id = :w AND h.is_active"), {"h": hid, "w": acc.workspace.id})).mappings().first()
    if not h:
        raise HTTPException(status_code=404, detail="Holiday not found")
    await _branch(db, acc, h["branch_id"], "gym.holidays.edit")
    await db.execute(text(f"UPDATE {S}gym_holidays SET is_active = FALSE, updated_at = now(), modified_by = :u WHERE id = :h"), {"u": user.id, "h": hid})
    audit(db, user, "holiday.removed", "gym_holidays", hid, acc.workspace.id, {"date": h["holiday_date"].isoformat()})
    if h["holiday_date"] >= _today():
        await notify_users(db, [u for u in await _branch_people(db, [h["branch_id"]]) if u != user.id], category="holiday",
                           title=f"{acc.workspace.name}: open on {h['holiday_date'].strftime('%d %b %Y')}",
                           message=f"The holiday on {h['holiday_date'].strftime('%d %b %Y')} ({h['reason']}) is cancelled — the gym is open.",
                           workspace_id=acc.workspace.id, branch_id=h["branch_id"], actor_id=user.id)
    await db.commit()
    return {"status": "removed"}


# ======================= plans =======================

class PlanRequest(BaseModel):
    branch_id: str
    name: str = Field(..., min_length=2, max_length=100)
    duration_months: int = Field(..., ge=1, le=36)
    price: int = Field(..., ge=0, le=10_000_000)  # whole rupees
    description: str | None = Field(None, max_length=500)
    status: str = Field("active", pattern="^(active|inactive)$")


def _plan_out(r) -> dict:
    return {"id": str(r["id"]), "branch_id": str(r["branch_id"]), "name": r["name"], "duration_months": r["duration_months"],
            "price": r["price_paise"] // 100, "description": r["description"], "status": r["status"]}


@router.get("/plans")
async def list_plans(workspace_id: str, branch_id: str | None = None, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    acc = await load_access(db, user, workspace_id)
    ids = await _scope(db, acc, branch_id, "gym.plans.view") if (acc.can("gym.plans.view")) else await _scope(db, acc, branch_id, "gym.self.view")
    rows = (await db.execute(text(
        f"SELECT id, branch_id, name, duration_months, price_paise, description, status FROM {S}gym_plans "
        "WHERE branch_id = ANY(:b) ORDER BY status, duration_months, name"), {"b": ids})).mappings().all()
    can_edit = any(acc.can("gym.plans.edit", b) for b in ids)
    return {"plans": [_plan_out(r) for r in rows if can_edit or r["status"] == "active"], "can_edit": can_edit}


@router.post("/plans", status_code=201)
async def add_plan(workspace_id: str, req: PlanRequest, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    acc = await load_access(db, user, workspace_id)
    bid = await _branch(db, acc, req.branch_id, "gym.plans.edit")
    pid = (await db.execute(text(
        f"INSERT INTO {S}gym_plans (branch_id, name, duration_months, price_paise, description, status, created_by, modified_by) "
        "VALUES (:b, :n, :d, :p, :desc, :s, :u, :u) RETURNING id"),
        {"b": bid, "n": req.name.strip(), "d": req.duration_months, "p": req.price * 100, "desc": req.description, "s": req.status, "u": user.id})).scalar_one()
    audit(db, user, "plan.created", "gym_plans", pid, acc.workspace.id, req.model_dump())
    await db.commit()
    return {"id": str(pid)}


@router.put("/plans/{plan_id}")
async def edit_plan(workspace_id: str, plan_id: str, req: PlanRequest, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    acc = await load_access(db, user, workspace_id)
    pid = _uuid(plan_id, "Plan")
    cur = (await db.execute(text(f"SELECT branch_id FROM {S}gym_plans WHERE id = :p"), {"p": pid})).scalar_one_or_none()
    if not cur:
        raise HTTPException(status_code=404, detail="Plan not found")
    await _branch(db, acc, cur, "gym.plans.edit")  # plan stays in its branch
    await db.execute(text(
        f"UPDATE {S}gym_plans SET name = :n, duration_months = :d, price_paise = :p, description = :desc, status = :s, "
        "updated_at = now(), modified_by = :u WHERE id = :id"),
        {"n": req.name.strip(), "d": req.duration_months, "p": req.price * 100, "desc": req.description, "s": req.status, "u": user.id, "id": pid})
    # Memberships already sold keep their own plan_name + amount snapshot.
    audit(db, user, "plan.updated", "gym_plans", pid, acc.workspace.id, req.model_dump())
    await db.commit()
    return {"status": "updated"}


# ======================= batches & shifts =======================

class SlotRequest(BaseModel):
    branch_id: str
    name: str = Field(..., min_length=2, max_length=80)
    start_time: str = Field(..., pattern=r"^([01][0-9]|2[0-3]):[0-5][0-9]$")
    end_time: str = Field(..., pattern=r"^([01][0-9]|2[0-3]):[0-5][0-9]$")
    weekdays: list[int] = Field(..., min_length=1, max_length=7)
    status: str = Field("active", pattern="^(active|inactive)$")
    trainer_member_id: str | None = None  # batches only
    capacity: int | None = Field(None, ge=1, le=1000)  # batches only

    @model_validator(mode="after")
    def check(self):
        if self.end_time <= self.start_time:
            raise ValueError("End time must be after the start time")
        if any(d < 1 or d > 7 for d in self.weekdays):
            raise ValueError("Weekdays are 1 (Mon) to 7 (Sun)")
        self.weekdays = sorted(set(self.weekdays))
        return self


async def _trainer_ok(db: AsyncSession, acc: Access, bid: UUID, member_id: str | None) -> UUID | None:
    if not member_id:
        return None
    mid = _uuid(member_id, "Trainer")
    ok = (await db.execute(text(
        f"SELECT 1 FROM {S}workspace_members wm JOIN {S}module_roles r ON r.id = wm.role_id "
        "WHERE wm.id = :m AND wm.workspace_id = :w AND wm.branch_id = :b AND wm.status = 'active' AND r.code = 'trainer'"),
        {"m": mid, "w": acc.workspace.id, "b": bid})).first()
    if not ok:
        raise HTTPException(status_code=400, detail="Pick an active trainer of this branch")
    return mid


def _slot_out(r) -> dict:
    d = {"id": str(r["id"]), "branch_id": str(r["branch_id"]), "name": r["name"], "start_time": _t(r["start_time"]),
         "end_time": _t(r["end_time"]), "weekdays": list(r["weekdays"] or []), "status": r["status"]}
    if "trainer_member_id" in r:
        d.update(trainer_member_id=str(r["trainer_member_id"]) if r["trainer_member_id"] else None,
                 trainer_name=r["trainer_name"], capacity=r["capacity"], members=r["members"])
    if "staff" in r:
        d["staff"] = r["staff"]
    return d


@router.get("/batches")
async def list_batches(workspace_id: str, branch_id: str | None = None, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    acc = await load_access(db, user, workspace_id)
    ids = await _scope(db, acc, branch_id, "gym.members.view")
    rows = (await db.execute(text(f"""
        SELECT bt.id, bt.branch_id, bt.name, bt.start_time, bt.end_time, bt.weekdays, bt.status, bt.trainer_member_id, bt.capacity,
               (u.first_name || ' ' || u.last_name) AS trainer_name,
               (SELECT count(*) FROM {S}gym_member_profiles p WHERE p.batch_id = bt.id) AS members
          FROM {S}gym_batches bt
          LEFT JOIN {S}workspace_members wm ON wm.id = bt.trainer_member_id
          LEFT JOIN {S}users u ON u.id = wm.user_id
         WHERE bt.branch_id = ANY(:b) ORDER BY bt.status, bt.start_time"""), {"b": ids})).mappings().all()
    return {"batches": [_slot_out(r) for r in rows], "can_edit": any(acc.can("gym.batches.edit", b) for b in ids)}


@router.post("/batches", status_code=201)
async def add_batch(workspace_id: str, req: SlotRequest, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    acc = await load_access(db, user, workspace_id)
    bid = await _branch(db, acc, req.branch_id, "gym.batches.edit")
    tid = await _trainer_ok(db, acc, bid, req.trainer_member_id)
    new_id = (await db.execute(text(
        f"INSERT INTO {S}gym_batches (branch_id, name, start_time, end_time, weekdays, trainer_member_id, capacity, status, created_by, modified_by) "
        "VALUES (:b, :n, :s, :e, CAST(:wd AS smallint[]), :t, :c, :st, :u, :u) RETURNING id"),
        {"b": bid, "n": req.name.strip(), "s": time.fromisoformat(req.start_time), "e": time.fromisoformat(req.end_time),
         "wd": req.weekdays, "t": tid, "c": req.capacity, "st": req.status, "u": user.id})).scalar_one()
    audit(db, user, "batch.created", "gym_batches", new_id, acc.workspace.id, req.model_dump())
    await db.commit()
    return {"id": str(new_id)}


@router.put("/batches/{batch_id}")
async def edit_batch(workspace_id: str, batch_id: str, req: SlotRequest, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    acc = await load_access(db, user, workspace_id)
    xid = _uuid(batch_id, "Batch")
    cur = (await db.execute(text(f"SELECT branch_id FROM {S}gym_batches WHERE id = :x"), {"x": xid})).scalar_one_or_none()
    if not cur:
        raise HTTPException(status_code=404, detail="Batch not found")
    bid = await _branch(db, acc, cur, "gym.batches.edit")
    tid = await _trainer_ok(db, acc, bid, req.trainer_member_id)
    await db.execute(text(
        f"UPDATE {S}gym_batches SET name = :n, start_time = :s, end_time = :e, weekdays = CAST(:wd AS smallint[]), trainer_member_id = :t, "
        "capacity = :c, status = :st, updated_at = now(), modified_by = :u WHERE id = :x"),
        {"n": req.name.strip(), "s": time.fromisoformat(req.start_time), "e": time.fromisoformat(req.end_time), "wd": req.weekdays,
         "t": tid, "c": req.capacity, "st": req.status, "u": user.id, "x": xid})
    audit(db, user, "batch.updated", "gym_batches", xid, acc.workspace.id, req.model_dump())
    await db.commit()
    return {"status": "updated"}


@router.get("/shifts")
async def list_shifts(workspace_id: str, branch_id: str | None = None, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    acc = await load_access(db, user, workspace_id)
    ids = await _scope(db, acc, branch_id, "gym.staff.manage")
    rows = (await db.execute(text(f"""
        SELECT s.id, s.branch_id, s.name, s.start_time, s.end_time, s.weekdays, s.status,
               (SELECT count(*) FROM {S}gym_shift_assignments a WHERE a.shift_id = s.id
                   AND (a.effective_to IS NULL OR a.effective_to >= :today)) AS staff
          FROM {S}gym_shifts s WHERE s.branch_id = ANY(:b) ORDER BY s.status, s.start_time"""), {"b": ids, "today": _today()})).mappings().all()
    return {"shifts": [_slot_out(r) for r in rows]}


@router.post("/shifts", status_code=201)
async def add_shift(workspace_id: str, req: SlotRequest, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    acc = await load_access(db, user, workspace_id)
    bid = await _branch(db, acc, req.branch_id, "gym.staff.manage")
    new_id = (await db.execute(text(
        f"INSERT INTO {S}gym_shifts (branch_id, name, start_time, end_time, weekdays, status, created_by, modified_by) "
        "VALUES (:b, :n, :s, :e, CAST(:wd AS smallint[]), :st, :u, :u) RETURNING id"),
        {"b": bid, "n": req.name.strip(), "s": time.fromisoformat(req.start_time), "e": time.fromisoformat(req.end_time),
         "wd": req.weekdays, "st": req.status, "u": user.id})).scalar_one()
    audit(db, user, "shift.created", "gym_shifts", new_id, acc.workspace.id, req.model_dump())
    await db.commit()
    return {"id": str(new_id)}


@router.put("/shifts/{shift_id}")
async def edit_shift(workspace_id: str, shift_id: str, req: SlotRequest, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    acc = await load_access(db, user, workspace_id)
    xid = _uuid(shift_id, "Shift")
    cur = (await db.execute(text(f"SELECT branch_id FROM {S}gym_shifts WHERE id = :x"), {"x": xid})).scalar_one_or_none()
    if not cur:
        raise HTTPException(status_code=404, detail="Shift not found")
    await _branch(db, acc, cur, "gym.staff.manage")
    #Added By Nikhil 22Nov26 10:47 For staff must keep at least one shift: block switching off someone's only shift START
    if req.status != "active":
        only = (await db.execute(text(
            f"SELECT count(*) FROM {S}gym_shift_assignments a JOIN {S}workspace_members wm ON wm.id = a.workspace_member_id "
            "WHERE a.shift_id = :x AND wm.status = 'active' AND (a.effective_to IS NULL OR a.effective_to >= :t) "
            f"AND NOT EXISTS (SELECT 1 FROM {S}gym_shift_assignments b JOIN {S}gym_shifts s2 ON s2.id = b.shift_id "
            "  WHERE b.workspace_member_id = a.workspace_member_id AND b.shift_id <> :x AND s2.status = 'active' "
            "  AND (b.effective_to IS NULL OR b.effective_to >= :t))"),
            {"x": xid, "t": _today()})).scalar_one()
        if only:
            raise HTTPException(status_code=400, detail=f"{only} staff member(s) have only this shift. Give them another shift first.")
    #Added By Nikhil 22Nov26 10:47 For staff must keep at least one shift: block switching off someone's only shift END
    await db.execute(text(
        f"UPDATE {S}gym_shifts SET name = :n, start_time = :s, end_time = :e, weekdays = CAST(:wd AS smallint[]), status = :st, "
        "updated_at = now(), modified_by = :u WHERE id = :x"),
        {"n": req.name.strip(), "s": time.fromisoformat(req.start_time), "e": time.fromisoformat(req.end_time), "wd": req.weekdays,
         "st": req.status, "u": user.id, "x": xid})
    audit(db, user, "shift.updated", "gym_shifts", xid, acc.workspace.id, req.model_dump())
    await db.commit()
    return {"status": "updated"}


# ======================= staff =======================

def _can_see_pay(acc: Access, branch_id: UUID, role_code: str, member_user_id: UUID, me: User) -> bool:
    """Owner: everyone. Manager: own branch, but not other managers. Staff: only themselves."""
    if member_user_id == me.id:
        return True
    if not acc.can("gym.staff.view_pay", branch_id):
        return False
    return acc.is_owner or role_code != "manager"


@router.get("/staff")
async def list_staff(workspace_id: str, branch_id: str | None = None, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    acc = await load_access(db, user, workspace_id)
    ids = await _scope(db, acc, branch_id, "gym.staff.manage")
    rows = (await db.execute(text(f"""
        SELECT wm.id, wm.branch_id, b.name AS branch_name, wm.status, wm.user_id, r.code AS role_code, r.name AS role_name, r.rank,
               u.first_name, u.last_name, u.username, u.dial_code, u.mobile_number,
               sp.specialization, sp.joining_date, sp.pay_amount_paise, sp.pay_period,
               COALESCE((SELECT array_agg(a.shift_id::text) FROM {S}gym_shift_assignments a
                          WHERE a.workspace_member_id = wm.id AND (a.effective_to IS NULL OR a.effective_to >= :today)), '{{}}') AS shift_ids
          FROM {S}workspace_members wm
          JOIN {S}module_roles r ON r.id = wm.role_id AND r.is_staff
          JOIN {S}users u ON u.id = wm.user_id
          JOIN {S}workspace_branches b ON b.id = wm.branch_id
          LEFT JOIN {S}gym_staff_profiles sp ON sp.workspace_member_id = wm.id
         WHERE wm.workspace_id = :w AND wm.branch_id = ANY(:b) AND wm.status IN ('active','invited')
         ORDER BY r.rank, u.first_name"""), {"w": acc.workspace.id, "b": ids, "today": _today()})).mappings().all()
    out = []
    for r in rows:
        see_pay = _can_see_pay(acc, r["branch_id"], r["role_code"], r["user_id"], user)
        out.append({
            "member_id": str(r["id"]), "branch_id": str(r["branch_id"]), "branch_name": r["branch_name"], "status": r["status"],
            "role_code": r["role_code"], "role_name": r["role_name"],
            "name": f"{r['first_name']} {r['last_name']}", "username": r["username"], "mobile": f"{r['dial_code']} {r['mobile_number']}",
            "specialization": r["specialization"], "joining_date": r["joining_date"].isoformat() if r["joining_date"] else None,
            "pay": (r["pay_amount_paise"] // 100 if r["pay_amount_paise"] is not None else None) if see_pay else None,
            "pay_period": r["pay_period"] if see_pay else None, "pay_visible": see_pay,
            "shift_ids": list(r["shift_ids"] or []),
            "can_edit": acc.is_owner or r["rank"] > acc.best_role.rank,
        })
    return {"staff": out}


class NewStaffRequest(BaseModel):
    branch_id: str
    role_code: str = Field(..., pattern="^(manager|receptionist|trainer)$")
    login: NewLogin
    shift_ids: list[str] = Field(..., min_length=1, max_length=10)  #Added By Nikhil 22Nov26 10:47 For staff cannot exist without a shift


@router.post("/staff", status_code=201)
async def create_staff_login(workspace_id: str, req: NewStaffRequest, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """Owner/manager creates the login (temporary password). Existing users are added via /workspaces/{id}/invites instead."""
    acc = await load_access(db, user, workspace_id)
    bid = await _branch(db, acc, req.branch_id, "gym.staff.manage")
    role = await _role(db, acc, req.role_code)
    if not acc.is_owner and role.rank <= acc.best_role.rank:
        raise HTTPException(status_code=403, detail="You can only add roles below your own")
    #Added By Nikhil 22Nov26 10:47 For shifts validated before the login is created (no half-made accounts) START
    wanted = {_uuid(s, "Shift") for s in req.shift_ids}
    valid = {r[0] for r in (await db.execute(text(
        f"SELECT id FROM {S}gym_shifts WHERE id = ANY(:s) AND branch_id = :b AND status = 'active'"),
        {"s": list(wanted), "b": bid})).all()}
    if valid != wanted:
        raise HTTPException(status_code=400, detail="Pick active shifts of this branch")
    #Added By Nikhil 22Nov26 10:47 For shifts validated before the login is created (no half-made accounts) END
    u, pwd = await _create_login(db, req.login)
    now = now_tz()
    m = WorkspaceMember(workspace_id=acc.workspace.id, branch_id=bid, user_id=u.id, role_id=role.id, status="active",
                        invited_by=user.id, responded_at=now, created_at=now, updated_at=now, created_by=user.id, modified_by=user.id)
    db.add(m)
    await db.flush()
    #Added By Nikhil 22Nov26 10:47 For shift assignments from today START
    for sid in wanted:
        await db.execute(text(
            f"INSERT INTO {S}gym_shift_assignments (shift_id, workspace_member_id, effective_from, created_by, modified_by) VALUES (:s, :m, :f, :u, :u)"),
            {"s": sid, "m": m.id, "f": _today(), "u": user.id})
    #Added By Nikhil 22Nov26 10:47 For shift assignments from today END
    audit(db, user, "staff.login_created", "workspace_members", m.id, acc.workspace.id, {"role": role.code, "username": u.username})
    await db.commit()
    return {"member_id": str(m.id), "username": u.username, "temporary_password": pwd}


class StaffProfileRequest(BaseModel):
    specialization: str | None = Field(None, max_length=100)
    joining_date: date | None = None
    pay: int | None = Field(None, ge=0, le=100_000_000)  # whole rupees
    pay_period: str | None = Field(None, pattern="^(monthly|per_shift|hourly)$")
    shift_ids: list[str] = Field(default_factory=list, max_length=10)


async def _staff_target(db: AsyncSession, acc: Access, member_id: str):
    mid = _uuid(member_id, "Staff member")
    t = (await db.execute(text(
        f"SELECT wm.id, wm.branch_id, wm.user_id, r.code, r.rank FROM {S}workspace_members wm JOIN {S}module_roles r ON r.id = wm.role_id "
        "WHERE wm.id = :m AND wm.workspace_id = :w AND r.is_staff AND wm.status IN ('active','invited')"),
        {"m": mid, "w": acc.workspace.id})).mappings().first()
    if not t:
        raise HTTPException(status_code=404, detail="Staff member not found")
    if not acc.can("gym.staff.manage", t["branch_id"]):
        raise HTTPException(status_code=403, detail="You do not have permission for this action")
    if not acc.is_owner and t["rank"] <= acc.best_role.rank:
        raise HTTPException(status_code=403, detail="You can only change staff below your own role")
    return t


@router.put("/staff/{member_id}")
async def edit_staff(workspace_id: str, member_id: str, req: StaffProfileRequest, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    acc = await load_access(db, user, workspace_id)
    t = await _staff_target(db, acc, member_id)
    can_pay = _can_see_pay(acc, t["branch_id"], t["code"], t["user_id"], user) and t["user_id"] != user.id
    await db.execute(text(
        f"INSERT INTO {S}gym_staff_profiles (workspace_member_id, specialization, joining_date, pay_amount_paise, pay_period, created_by, modified_by) "
        "VALUES (:m, :sp, :jd, :pay, :pp, :u, :u) ON CONFLICT (workspace_member_id) DO UPDATE SET specialization = EXCLUDED.specialization, "
        "joining_date = EXCLUDED.joining_date, updated_at = now(), modified_by = EXCLUDED.modified_by"
        + (", pay_amount_paise = EXCLUDED.pay_amount_paise, pay_period = EXCLUDED.pay_period" if can_pay else "")),
        {"m": t["id"], "sp": req.specialization, "jd": req.joining_date,
         "pay": req.pay * 100 if (can_pay and req.pay is not None) else None, "pp": req.pay_period if can_pay else None, "u": user.id})
    # Shifts: end the ones removed (history kept), start the new ones from today.
    wanted = {_uuid(s, "Shift") for s in req.shift_ids}
    if wanted:
        valid = {r[0] for r in (await db.execute(text(
            f"SELECT id FROM {S}gym_shifts WHERE id = ANY(:s) AND branch_id = :b AND status = 'active'"),
            {"s": list(wanted), "b": t["branch_id"]})).all()}
        if valid != wanted:
            raise HTTPException(status_code=400, detail="Pick active shifts of this staff member's branch")
    today = _today()
    current = {r[0]: r[1] for r in (await db.execute(text(
        f"SELECT shift_id, id FROM {S}gym_shift_assignments WHERE workspace_member_id = :m AND (effective_to IS NULL OR effective_to >= :t)"),
        {"m": t["id"], "t": today})).all()}
    if current and not wanted:  #Added By Nikhil 22Nov26 10:47 For staff must keep at least one shift (invited staff may have none until assigned)
        raise HTTPException(status_code=400, detail="Staff must have at least one shift")  #Added By Nikhil 22Nov26 10:47 For staff must keep at least one shift
    for sid, aid in current.items():
        if sid not in wanted:
            await db.execute(text(
                f"UPDATE {S}gym_shift_assignments SET effective_to = GREATEST(effective_from, CAST(:y AS date)), updated_at = now(), modified_by = :u WHERE id = :a"),
                {"y": today - timedelta(days=1), "u": user.id, "a": aid})
    for sid in wanted - set(current):
        await db.execute(text(
            f"INSERT INTO {S}gym_shift_assignments (shift_id, workspace_member_id, effective_from, created_by, modified_by) VALUES (:s, :m, :f, :u, :u)"),
            {"s": sid, "m": t["id"], "f": today, "u": user.id})
    audit(db, user, "staff.updated", "gym_staff_profiles", t["id"], acc.workspace.id,
          {"specialization": req.specialization, "pay_changed": can_pay and req.pay is not None, "shifts": sorted(str(s) for s in wanted)})
    await db.commit()
    return {"status": "updated", "pay_saved": can_pay}


@router.post("/staff/{member_id}/remove")
async def remove_staff(workspace_id: str, member_id: str, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    acc = await load_access(db, user, workspace_id)
    t = await _staff_target(db, acc, member_id)
    if t["user_id"] == user.id:
        raise HTTPException(status_code=400, detail="You cannot remove yourself")
    await db.execute(text(f"UPDATE {S}workspace_members SET status = 'removed', updated_at = now(), modified_by = :u WHERE id = :m"),
                     {"u": user.id, "m": t["id"]})
    await db.execute(text(
        f"UPDATE {S}gym_shift_assignments SET effective_to = GREATEST(effective_from, CAST(:t AS date)), updated_at = now() "
        "WHERE workspace_member_id = :m AND effective_to IS NULL"), {"t": _today(), "m": t["id"]})
    await db.execute(text(
        f"UPDATE {S}gym_batches SET trainer_member_id = NULL, updated_at = now(), modified_by = :u WHERE trainer_member_id = :m"),
        {"u": user.id, "m": t["id"]})
    audit(db, user, "staff.removed", "workspace_members", t["id"], acc.workspace.id, {"role": t["code"]})
    await db.commit()
    return {"status": "removed"}


# ======================= members =======================

class MemberProfile(BaseModel):
    gender: str | None = Field(None, pattern="^(male|female|other)$")
    dob: date | None = None
    occupation: str | None = Field(None, max_length=100)
    address: str | None = Field(None, max_length=500)
    emergency_contact: str | None = Field(None, max_length=20, pattern=r"^[0-9+\-\s]*$")
    notes: str | None = Field(None, max_length=1000)
    batch_id: str | None = None
    joined_on: date | None = None


class FirstPayment(BaseModel):
    amount: float = Field(..., gt=0, le=10_000_000)
    method: str = Field(..., pattern="^(cash|upi|card|other)$")
    reference_last_digits: str | None = Field(None, max_length=6, pattern=r"^[0-9A-Za-z]*$")


class AddMemberRequest(BaseModel):
    branch_id: str
    user_id: str | None = None  # existing account found by exact search → invite (they accept)
    login: NewLogin | None = None  # or create a login with a temporary password
    profile: MemberProfile = Field(default_factory=MemberProfile)
    plan_id: str | None = None
    start_date: date | None = None
    payment: FirstPayment | None = None

    @model_validator(mode="after")
    def check(self):
        if bool(self.user_id) == bool(self.login):
            raise ValueError("Pick an existing account OR fill in a new login")
        if self.payment and not self.plan_id:
            raise ValueError("A payment needs a plan")
        return self


async def _batch_ok(db: AsyncSession, bid: UUID, batch_id: str | None) -> UUID | None:
    if not batch_id:
        return None
    x = _uuid(batch_id, "Batch")
    if not (await db.execute(text(f"SELECT 1 FROM {S}gym_batches WHERE id = :x AND branch_id = :b AND status = 'active'"), {"x": x, "b": bid})).first():
        raise HTTPException(status_code=400, detail="Pick an active batch of this branch")
    return x


async def _next_member_code(db: AsyncSession, acc: Access) -> str:
    n = (await db.execute(text(
        f"SELECT count(*) FROM {S}gym_member_profiles p JOIN {S}workspace_branches b ON b.id = p.branch_id WHERE b.workspace_id = :w"),
        {"w": acc.workspace.id})).scalar_one()
    return f"{acc.workspace.short_code}-{n + 1:04d}"


async def _assign_plan(db: AsyncSession, me: User, profile_id: UUID, bid: UUID, plan_id: str, start: date | None) -> dict:
    pid = _uuid(plan_id, "Plan")
    plan = (await db.execute(text(
        f"SELECT id, name, duration_months, price_paise FROM {S}gym_plans WHERE id = :p AND branch_id = :b AND status = 'active'"),
        {"p": pid, "b": bid})).mappings().first()
    if not plan:
        raise HTTPException(status_code=400, detail="Pick an active plan of this branch")
    if start is None:
        # Renewal: continue the day after the current membership ends; otherwise today.
        last = (await db.execute(text(
            f"SELECT max(expiry_date) FROM {S}gym_memberships WHERE member_profile_id = :m AND status = 'active'"), {"m": profile_id})).scalar_one()
        start = max(_today(), last + timedelta(days=1)) if last else _today()
    expiry = _add_months(start, plan["duration_months"]) - timedelta(days=1)
    mid = (await db.execute(text(
        f"INSERT INTO {S}gym_memberships (member_profile_id, branch_id, plan_id, plan_name, start_date, expiry_date, total_amount_paise, created_by, modified_by) "
        "VALUES (:m, :b, :p, :n, :s, :e, :a, :u, :u) RETURNING id"),
        {"m": profile_id, "b": bid, "p": plan["id"], "n": plan["name"], "s": start, "e": expiry, "a": plan["price_paise"], "u": me.id})).scalar_one()
    return {"membership_id": mid, "start_date": start, "expiry_date": expiry, "amount_paise": plan["price_paise"]}


async def _record_payment(db: AsyncSession, acc: Access, me: User, bid: UUID, profile_id: UUID, membership_id, p: FirstPayment,
                          paid_on: date | None = None, notes: str | None = None) -> tuple[UUID, str]:
    verified = acc.can("gym.payments.verify", bid)
    status = "verified" if verified else "pending"  # receptionist-type entries wait for owner/manager to verify
    pid = (await db.execute(text(
        f"INSERT INTO {S}gym_payments (branch_id, member_profile_id, membership_id, amount_paise, method, reference_last_digits, status, paid_on, notes, "
        "recorded_by, verified_by, verified_at, created_by, modified_by) VALUES (:b, :m, :ms, :a, :me, NULLIF(:ref, ''), :st, :d, :n, :u, :vb, :va, :u, :u) RETURNING id"),
        {"b": bid, "m": profile_id, "ms": membership_id, "a": _rupees_to_paise(p.amount), "me": p.method, "ref": p.reference_last_digits or "",
         "st": status, "d": paid_on or _today(), "n": notes, "u": me.id, "vb": me.id if verified else None,
         "va": now_tz() if verified else None})).scalar_one()
    return pid, status


@router.post("/members", status_code=201)
async def add_member(workspace_id: str, req: AddMemberRequest, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    acc = await load_access(db, user, workspace_id)
    bid = await _branch(db, acc, req.branch_id, "gym.members.edit")
    if req.plan_id and not acc.can("gym.memberships.edit", bid):
        raise HTTPException(status_code=403, detail="You cannot assign plans")
    if req.payment and not acc.can("gym.payments.record", bid):
        raise HTTPException(status_code=403, detail="You cannot record payments")
    role = await _role(db, acc, "member")
    if req.plan_id and not (await db.execute(text(
            f"SELECT 1 FROM {S}gym_plans WHERE id = :p AND branch_id = :b AND status = 'active'"),
            {"p": _uuid(req.plan_id, "Plan"), "b": bid})).first():
        raise HTTPException(status_code=400, detail="Pick an active plan of this branch")
    temp_pwd = None
    if req.login:
        member_user, temp_pwd = await _create_login(db, req.login)
        status = "active"
    else:
        member_user = (await db.execute(select(User).where(User.id == _uuid(req.user_id, "User"), User.is_active == True))).scalar_one_or_none()
        if not member_user or member_user.id == acc.workspace.owner_user_id:
            raise HTTPException(status_code=404, detail="User not found")
        status = "invited"
    if (await db.execute(text(
        f"SELECT 1 FROM {S}workspace_members WHERE workspace_id = :w AND user_id = :u AND role_id = :r AND status IN ('active','invited')"),
        {"w": acc.workspace.id, "u": member_user.id, "r": role.id})).first():
        raise HTTPException(status_code=400, detail="This person is already a member of your gym")
    batch = await _batch_ok(db, bid, req.profile.batch_id)
    now = now_tz()
    m = WorkspaceMember(workspace_id=acc.workspace.id, branch_id=bid, user_id=member_user.id, role_id=role.id, status=status,
                        invited_by=user.id, responded_at=now if status == "active" else None,
                        created_at=now, updated_at=now, created_by=user.id, modified_by=user.id)
    db.add(m)
    await db.flush()
    p = req.profile
    profile_id = None
    for _ in range(3):  # member code race: retry with the next number
        code = await _next_member_code(db, acc)
        try:
            async with db.begin_nested():
                profile_id = (await db.execute(text(
                    f"INSERT INTO {S}gym_member_profiles (workspace_member_id, branch_id, member_code, gender, dob, occupation, address, "
                    "emergency_contact, notes, batch_id, joined_on, created_by, modified_by) "
                    "VALUES (:wm, :b, :c, :g, :dob, :o, :a, :e, :n, :bt, :j, :u, :u) RETURNING id"),
                    {"wm": m.id, "b": bid, "c": code, "g": p.gender, "dob": p.dob, "o": p.occupation, "a": p.address,
                     "e": p.emergency_contact, "n": p.notes, "bt": batch, "j": p.joined_on or _today(), "u": user.id})).scalar_one()
            break
        except IntegrityError:
            continue
    if not profile_id:
        raise HTTPException(status_code=409, detail="Please try again")
    out = {"member_profile_id": str(profile_id), "member_code": code, "status": status}
    if req.plan_id:
        ms = await _assign_plan(db, user, profile_id, bid, req.plan_id, req.start_date)
        out["expiry_date"] = ms["expiry_date"].isoformat()
        if req.payment:
            _, out["payment_status"] = await _record_payment(db, acc, user, bid, profile_id, ms["membership_id"], req.payment)
    if status == "invited":
        await notify_users(db, [member_user.id], category="invite", title=f"{acc.workspace.name} wants to add you",
                           message=f"{acc.workspace.name} added you as a Member. Open the app to accept or decline.",
                           workspace_id=acc.workspace.id, branch_id=bid, dedupe_prefix=f"invite:{m.id}", actor_id=user.id)
    audit(db, user, "member.added", "gym_member_profiles", profile_id, acc.workspace.id,
          {"code": code, "mode": "new_login" if req.login else "invite", "plan": req.plan_id})
    await db.commit()
    if temp_pwd:
        out.update(username=member_user.username, temporary_password=temp_pwd)  # shown once to the owner
    return out


@router.get("/members")
async def list_members(
    workspace_id: str,
    branch_id: str | None = None,
    q: str | None = Query(None, max_length=60),
    status: str | None = Query(None, pattern="^(active|expiring|expired|none|invited)$"),
    offset: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=100),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    acc = await load_access(db, user, workspace_id)
    ids = await _scope(db, acc, branch_id, "gym.members.view")
    # Trainers (without members.edit) see only members of their own batches.
    trainer_only = [b for b in ids if not acc.can("gym.members.edit", b)]
    my_member_ids = [r.id for r in acc.roles]
    today = _today()
    params = {"w": acc.workspace.id, "b": ids, "tb": trainer_only, "mine": my_member_ids, "today": today,
              "q": f"%{q.strip()}%" if q else None, "st": status, "off": offset, "lim": limit + 1}
    rows = (await db.execute(text(f"""
        SELECT * FROM (
          SELECT p.id, p.member_code, p.branch_id, b.name AS branch_name, wm.status AS member_status,
                 u.first_name, u.last_name, u.dial_code, u.mobile_number, bt.name AS batch_name,
                 ms.plan_name, ms.expiry_date,
                 CASE WHEN wm.status = 'invited' THEN 'invited'
                      WHEN ms.expiry_date IS NULL THEN 'none'
                      WHEN ms.expiry_date < :today THEN 'expired'
                      WHEN ms.expiry_date <= CAST(:today AS date) + COALESCE(s.reminder_lead_days, 7) THEN 'expiring'
                      ELSE 'active' END AS state,
                 EXISTS (SELECT 1 FROM {S}gym_member_attendance a WHERE a.member_profile_id = p.id AND a.check_out_at IS NULL) AS inside
            FROM {S}gym_member_profiles p
            JOIN {S}workspace_members wm ON wm.id = p.workspace_member_id AND wm.status IN ('active','invited')
            JOIN {S}users u ON u.id = wm.user_id
            JOIN {S}workspace_branches b ON b.id = p.branch_id
            LEFT JOIN {S}gym_branch_settings s ON s.branch_id = p.branch_id
            LEFT JOIN {S}gym_batches bt ON bt.id = p.batch_id
            LEFT JOIN LATERAL (SELECT plan_name, expiry_date FROM {S}gym_memberships m
                                WHERE m.member_profile_id = p.id AND m.status = 'active' ORDER BY m.expiry_date DESC LIMIT 1) ms ON TRUE
           WHERE wm.workspace_id = :w AND p.branch_id = ANY(:b)
             AND (NOT (p.branch_id = ANY(:tb)) OR bt.trainer_member_id = ANY(:mine))
             AND (CAST(:q AS text) IS NULL OR (u.first_name || ' ' || u.last_name) ILIKE :q OR p.member_code ILIKE :q OR u.mobile_number LIKE :q)
        ) x
        WHERE (CAST(:st AS text) IS NULL OR x.state = :st)
        ORDER BY x.first_name, x.last_name OFFSET :off LIMIT :lim"""), params)).mappings().all()
    items = [{
        "id": str(r["id"]), "member_code": r["member_code"], "branch_id": str(r["branch_id"]), "branch_name": r["branch_name"],
        "name": f"{r['first_name']} {r['last_name']}", "mobile": f"{r['dial_code']} {r['mobile_number']}",
        "batch_name": r["batch_name"], "plan_name": r["plan_name"],
        "expiry_date": r["expiry_date"].isoformat() if r["expiry_date"] else None,
        "days_left": (r["expiry_date"] - today).days if r["expiry_date"] else None,
        "state": r["state"], "inside": r["inside"],
    } for r in rows[:limit]]
    return {"members": items, "next_offset": offset + limit if len(rows) > limit else None,
            "can_add": any(acc.can("gym.members.edit", b) for b in ids)}


async def _member(db: AsyncSession, acc: Access, profile_id: str, perm: str):
    pid = _uuid(profile_id, "Member")
    m = (await db.execute(text(f"""
        SELECT p.*, wm.status AS member_status, wm.user_id, u.first_name, u.last_name, u.username, u.dial_code, u.mobile_number,
               b.name AS branch_name, bt.trainer_member_id
          FROM {S}gym_member_profiles p
          JOIN {S}workspace_members wm ON wm.id = p.workspace_member_id
          JOIN {S}users u ON u.id = wm.user_id
          JOIN {S}workspace_branches b ON b.id = p.branch_id
          LEFT JOIN {S}gym_batches bt ON bt.id = p.batch_id
         WHERE p.id = :p AND b.workspace_id = :w AND wm.status IN ('active','invited')"""), {"p": pid, "w": acc.workspace.id})).mappings().first()
    if not m or not acc.can(perm, m["branch_id"]):
        raise HTTPException(status_code=404, detail="Member not found")
    if not acc.can("gym.members.edit", m["branch_id"]) and m["trainer_member_id"] not in {r.id for r in acc.roles}:
        raise HTTPException(status_code=404, detail="Member not found")  # trainer: only own batch members
    return m


@router.get("/members/{profile_id}")
async def member_detail(workspace_id: str, profile_id: str, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    acc = await load_access(db, user, workspace_id)
    m = await _member(db, acc, profile_id, "gym.members.view")
    bid = m["branch_id"]
    ships = (await db.execute(text(
        f"SELECT id, plan_name, start_date, expiry_date, total_amount_paise, status FROM {S}gym_memberships "
        "WHERE member_profile_id = :p ORDER BY start_date DESC LIMIT 50"), {"p": m["id"]})).mappings().all()
    can_pay = acc.can("gym.payments.record", bid) or acc.can("gym.payments.verify", bid)
    pays = (await db.execute(text(
        f"SELECT id, membership_id, amount_paise, method, reference_last_digits, status, paid_on FROM {S}gym_payments "
        "WHERE member_profile_id = :p ORDER BY paid_on DESC, created_at DESC LIMIT 50"), {"p": m["id"]})).mappings().all() if can_pay else []
    visits = (await db.execute(text(
        f"SELECT check_in_at, check_out_at FROM {S}gym_member_attendance WHERE member_profile_id = :p ORDER BY check_in_at DESC LIMIT 20"),
        {"p": m["id"]})).mappings().all()
    paid = {}
    for p in pays:
        if p["status"] == "verified" and p["membership_id"]:
            paid[p["membership_id"]] = paid.get(p["membership_id"], 0) + p["amount_paise"]
    tz = now_tz().tzinfo
    today = _today()
    return {
        "id": str(m["id"]), "member_code": m["member_code"], "status": m["member_status"],
        "name": f"{m['first_name']} {m['last_name']}", "username": m["username"], "mobile": f"{m['dial_code']} {m['mobile_number']}",
        "branch_id": str(bid), "branch_name": m["branch_name"],
        "profile": {"gender": m["gender"], "dob": m["dob"].isoformat() if m["dob"] else None, "occupation": m["occupation"],
                    "address": m["address"], "emergency_contact": m["emergency_contact"], "notes": m["notes"],
                    "batch_id": str(m["batch_id"]) if m["batch_id"] else None, "joined_on": m["joined_on"].isoformat()},
        "memberships": [{"id": str(s["id"]), "plan_name": s["plan_name"], "start_date": s["start_date"].isoformat(),
                         "expiry_date": s["expiry_date"].isoformat(), "amount": s["total_amount_paise"] / 100,
                         "paid": paid.get(s["id"], 0) / 100 if can_pay else None, "status": s["status"],
                         "current": s["status"] == "active" and s["start_date"] <= today <= s["expiry_date"]} for s in ships],
        "payments": [{"id": str(p["id"]), "membership_id": str(p["membership_id"]) if p["membership_id"] else None,
                      "amount": p["amount_paise"] / 100, "method": p["method"], "reference_last_digits": p["reference_last_digits"],
                      "status": p["status"], "paid_on": p["paid_on"].isoformat()} for p in pays],
        "visits": [{"in": v["check_in_at"].astimezone(tz).isoformat(), "out": v["check_out_at"].astimezone(tz).isoformat() if v["check_out_at"] else None}
                   for v in visits],
        "inside": bool(visits) and visits[0]["check_out_at"] is None,
        "can": {"edit": acc.can("gym.members.edit", bid), "memberships": acc.can("gym.memberships.edit", bid),
                "record_payment": acc.can("gym.payments.record", bid), "verify_payment": acc.can("gym.payments.verify", bid),
                "checkin": acc.can("gym.checkin", bid)},
    }


@router.put("/members/{profile_id}")
async def edit_member(workspace_id: str, profile_id: str, req: MemberProfile, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    acc = await load_access(db, user, workspace_id)
    m = await _member(db, acc, profile_id, "gym.members.edit")
    batch = await _batch_ok(db, m["branch_id"], req.batch_id)
    await db.execute(text(
        f"UPDATE {S}gym_member_profiles SET gender = :g, dob = :dob, occupation = :o, address = :a, emergency_contact = :e, notes = :n, "
        "batch_id = :bt, joined_on = COALESCE(:j, joined_on), updated_at = now(), modified_by = :u WHERE id = :p"),
        {"g": req.gender, "dob": req.dob, "o": req.occupation, "a": req.address, "e": req.emergency_contact, "n": req.notes,
         "bt": batch, "j": req.joined_on, "u": user.id, "p": m["id"]})
    audit(db, user, "member.updated", "gym_member_profiles", m["id"], acc.workspace.id, {"batch": req.batch_id})
    await db.commit()
    return {"status": "updated"}


@router.post("/members/{profile_id}/remove")
async def remove_member(workspace_id: str, profile_id: str, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    acc = await load_access(db, user, workspace_id)
    m = await _member(db, acc, profile_id, "gym.members.edit")
    # The login and history stay; they just lose access to this gym.
    await db.execute(text(f"UPDATE {S}workspace_members SET status = 'removed', updated_at = now(), modified_by = :u WHERE id = :wm"),
                     {"u": user.id, "wm": m["workspace_member_id"]})
    audit(db, user, "member.removed", "gym_member_profiles", m["id"], acc.workspace.id, {"code": m["member_code"]})
    await db.commit()
    return {"status": "removed"}


class AssignRequest(BaseModel):
    plan_id: str
    start_date: date | None = None  # empty = today, or day after the current plan ends (renewal)
    payment: FirstPayment | None = None


@router.post("/members/{profile_id}/memberships", status_code=201)
async def assign_membership(workspace_id: str, profile_id: str, req: AssignRequest, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    acc = await load_access(db, user, workspace_id)
    m = await _member(db, acc, profile_id, "gym.memberships.edit")
    if req.payment and not acc.can("gym.payments.record", m["branch_id"]):
        raise HTTPException(status_code=403, detail="You cannot record payments")
    ms = await _assign_plan(db, user, m["id"], m["branch_id"], req.plan_id, req.start_date)
    out = {"membership_id": str(ms["membership_id"]), "start_date": ms["start_date"].isoformat(), "expiry_date": ms["expiry_date"].isoformat()}
    if req.payment:
        _, out["payment_status"] = await _record_payment(db, acc, user, m["branch_id"], m["id"], ms["membership_id"], req.payment)
    audit(db, user, "membership.assigned", "gym_memberships", ms["membership_id"], acc.workspace.id,
          {"member": m["member_code"], "plan": req.plan_id, "start": out["start_date"], "expiry": out["expiry_date"]})
    await db.commit()
    return out


@router.post("/memberships/{membership_id}/cancel")
async def cancel_membership(workspace_id: str, membership_id: str, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    acc = await load_access(db, user, workspace_id)
    xid = _uuid(membership_id, "Membership")
    r = (await db.execute(text(
        f"SELECT ms.member_profile_id, ms.branch_id FROM {S}gym_memberships ms JOIN {S}workspace_branches b ON b.id = ms.branch_id "
        "WHERE ms.id = :x AND b.workspace_id = :w AND ms.status = 'active'"), {"x": xid, "w": acc.workspace.id})).mappings().first()
    if not r or not acc.can("gym.memberships.edit", r["branch_id"]):
        raise HTTPException(status_code=404, detail="Membership not found")
    await db.execute(text(f"UPDATE {S}gym_memberships SET status = 'cancelled', updated_at = now(), modified_by = :u WHERE id = :x"), {"u": user.id, "x": xid})
    audit(db, user, "membership.cancelled", "gym_memberships", xid, acc.workspace.id)
    await db.commit()
    return {"status": "cancelled"}


# ======================= check-in / out (members) =======================

@router.post("/members/{profile_id}/checkin")
async def member_checkin(workspace_id: str, profile_id: str, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    acc = await load_access(db, user, workspace_id)
    m = await _member(db, acc, profile_id, "gym.checkin")
    if m["member_status"] != "active":
        raise HTTPException(status_code=400, detail="This member has not accepted the invite yet")
    today = _today()
    active = (await db.execute(text(
        f"SELECT 1 FROM {S}gym_memberships WHERE member_profile_id = :p AND status = 'active' AND start_date <= :t AND expiry_date >= :t"),
        {"p": m["id"], "t": today})).first()
    try:
        async with db.begin_nested():
            await db.execute(text(
                f"INSERT INTO {S}gym_member_attendance (branch_id, member_profile_id, check_in_at, checked_in_by) VALUES (:b, :p, :now, :u)"),
                {"b": m["branch_id"], "p": m["id"], "now": now_tz(), "u": user.id})
    except IntegrityError:
        raise HTTPException(status_code=400, detail="Already checked in")
    await db.commit()
    return {"status": "checked_in", "warning": None if active else "No active membership today — please renew"}


@router.post("/members/{profile_id}/checkout")
async def member_checkout(workspace_id: str, profile_id: str, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    acc = await load_access(db, user, workspace_id)
    m = await _member(db, acc, profile_id, "gym.checkin")
    res = await db.execute(text(
        f"UPDATE {S}gym_member_attendance SET check_out_at = :now, checked_out_by = :u, updated_at = :now "
        "WHERE member_profile_id = :p AND check_out_at IS NULL"), {"now": now_tz(), "u": user.id, "p": m["id"]})
    if res.rowcount == 0:
        raise HTTPException(status_code=400, detail="Not checked in")
    await db.commit()
    return {"status": "checked_out"}


# ======================= payments =======================

class PaymentRequest(FirstPayment):
    member_profile_id: str
    membership_id: str | None = None
    paid_on: date | None = None
    notes: str | None = Field(None, max_length=500)


@router.get("/payments")
async def list_payments(
    workspace_id: str,
    branch_id: str | None = None,
    status: str | None = Query(None, pattern="^(pending|verified|cancelled)$"),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    acc = await load_access(db, user, workspace_id)
    ids = await _scope(db, acc, branch_id, "gym.payments.record")
    rows = (await db.execute(text(f"""
        SELECT gp.id, gp.branch_id, b.name AS branch_name, gp.member_profile_id, p.member_code, u.first_name, u.last_name,
               gp.amount_paise, gp.method, gp.reference_last_digits, gp.status, gp.paid_on, ms.plan_name,
               (ru.first_name || ' ' || ru.last_name) AS recorded_by
          FROM {S}gym_payments gp
          JOIN {S}gym_member_profiles p ON p.id = gp.member_profile_id
          JOIN {S}workspace_members wm ON wm.id = p.workspace_member_id
          JOIN {S}users u ON u.id = wm.user_id
          JOIN {S}users ru ON ru.id = gp.recorded_by
          JOIN {S}workspace_branches b ON b.id = gp.branch_id
          LEFT JOIN {S}gym_memberships ms ON ms.id = gp.membership_id
         WHERE gp.branch_id = ANY(:b) AND (CAST(:st AS text) IS NULL OR gp.status = :st)
         ORDER BY gp.paid_on DESC, gp.created_at DESC LIMIT 200"""), {"b": ids, "st": status})).mappings().all()
    return {"payments": [{
        "id": str(r["id"]), "branch_name": r["branch_name"], "member_profile_id": str(r["member_profile_id"]),
        "member": f"{r['first_name']} {r['last_name']} ({r['member_code']})", "amount": r["amount_paise"] / 100,
        "method": r["method"], "reference_last_digits": r["reference_last_digits"], "status": r["status"],
        "paid_on": r["paid_on"].isoformat(), "plan_name": r["plan_name"], "recorded_by": r["recorded_by"],
        "can_verify": acc.can("gym.payments.verify", r["branch_id"]),
    } for r in rows]}


@router.post("/payments", status_code=201)
async def add_payment(workspace_id: str, req: PaymentRequest, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    acc = await load_access(db, user, workspace_id)
    m = await _member(db, acc, req.member_profile_id, "gym.payments.record")
    msid = None
    if req.membership_id:
        msid = _uuid(req.membership_id, "Membership")
        if not (await db.execute(text(f"SELECT 1 FROM {S}gym_memberships WHERE id = :x AND member_profile_id = :p"), {"x": msid, "p": m["id"]})).first():
            raise HTTPException(status_code=404, detail="Membership not found")
    if req.paid_on and req.paid_on > _today():
        raise HTTPException(status_code=400, detail="Payment date cannot be in the future")
    pid, st = await _record_payment(db, acc, user, m["branch_id"], m["id"], msid, req, req.paid_on, req.notes)
    audit(db, user, "payment.recorded", "gym_payments", pid, acc.workspace.id, {"amount": req.amount, "method": req.method, "status": st})
    await db.commit()
    return {"id": str(pid), "status": st}


@router.post("/payments/{payment_id}/{action}")
async def verify_payment(workspace_id: str, payment_id: str, action: str, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    if action not in ("verify", "cancel"):
        raise HTTPException(status_code=404, detail="Not found")
    acc = await load_access(db, user, workspace_id)
    xid = _uuid(payment_id, "Payment")
    r = (await db.execute(text(
        f"SELECT gp.branch_id, gp.status FROM {S}gym_payments gp JOIN {S}workspace_branches b ON b.id = gp.branch_id "
        "WHERE gp.id = :x AND b.workspace_id = :w"), {"x": xid, "w": acc.workspace.id})).mappings().first()
    if not r or not acc.can("gym.payments.verify", r["branch_id"]):
        raise HTTPException(status_code=404, detail="Payment not found")
    if r["status"] == "cancelled" or (action == "verify" and r["status"] == "verified"):
        raise HTTPException(status_code=400, detail=f"Payment is already {r['status']}")
    new = "verified" if action == "verify" else "cancelled"
    await db.execute(text(
        f"UPDATE {S}gym_payments SET status = :s, verified_by = :u, verified_at = :now, updated_at = :now, modified_by = :u WHERE id = :x"),
        {"s": new, "u": user.id, "now": now_tz(), "x": xid})
    audit(db, user, f"payment.{new}", "gym_payments", xid, acc.workspace.id)
    await db.commit()
    return {"status": new}
