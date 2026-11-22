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
                   (SELECT h.reason FROM {S}gym_holidays h WHERE h.branch_id = b.id AND h.is_active AND h.holiday_date = :today LIMIT 1) AS holiday_today,
                   --Added By Nikhil 22Nov26 14:41 For staff present / scheduled today START
                   (SELECT count(*) FROM {S}gym_shift_assignments sa JOIN {S}gym_shifts sh ON sh.id = sa.shift_id
                      JOIN {S}workspace_members wm ON wm.id = sa.workspace_member_id AND wm.status = 'active'
                     WHERE sh.branch_id = b.id AND sh.status = 'active' AND CAST(:wd AS smallint) = ANY(sh.weekdays)
                       AND sa.effective_from <= :today AND (sa.effective_to IS NULL OR sa.effective_to >= :today)
                       AND NOT EXISTS (SELECT 1 FROM {S}gym_holidays h2 WHERE h2.branch_id = b.id AND h2.is_active AND h2.holiday_date = :today)
                   ) AS staff_scheduled_today,
                   (SELECT count(*) FROM {S}gym_staff_attendance sa2 WHERE sa2.branch_id = b.id AND sa2.work_date = :today
                       AND sa2.check_in_at IS NOT NULL) AS staff_present_today
                   --Added By Nikhil 22Nov26 14:41 For staff present / scheduled today END
              FROM {S}workspace_branches b LEFT JOIN {S}gym_branch_settings s ON s.branch_id = b.id
             WHERE b.id = ANY(:b)"""), {"b": ids, "today": today, "ds": start, "de": end, "ms": month_start, "wd": today.isoweekday()})).mappings().all()  #Modified By Nikhil 22Nov26 14:41 For today's weekday (staff scheduled). Old: ..."ms": month_start})
        can_money = {bid for bid in ids if acc.can("gym.reports.view", bid) or acc.can("gym.payments.verify", bid)}
        for r in rows:
            d = {k: (int(v) if isinstance(v, int) else v) for k, v in r.items() if k != "id"}
            if r["id"] not in can_money:
                d["month_revenue_paise"] = None  # receptionists / trainers do not see revenue
            stats[r["id"]] = d
    #Modified By Nikhil 22Nov26 14:41 For staff present / scheduled totals. Old: keys = (..., "pending_payments", "staff")
    keys = ("members", "active", "expiring", "expired", "visits_today", "inside_now", "pending_payments", "staff",
            "staff_scheduled_today", "staff_present_today")
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
        #Added By Nikhil 22Nov26 20:53 For location check-in: gym position + radius
        g = (await db.execute(text(f"SELECT latitude, longitude, checkin_radius_m FROM {S}workspace_branches WHERE id = :b"), {"b": bid})).mappings().first()
        out["location"] = {"latitude": float(g["latitude"]) if g["latitude"] is not None else None,
                           "longitude": float(g["longitude"]) if g["longitude"] is not None else None, "radius_m": g["checkin_radius_m"]}
    return out


#Added By Nikhil 22Nov26 20:53 For location check-in: owner saves the gym position + allowed radius START
class LocationRequest(BaseModel):
    latitude: float | None = Field(None, ge=-90, le=90)
    longitude: float | None = Field(None, ge=-180, le=180)
    radius_m: int = Field(50, ge=20, le=1000)

    @model_validator(mode="after")
    def both(self):
        if (self.latitude is None) != (self.longitude is None):
            raise ValueError("Send both latitude and longitude, or neither (to switch the location rule off)")
        return self


@router.put("/branches/{branch_id}/location")
async def set_location(workspace_id: str, branch_id: str, req: LocationRequest, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    acc = await load_access(db, user, workspace_id)
    bid = await _branch(db, acc, branch_id, "gym.business.manage")
    await db.execute(text(
        f"UPDATE {S}workspace_branches SET latitude = :la, longitude = :lo, checkin_radius_m = :r, updated_at = now(), modified_by = :u WHERE id = :b"),
        {"la": req.latitude, "lo": req.longitude, "r": req.radius_m, "u": user.id, "b": bid})
    audit(db, user, "branch.location_updated", "workspace_branches", bid, acc.workspace.id,
          {"set": req.latitude is not None, "radius_m": req.radius_m})  # no coordinates in the audit log
    await db.commit()
    return {"status": "updated"}


class GeoRequest(BaseModel):
    lat: float | None = Field(None, ge=-90, le=90)
    lng: float | None = Field(None, ge=-180, le=180)
    accuracy_m: float | None = Field(None, ge=0, le=100000)


def _distance_m(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Great-circle distance in metres (haversine)."""
    import math
    r = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = math.radians(lat2 - lat1), math.radians(lng2 - lng1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


async def _geo_check(db: AsyncSession, bid, lat: float | None, lng: float | None) -> None:
    """Branch with a saved position → the phone must be within the radius. No saved position → no rule."""
    g = (await db.execute(text(f"SELECT latitude, longitude, checkin_radius_m FROM {S}workspace_branches WHERE id = :b"), {"b": bid})).mappings().first()
    if not g or g["latitude"] is None:
        return
    if lat is None or lng is None:
        raise HTTPException(status_code=400, detail="Turn on location to check in at the gym")
    d = _distance_m(float(g["latitude"]), float(g["longitude"]), lat, lng)
    if d > g["checkin_radius_m"]:
        raise HTTPException(status_code=400, detail=f"You are about {int(round(d))} m from the gym. Check in when you are there (within {g['checkin_radius_m']} m).")
#Added By Nikhil 22Nov26 20:53 For location check-in: owner saves the gym position + allowed radius END


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
    """Only the owner sees (and sets) staff pay — decided 22Nov26 18:05."""
    #Modified By Nikhil 22Nov26 18:05 For pay visible to the owner only. Old: own pay → True; manager with staff.view_pay → non-managers of own branch
    return acc.is_owner


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
    #Added By Nikhil 22Nov26 18:05 For members check in/out only from their own app — owner/staff cannot do it for them
    raise HTTPException(status_code=403, detail="Members check in and out from their own app")
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
    #Added By Nikhil 22Nov26 18:05 For members check in/out only from their own app — owner/staff cannot do it for them
    raise HTTPException(status_code=403, detail="Members check in and out from their own app")
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


# ======================= staff attendance (step 4) =======================
#Added By Nikhil 22Nov26 14:41 For staff self check-in + shift attendance (register, month summary, corrections) START

CHECKIN_EARLY_MIN = 60  # check-in opens 60 min before the shift starts (decided 22Nov26)
_STATUS_LABEL = {"present": "Present", "late": "Late", "half_day": "Half day", "absent": "Absent", "missed_checkout": "Missed check-out",
                 "holiday": "Holiday", "week_off": "Week off", "pending": "Not checked in"}


def _att_status(d: date, now: datetime, start: time, end: time, cfg: dict, rec: dict | None,
                holiday: str | None, works_today: bool) -> tuple[str, bool]:
    """(status, working_now) — the ONE rule used by check-in, check-out and every read. Server clock (IST) only.

    Check-in: ≤ start + late grace → present; ≤ start + half-day-after → late; later → half_day.
    Check-out: worked < 50 % of the shift → absent; left more than the early-out grace before the end → half_day.
    No check-out by the end of the day → missed_checkout. No check-in by the shift end → absent.
    Branch holiday → holiday; not one of the shift's weekdays → week_off (never absent).
    'pending' = shift not over yet and not checked in (not counted). A correction always wins.
    """
    tz = now.tzinfo
    if rec and rec.get("corrected_by"):
        return rec["status"], False
    s_dt, e_dt = datetime.combine(d, start, tz), datetime.combine(d, end, tz)
    cin = rec.get("check_in_at") if rec else None
    if not cin:
        if not works_today:
            return "week_off", False
        if holiday:
            return "holiday", False
        return ("absent", False) if now >= e_dt else ("pending", False)
    cin = cin.astimezone(tz)
    late_min = (cin - s_dt).total_seconds() / 60
    st = "present" if late_min <= cfg["late"] else "late" if late_min <= cfg["half"] else "half_day"
    cout = rec.get("check_out_at")
    if not cout:
        return ("missed_checkout", False) if d < now.date() else (st, True)
    cout = cout.astimezone(tz)
    if (cout - max(cin, s_dt)).total_seconds() < (e_dt - s_dt).total_seconds() * 0.5:
        return "absent", False
    if cout < e_dt - timedelta(minutes=cfg["early"]):
        return "half_day", False
    return st, False


async def _att_rows(db: AsyncSession, branch_ids: list[UUID], d1: date, d2: date, member_id: UUID | None = None) -> list:
    """One row per (day, active staff member, assigned shift) with the attendance record if any."""
    return (await db.execute(text(f"""
        SELECT CAST(g.d AS date) AS work_date, wm.id AS member_id, wm.branch_id, b.name AS branch_name, wm.user_id,
               (b.latitude IS NOT NULL) AS geo,
               u.first_name, u.last_name, r.code AS role_code, r.name AS role_name, r.rank,
               s.id AS shift_id, s.name AS shift_name, s.start_time, s.end_time, s.weekdays,
               a.id AS att_id, a.check_in_at, a.check_out_at, a.status, a.corrected_by, a.correction_note,
               COALESCE(bs.late_grace_minutes, 15) AS late, COALESCE(bs.half_day_after_minutes, 30) AS half,
               COALESCE(bs.early_out_grace_minutes, 10) AS early,
               (SELECT h.reason FROM {S}gym_holidays h WHERE h.branch_id = wm.branch_id AND h.is_active
                   AND h.holiday_date = CAST(g.d AS date) LIMIT 1) AS holiday
          FROM generate_series(CAST(:d1 AS date), CAST(:d2 AS date), interval '1 day') AS g(d)
          JOIN {S}gym_shift_assignments sa ON sa.effective_from <= CAST(g.d AS date)
                AND (sa.effective_to IS NULL OR sa.effective_to >= CAST(g.d AS date))
          JOIN {S}gym_shifts s ON s.id = sa.shift_id
          JOIN {S}workspace_members wm ON wm.id = sa.workspace_member_id AND wm.status = 'active'
          JOIN {S}module_roles r ON r.id = wm.role_id AND r.is_staff
          JOIN {S}users u ON u.id = wm.user_id
          JOIN {S}workspace_branches b ON b.id = wm.branch_id
          LEFT JOIN {S}gym_branch_settings bs ON bs.branch_id = wm.branch_id
          LEFT JOIN {S}gym_staff_attendance a ON a.workspace_member_id = wm.id AND a.shift_id = s.id AND a.work_date = CAST(g.d AS date)
         WHERE wm.branch_id = ANY(:b) AND (CAST(:m AS uuid) IS NULL OR wm.id = CAST(:m AS uuid))
           AND (s.status = 'active' OR a.id IS NOT NULL)
         ORDER BY g.d DESC, s.start_time, r.rank, u.first_name"""),
        {"b": branch_ids, "d1": d1, "d2": d2, "m": str(member_id) if member_id else None})).mappings().all()


def _cfg(r) -> dict:
    return {"late": r["late"], "half": r["half"], "early": r["early"]}


def _att_out(r, now: datetime) -> dict:
    d = r["work_date"]
    works = d.isoweekday() in (r["weekdays"] or [])
    rec = ({"check_in_at": r["check_in_at"], "check_out_at": r["check_out_at"], "status": r["status"], "corrected_by": r["corrected_by"]}
           if r["att_id"] else None)
    status, working = _att_status(d, now, r["start_time"], r["end_time"], _cfg(r), rec, r["holiday"], works)
    tz = now.tzinfo
    opens = datetime.combine(d, r["start_time"], tz) - timedelta(minutes=CHECKIN_EARLY_MIN)
    ends = datetime.combine(d, r["end_time"], tz)
    #Modified By Nikhil 22Nov26 20:53 For staff check-in on a week off (extra day). Old: d == now.date() and works and not r["holiday"] ...
    can_in = (d == now.date() and not r["holiday"] and not (rec and (rec["check_in_at"] or rec["corrected_by"]))
              and opens <= now < ends)
    return {
        "work_date": d.isoformat(), "member_id": str(r["member_id"]), "branch_id": str(r["branch_id"]), "branch_name": r["branch_name"],
        "name": f"{r['first_name']} {r['last_name']}", "role_code": r["role_code"], "role_name": r["role_name"],
        "shift_id": str(r["shift_id"]), "shift_name": r["shift_name"], "start_time": _t(r["start_time"]), "end_time": _t(r["end_time"]),
        "check_in_at": r["check_in_at"].astimezone(tz).isoformat() if r["check_in_at"] else None,
        "check_out_at": r["check_out_at"].astimezone(tz).isoformat() if r["check_out_at"] else None,
        "status": status, "status_label": _STATUS_LABEL.get(status, status), "working_now": working,
        "corrected": bool(r["corrected_by"]), "correction_note": r["correction_note"], "holiday": r["holiday"],
        "can_check_in": can_in, "can_check_out": working, "check_in_opens": _t(opens.time()),
        "extra_day": not works,  #Added By Nikhil 22Nov26 20:53 For week-off check-in shown as an extra day
        "location_required": bool(r["geo"]),  #Added By Nikhil 22Nov26 20:53 For location check-in (app asks for GPS only when needed)
    }


def _counts(items: list[dict]) -> dict:
    c = {k: 0 for k in ("present", "late", "half_day", "absent", "missed_checkout", "holiday", "week_off", "pending")}
    for i in items:
        c[i["status"]] = c.get(i["status"], 0) + 1
    c["scheduled"] = sum(c[k] for k in ("present", "late", "half_day", "absent", "missed_checkout"))
    return c


def _month_range(month: str | None) -> tuple[date, date, str]:
    today = _today()
    if month:
        if not re.fullmatch(r"\d{4}-(0[1-9]|1[0-2])", month):
            raise HTTPException(status_code=400, detail="Month must look like 2026-11")
        first = date(int(month[:4]), int(month[5:]), 1)
    else:
        first = today.replace(day=1)
    last = date(first.year, first.month, calendar.monthrange(first.year, first.month)[1])
    return first, min(last, today), first.strftime("%Y-%m")


async def _my_items(db: AsyncSession, acc: Access, d1: date, d2: date) -> list[tuple]:
    now = now_tz()
    out = []
    for m in (r for r in acc.roles if r.role.is_staff and r.branch_id):
        out += [(r, _att_out(r, now)) for r in await _att_rows(db, [m.branch_id], d1, d2, m.id)]
    return out


@router.get("/me/today")
async def my_today(workspace_id: str, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """The caller's own shifts today (staff roles only) with what they may do now."""
    acc = await load_access(db, user, workspace_id)
    today = _today()
    items = [o for _, o in await _my_items(db, acc, today, today)]
    items.sort(key=lambda o: o["start_time"])
    return {"today": today.isoformat(), "now": now_tz().isoformat(), "is_staff": any(r.role.is_staff for r in acc.roles),
            "checkin_early_minutes": CHECKIN_EARLY_MIN, "shifts": items}


class MyCheckRequest(GeoRequest):  #Modified By Nikhil 22Nov26 20:53 For location check-in. Old: class MyCheckRequest(BaseModel):
    shift_id: str | None = None


@router.post("/me/checkin")
async def my_checkin(workspace_id: str, req: MyCheckRequest, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """Own record only, server time. Picks the shift whose check-in window is open now (or the one asked for)."""
    acc = await load_access(db, user, workspace_id)
    now, today = now_tz(), _today()
    items = await _my_items(db, acc, today, today)
    if not items:
        raise HTTPException(status_code=400, detail="You have no shift today")
    if any(o["working_now"] for _, o in items):
        raise HTTPException(status_code=400, detail="You are already checked in. Check out first.")
    pool = [(r, o) for r, o in items if not req.shift_id or o["shift_id"] == req.shift_id]
    open_ = sorted([(r, o) for r, o in pool if o["can_check_in"]], key=lambda x: x[1]["start_time"])
    if not open_:
        if any(o["status"] == "holiday" for _, o in pool):
            raise HTTPException(status_code=400, detail="Today is a holiday at your branch. No check-in needed.")
        #Removed By Nikhil 22Nov26 20:53 For week-off check-in allowed (extra day): if all week_off → 400 "Today is your week off."
        #Modified By Nikhil 22Nov26 20:53 For week-off shifts also showing when check-in opens. Old: ... if o["status"] == "pending" and ...
        later = sorted(o["check_in_opens"] for _, o in pool if o["status"] in ("pending", "week_off") and o["check_in_opens"] > now.strftime("%H:%M"))
        if later:
            raise HTTPException(status_code=400, detail=f"Check-in opens at {later[0]} ({CHECKIN_EARLY_MIN} min before your shift)")
        raise HTTPException(status_code=400, detail="Your shift for today is over or already marked")
    r, o = open_[0]
    await _geo_check(db, r["branch_id"], req.lat, req.lng)  #Added By Nikhil 22Nov26 20:53 For location check-in (staff)
    status, _ = _att_status(today, now, r["start_time"], r["end_time"], _cfg(r),
                            {"check_in_at": now, "check_out_at": None, "status": None, "corrected_by": None}, None, True)
    new_id = (await db.execute(text(
        f"INSERT INTO {S}gym_staff_attendance (branch_id, workspace_member_id, shift_id, work_date, check_in_at, status) "
        "VALUES (:b, :m, :s, :d, :now, :st) ON CONFLICT (workspace_member_id, shift_id, work_date) DO UPDATE "
        f"SET check_in_at = EXCLUDED.check_in_at, status = EXCLUDED.status, updated_at = now() "
        f"WHERE {S}gym_staff_attendance.check_in_at IS NULL AND {S}gym_staff_attendance.corrected_by IS NULL RETURNING id"),
        {"b": r["branch_id"], "m": r["member_id"], "s": r["shift_id"], "d": today, "now": now, "st": status})).scalar_one_or_none()
    if not new_id:
        raise HTTPException(status_code=400, detail="You are already checked in for this shift")
    audit(db, user, "staff_attendance.check_in", "gym_staff_attendance", new_id, acc.workspace.id, {"shift": o["shift_name"], "status": status})
    await db.commit()
    return {"status": status, "status_label": _STATUS_LABEL[status], "shift_name": o["shift_name"], "check_in_at": now.isoformat()}


@router.post("/me/checkout")
async def my_checkout(workspace_id: str, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    acc = await load_access(db, user, workspace_id)
    now, today = now_tz(), _today()
    working = [(r, o) for r, o in await _my_items(db, acc, today, today) if o["working_now"]]
    if not working:
        raise HTTPException(status_code=400, detail="You are not checked in")
    r, o = working[0]
    status, _ = _att_status(today, now, r["start_time"], r["end_time"], _cfg(r),
                            {"check_in_at": r["check_in_at"], "check_out_at": now, "status": None, "corrected_by": None}, None, True)
    done = (await db.execute(text(
        f"UPDATE {S}gym_staff_attendance SET check_out_at = :now, status = :st, updated_at = now() "
        "WHERE id = :a AND check_out_at IS NULL AND corrected_by IS NULL RETURNING id"),
        {"now": now, "st": status, "a": r["att_id"]})).scalar_one_or_none()
    if not done:
        raise HTTPException(status_code=400, detail="You are not checked in")
    audit(db, user, "staff_attendance.check_out", "gym_staff_attendance", r["att_id"], acc.workspace.id, {"shift": o["shift_name"], "status": status})
    await db.commit()
    return {"status": status, "status_label": _STATUS_LABEL[status], "shift_name": o["shift_name"], "check_out_at": now.isoformat()}


@router.get("/me/attendance")
async def my_attendance(workspace_id: str, month: str | None = None, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    acc = await load_access(db, user, workspace_id)
    d1, d2, label = _month_range(month)
    items = [o for _, o in await _my_items(db, acc, d1, d2)] if d1 <= d2 else []
    return {"month": label, "days": items, "counts": _counts(items)}


def _can_correct(acc: Access, r, me: User) -> bool:
    return (acc.can("gym.staff_attendance.correct", r["branch_id"]) and r["user_id"] != me.id
            and (acc.is_owner or r["rank"] > acc.best_role.rank))


@router.get("/staff-attendance")
async def staff_register(workspace_id: str, date_: str | None = Query(None, alias="date"), branch_id: str | None = None,
                         user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """Day register for the branches the caller may view: every scheduled staff shift, absent / holiday / week off filled in."""
    acc = await load_access(db, user, workspace_id)
    ids = await _scope(db, acc, branch_id, "gym.attendance.view")
    try:
        d = date.fromisoformat(date_) if date_ else _today()
    except ValueError:
        raise HTTPException(status_code=400, detail="Date must look like 2026-11-22")
    if d > _today():
        raise HTTPException(status_code=400, detail="Pick today or an earlier date")
    now = now_tz()
    items = [{**_att_out(r, now), "can_correct": _can_correct(acc, r, user)} for r in await _att_rows(db, ids, d, d)]
    items.sort(key=lambda o: (o["start_time"], o["name"]))
    return {"date": d.isoformat(), "items": items, "counts": _counts(items)}


@router.get("/staff-attendance/summary")
async def staff_month_summary(workspace_id: str, month: str | None = None, branch_id: str | None = None,
                              user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    acc = await load_access(db, user, workspace_id)
    ids = await _scope(db, acc, branch_id, "gym.attendance.view")
    d1, d2, label = _month_range(month)
    now = now_tz()
    people: dict[str, dict] = {}
    for r in (await _att_rows(db, ids, d1, d2) if d1 <= d2 else []):
        o = _att_out(r, now)
        p = people.setdefault(o["member_id"], {"member_id": o["member_id"], "name": o["name"], "role_name": o["role_name"],
                                               "branch_name": o["branch_name"], "items": []})
        p["items"].append(o)
    staff = [{**{k: v for k, v in p.items() if k != "items"}, "counts": _counts(p["items"])} for p in people.values()]
    staff.sort(key=lambda p: p["name"])
    return {"month": label, "staff": staff}


class CorrectRequest(BaseModel):
    member_id: str
    shift_id: str
    work_date: date
    status: str = Field(..., pattern="^(present|late|half_day|absent)$")
    check_in: str | None = Field(None, pattern=r"^([01][0-9]|2[0-3]):[0-5][0-9]$")
    check_out: str | None = Field(None, pattern=r"^([01][0-9]|2[0-3]):[0-5][0-9]$")
    note: str = Field(..., min_length=3, max_length=300)

    @model_validator(mode="after")
    def check(self):
        if self.check_out and not self.check_in:
            raise ValueError("Enter the check-in time too")
        if self.check_in and self.check_out and self.check_out <= self.check_in:
            raise ValueError("Check-out must be after check-in")
        return self


@router.post("/staff-attendance/correct")
async def correct_attendance(workspace_id: str, req: CorrectRequest, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """Owner / manager fixes one shift-day. Rank rule, never yourself, never a future day, a note is required."""
    acc = await load_access(db, user, workspace_id)
    mid, sid = _uuid(req.member_id, "Staff member"), _uuid(req.shift_id, "Shift")
    t = (await db.execute(text(
        f"SELECT wm.id, wm.branch_id, wm.user_id, r.rank FROM {S}workspace_members wm JOIN {S}module_roles r ON r.id = wm.role_id "
        "WHERE wm.id = :m AND wm.workspace_id = :w AND r.is_staff AND wm.status = 'active'"),
        {"m": mid, "w": acc.workspace.id})).mappings().first()
    if not t:
        raise HTTPException(status_code=404, detail="Staff member not found")
    if not acc.can("gym.staff_attendance.correct", t["branch_id"]):
        raise HTTPException(status_code=403, detail="You do not have permission for this action")
    if t["user_id"] == user.id:
        raise HTTPException(status_code=400, detail="You cannot correct your own attendance")
    if not acc.is_owner and t["rank"] <= acc.best_role.rank:
        raise HTTPException(status_code=403, detail="You can only correct staff below your own role")
    now = now_tz()
    if req.work_date > now.date():
        raise HTTPException(status_code=400, detail="You cannot mark a future day")
    shift = (await db.execute(text(
        f"SELECT s.name FROM {S}gym_shift_assignments sa JOIN {S}gym_shifts s ON s.id = sa.shift_id "
        "WHERE sa.workspace_member_id = :m AND sa.shift_id = :s AND s.branch_id = :b AND sa.effective_from <= :d "
        "AND (sa.effective_to IS NULL OR sa.effective_to >= :d) LIMIT 1"),
        {"m": mid, "s": sid, "b": t["branch_id"], "d": req.work_date})).scalar_one_or_none()
    if not shift:
        raise HTTPException(status_code=400, detail="This shift was not assigned to them on that day")
    tz = now.tzinfo
    cin = datetime.combine(req.work_date, time.fromisoformat(req.check_in), tz) if req.check_in else None
    cout = datetime.combine(req.work_date, time.fromisoformat(req.check_out), tz) if req.check_out else None
    if (cin and cin > now) or (cout and cout > now):
        raise HTTPException(status_code=400, detail="Times cannot be in the future")
    old = (await db.execute(text(
        f"SELECT status FROM {S}gym_staff_attendance WHERE workspace_member_id = :m AND shift_id = :s AND work_date = :d"),
        {"m": mid, "s": sid, "d": req.work_date})).scalar_one_or_none()
    att_id = (await db.execute(text(
        f"INSERT INTO {S}gym_staff_attendance (branch_id, workspace_member_id, shift_id, work_date, check_in_at, check_out_at, status, "
        "corrected_by, correction_note) VALUES (:b, :m, :s, :d, :cin, :cout, :st, :u, :note) "
        "ON CONFLICT (workspace_member_id, shift_id, work_date) DO UPDATE SET "
        f"check_in_at = COALESCE(EXCLUDED.check_in_at, {S}gym_staff_attendance.check_in_at), "
        f"check_out_at = COALESCE(EXCLUDED.check_out_at, {S}gym_staff_attendance.check_out_at), "
        "status = EXCLUDED.status, corrected_by = EXCLUDED.corrected_by, correction_note = EXCLUDED.correction_note, updated_at = now() "
        "RETURNING id"),
        {"b": t["branch_id"], "m": mid, "s": sid, "d": req.work_date, "cin": cin, "cout": cout, "st": req.status,
         "u": user.id, "note": req.note.strip()})).scalar_one()
    audit(db, user, "staff_attendance.corrected", "gym_staff_attendance", att_id, acc.workspace.id,
          {"work_date": req.work_date.isoformat(), "shift": shift, "old_status": old, "new_status": req.status, "note": req.note.strip()})
    await notify_users(db, [t["user_id"]], category="attendance", title=f"{acc.workspace.name}: attendance updated",
                       message=f"{shift} on {req.work_date.strftime('%d %b %Y')} marked {_STATUS_LABEL[req.status]}. Note: {req.note.strip()}",
                       workspace_id=acc.workspace.id, branch_id=t["branch_id"], actor_id=user.id)
    await db.commit()
    return {"status": req.status, "id": str(att_id)}
#Added By Nikhil 22Nov26 14:41 For staff self check-in + shift attendance (register, month summary, corrections) END


# ======================= member self-service (step 5) =======================
#Added By Nikhil 22Nov26 17:36 For member screens: home, check-in/out, visits, payments, renew, gym info START
# Every route below works ONLY on the caller's own member record in this business (role 'member', status active).

async def _me_member(db: AsyncSession, acc: Access) -> dict:
    mine = [r for r in acc.roles if r.role.code == "member"]
    if not mine:
        raise HTTPException(status_code=403, detail="This page is for gym members")
    p = (await db.execute(text(
        f"SELECT p.id, p.branch_id, p.member_code, p.joined_on, p.batch_id, b.name AS branch_name, b.address, b.phone, "
        f"(b.latitude IS NOT NULL) AS geo "
        f"FROM {S}gym_member_profiles p JOIN {S}workspace_branches b ON b.id = p.branch_id WHERE p.workspace_member_id = :m"),
        {"m": mine[0].id})).mappings().first()
    if not p:
        raise HTTPException(status_code=404, detail="Your member profile was not found. Please contact the gym.")
    return dict(p)


def _ms_out(r, today: date) -> dict:
    return {"id": str(r["id"]), "plan_name": r["plan_name"], "start_date": r["start_date"].isoformat(),
            "expiry_date": r["expiry_date"].isoformat(), "days_left": max(0, (r["expiry_date"] - today).days + 1) if r["start_date"] <= today else None,
            "total": r["total_amount_paise"] / 100, "paid": (r["paid"] or 0) / 100, "pending": (r["pending"] or 0) / 100,
            "status": r["status"]}


async def _today_rules(db: AsyncSession, bid: UUID) -> dict:
    """Branch opening hours today + holiday (server time IST)."""
    today = _today()
    h = (await db.execute(text(
        f"SELECT is_closed, open_time, close_time FROM {S}gym_branch_hours WHERE branch_id = :b AND weekday = :wd"),
        {"b": bid, "wd": today.isoweekday()})).mappings().first()
    hol = (await db.execute(text(
        f"SELECT reason FROM {S}gym_holidays WHERE branch_id = :b AND is_active AND holiday_date = :t LIMIT 1"),
        {"b": bid, "t": today})).scalar_one_or_none()
    return {"closed": bool(h is None or h["is_closed"]), "open": _t(h["open_time"]) if h else None,
            "close": _t(h["close_time"]) if h else None, "holiday": hol}


def _checkin_block(rules: dict, active: bool, inside: bool) -> str | None:
    """Why the member may not check in right now (None = allowed)."""
    if inside:
        return None
    if rules["holiday"]:
        return f"The gym is closed today ({rules['holiday']})"
    if rules["closed"] or not rules["open"]:
        return "The gym is closed today"
    now_hm = now_tz().strftime("%H:%M")
    if not (rules["open"] <= now_hm < rules["close"]):
        return f"Check-in is open {rules['open']} – {rules['close']}"
    if not active:
        return "Your membership is not active today. Please renew."
    return None


@router.get("/me/member")
async def my_member_home(workspace_id: str, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    acc = await load_access(db, user, workspace_id)
    p = await _me_member(db, acc)
    today = _today()
    ms = (await db.execute(text(f"""
        SELECT ms.id, ms.plan_name, ms.start_date, ms.expiry_date, ms.total_amount_paise, ms.status,
               (SELECT sum(amount_paise) FROM {S}gym_payments g WHERE g.membership_id = ms.id AND g.status = 'verified') AS paid,
               (SELECT sum(amount_paise) FROM {S}gym_payments g WHERE g.membership_id = ms.id AND g.status = 'pending') AS pending
          FROM {S}gym_memberships ms WHERE ms.member_profile_id = :p AND ms.status = 'active'
         ORDER BY ms.start_date"""), {"p": p["id"]})).mappings().all()
    current = next((m for m in ms if m["start_date"] <= today <= m["expiry_date"]), None)
    upcoming = [m for m in ms if m["start_date"] > today]
    last = max((m for m in ms if m["expiry_date"] < today), key=lambda m: m["expiry_date"], default=None)
    visit = (await db.execute(text(
        f"SELECT check_in_at, check_out_at FROM {S}gym_member_attendance WHERE member_profile_id = :p "
        "ORDER BY check_in_at DESC LIMIT 1"), {"p": p["id"]})).mappings().first()
    tz = now_tz().tzinfo
    inside = bool(visit and visit["check_out_at"] is None)
    today_visit = visit if visit and visit["check_in_at"].astimezone(tz).date() == today else None
    rules = await _today_rules(db, p["branch_id"])
    batch = None
    if p["batch_id"]:
        b = (await db.execute(text(f"""
            SELECT bt.name, bt.start_time, bt.end_time, bt.weekdays, u.first_name, u.last_name, sp.specialization
              FROM {S}gym_batches bt
              LEFT JOIN {S}workspace_members wm ON wm.id = bt.trainer_member_id AND wm.status = 'active'
              LEFT JOIN {S}users u ON u.id = wm.user_id
              LEFT JOIN {S}gym_staff_profiles sp ON sp.workspace_member_id = wm.id
             WHERE bt.id = :b"""), {"b": p["batch_id"]})).mappings().first()
        if b:
            batch = {"name": b["name"], "start_time": _t(b["start_time"]), "end_time": _t(b["end_time"]), "weekdays": list(b["weekdays"] or []),
                     "trainer": f"{b['first_name']} {b['last_name']}" if b["first_name"] else None, "specialization": b["specialization"]}
    block = _checkin_block(rules, current is not None, inside)
    #Added By Nikhil 22Nov26 18:05 For "you forgot to check out" (reminder sent once; the visit stays open) START
    forgot = bool(inside and (visit["check_in_at"].astimezone(tz).date() < today
                              or (rules["close"] and now_tz().strftime("%H:%M") >= rules["close"])))
    if forgot:
        from app.modules.gym.jobs import notify_forgot_checkouts
        if await notify_forgot_checkouts(db, p["id"]):
            await db.commit()
    #Added By Nikhil 22Nov26 18:05 For "you forgot to check out" (reminder sent once; the visit stays open) END
    return {
        "forgot_checkout": forgot,  #Added By Nikhil 22Nov26 18:05 For "you forgot to check out"
        "location_required": bool(p["geo"]),  #Added By Nikhil 22Nov26 20:53 For location check-in (app asks for GPS only when needed)
        "inside_since": visit["check_in_at"].astimezone(tz).isoformat() if inside else None,  #Added By Nikhil 22Nov26 18:05 For open visit from an earlier day
        "today": today.isoformat(), "gym": acc.workspace.name, "branch": p["branch_name"], "member_code": p["member_code"],
        "joined_on": p["joined_on"].isoformat(),
        "membership": _ms_out(current, today) if current else None,
        "upcoming": [_ms_out(m, today) for m in upcoming],
        "last_expired": _ms_out(last, today) if last and not current else None,
        "inside_now": inside,
        "today_visit": {"check_in_at": today_visit["check_in_at"].astimezone(tz).isoformat(),
                        "check_out_at": today_visit["check_out_at"].astimezone(tz).isoformat() if today_visit["check_out_at"] else None}
        if today_visit else None,
        "hours_today": rules, "batch": batch,
        "can_check_in": not inside and block is None, "can_check_out": inside, "check_in_note": None if inside else block,
    }


@router.post("/me/visit/checkin")
async def my_visit_checkin(workspace_id: str, req: GeoRequest | None = None, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):  #Modified By Nikhil 22Nov26 20:53 For location check-in. Old: no body
    """Member checks themselves in (trusted, decided 22Nov26): active membership, gym open now, not a holiday."""
    acc = await load_access(db, user, workspace_id)
    p = await _me_member(db, acc)
    today = _today()
    active = (await db.execute(text(
        f"SELECT 1 FROM {S}gym_memberships WHERE member_profile_id = :p AND status = 'active' AND start_date <= :t AND expiry_date >= :t"),
        {"p": p["id"], "t": today})).first() is not None
    block = _checkin_block(await _today_rules(db, p["branch_id"]), active, False)
    if block:
        raise HTTPException(status_code=400, detail=block)
    await _geo_check(db, p["branch_id"], req.lat if req else None, req.lng if req else None)  #Added By Nikhil 22Nov26 20:53 For location check-in (member)
    try:
        async with db.begin_nested():
            await db.execute(text(
                f"INSERT INTO {S}gym_member_attendance (branch_id, member_profile_id, check_in_at, checked_in_by) VALUES (:b, :p, :now, :u)"),
                {"b": p["branch_id"], "p": p["id"], "now": now_tz(), "u": user.id})
    except IntegrityError:
        raise HTTPException(status_code=400, detail="You are already checked in")
    await db.commit()
    return {"status": "checked_in"}


@router.post("/me/visit/checkout")
async def my_visit_checkout(workspace_id: str, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    acc = await load_access(db, user, workspace_id)
    p = await _me_member(db, acc)
    res = await db.execute(text(
        f"UPDATE {S}gym_member_attendance SET check_out_at = :now, checked_out_by = :u, updated_at = :now "
        "WHERE member_profile_id = :p AND check_out_at IS NULL"), {"now": now_tz(), "u": user.id, "p": p["id"]})
    if res.rowcount == 0:
        raise HTTPException(status_code=400, detail="You are not checked in")
    await db.commit()
    return {"status": "checked_out"}


@router.get("/me/visits")
async def my_visits(workspace_id: str, month: str | None = None, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    acc = await load_access(db, user, workspace_id)
    p = await _me_member(db, acc)
    d1, d2, label = _month_range(month)
    s, _ = _day_bounds(d1)
    _, e = _day_bounds(d2)
    tz = now_tz().tzinfo
    rows = (await db.execute(text(
        f"SELECT check_in_at, check_out_at FROM {S}gym_member_attendance WHERE member_profile_id = :p "
        "AND check_in_at >= :s AND check_in_at < :e ORDER BY check_in_at DESC"), {"p": p["id"], "s": s, "e": e})).mappings().all()
    visits = [{"check_in_at": r["check_in_at"].astimezone(tz).isoformat(),
               "check_out_at": r["check_out_at"].astimezone(tz).isoformat() if r["check_out_at"] else None,
               "minutes": int((r["check_out_at"] - r["check_in_at"]).total_seconds() // 60) if r["check_out_at"] else None} for r in rows]
    return {"month": label, "visits": visits, "count": len(visits), "days": len({v["check_in_at"][:10] for v in visits})}


@router.get("/me/payments")
async def my_payments(workspace_id: str, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    acc = await load_access(db, user, workspace_id)
    p = await _me_member(db, acc)
    today = _today()
    pays = (await db.execute(text(f"""
        SELECT g.id, g.amount_paise, g.method, g.reference_last_digits, g.status, g.paid_on, g.verified_at, ms.plan_name
          FROM {S}gym_payments g LEFT JOIN {S}gym_memberships ms ON ms.id = g.membership_id
         WHERE g.member_profile_id = :p AND g.status <> 'cancelled' ORDER BY g.paid_on DESC, g.created_at DESC"""), {"p": p["id"]})).mappings().all()
    hist = (await db.execute(text(f"""
        SELECT ms.id, ms.plan_name, ms.start_date, ms.expiry_date, ms.total_amount_paise, ms.status,
               (SELECT sum(amount_paise) FROM {S}gym_payments g WHERE g.membership_id = ms.id AND g.status = 'verified') AS paid,
               (SELECT sum(amount_paise) FROM {S}gym_payments g WHERE g.membership_id = ms.id AND g.status = 'pending') AS pending
          FROM {S}gym_memberships ms WHERE ms.member_profile_id = :p ORDER BY ms.start_date DESC"""), {"p": p["id"]})).mappings().all()
    return {
        "member_code": p["member_code"],
        "payments": [{"id": str(r["id"]), "amount": r["amount_paise"] / 100, "method": r["method"],
                      "reference": f"••{r['reference_last_digits']}" if r["reference_last_digits"] else None, "status": r["status"],
                      "paid_on": r["paid_on"].isoformat(), "towards": r["plan_name"],
                      "verified_on": r["verified_at"].astimezone(now_tz().tzinfo).date().isoformat() if r["verified_at"] else None} for r in pays],
        "memberships": [_ms_out(m, today) for m in hist],
    }


@router.get("/me/renew-options")
async def my_renew_options(workspace_id: str, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    acc = await load_access(db, user, workspace_id)
    p = await _me_member(db, acc)
    plans = (await db.execute(text(
        f"SELECT id, name, duration_months, price_paise, description FROM {S}gym_plans WHERE branch_id = :b AND status = 'active' "
        "ORDER BY duration_months, price_paise"), {"b": p["branch_id"]})).mappings().all()
    upi = (await db.execute(text(f"SELECT upi_id, upi_payee_name FROM {S}gym_branch_settings WHERE branch_id = :b"),
                            {"b": p["branch_id"]})).mappings().first()
    return {"plans": [{"id": str(r["id"]), "name": r["name"], "months": r["duration_months"], "price": r["price_paise"] / 100,
                       "description": r["description"]} for r in plans],
            "upi_id": upi["upi_id"] if upi else None, "upi_payee_name": upi["upi_payee_name"] if upi else None}


class RenewRequest(BaseModel):
    plan_id: str
    reference_last_digits: str = Field(..., min_length=4, max_length=6, pattern=r"^[0-9A-Za-z]+$")


@router.post("/me/renew", status_code=201)
async def my_renew(workspace_id: str, req: RenewRequest, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """Member says "I paid the gym by UPI". Server takes the amount from the plan (never from the app); the payment stays
    PENDING until the owner / a manager verifies it and assigns the plan."""
    acc = await load_access(db, user, workspace_id)
    p = await _me_member(db, acc)
    plan = (await db.execute(text(
        f"SELECT id, name, price_paise FROM {S}gym_plans WHERE id = :x AND branch_id = :b AND status = 'active'"),
        {"x": _uuid(req.plan_id, "Plan"), "b": p["branch_id"]})).mappings().first()
    if not plan:
        raise HTTPException(status_code=400, detail="Pick a plan of your branch")
    if plan["price_paise"] <= 0:
        raise HTTPException(status_code=400, detail="This plan has no price. Please contact the gym.")
    open_req = (await db.execute(text(
        f"SELECT 1 FROM {S}gym_payments WHERE member_profile_id = :p AND status = 'pending' AND membership_id IS NULL "
        "AND notes LIKE 'Renewal request:%'"), {"p": p["id"]})).first()
    if open_req:
        raise HTTPException(status_code=400, detail="You already have a renewal waiting for the gym to confirm")
    pid = (await db.execute(text(
        f"INSERT INTO {S}gym_payments (branch_id, member_profile_id, membership_id, amount_paise, method, reference_last_digits, status, "
        "paid_on, notes, recorded_by, created_by, modified_by) VALUES (:b, :m, NULL, :a, 'upi', :ref, 'pending', :d, :n, :u, :u, :u) RETURNING id"),
        {"b": p["branch_id"], "m": p["id"], "a": plan["price_paise"], "ref": req.reference_last_digits, "d": _today(),
         "n": f"Renewal request: {plan['name']}", "u": user.id})).scalar_one()
    staff = (await db.execute(text(f"""
        SELECT DISTINCT wm.user_id FROM {S}workspace_members wm
          JOIN {S}module_role_permissions rp ON rp.role_id = wm.role_id
          JOIN {S}module_permissions mp ON mp.id = rp.permission_id AND mp.code = 'gym.payments.verify'
         WHERE wm.workspace_id = :w AND wm.status = 'active' AND (wm.branch_id = :b OR wm.branch_id IS NULL)"""),
        {"w": acc.workspace.id, "b": p["branch_id"]})).scalars().all()
    audit(db, user, "member.renew_requested", "gym_payments", pid, acc.workspace.id, {"plan": plan["name"]})
    await notify_users(db, [u for u in staff if u != user.id], category="payment",
                       title=f"Renewal payment to verify ({p['branch_name']})",
                       message=f"{user.first_name} {user.last_name} ({p['member_code']}) paid ₹{plan['price_paise'] // 100} by UPI for {plan['name']}. "
                               "Verify it in Payments, then assign the plan.",
                       workspace_id=acc.workspace.id, branch_id=p["branch_id"], actor_id=user.id)
    await db.commit()
    return {"status": "pending", "amount": plan["price_paise"] / 100, "plan": plan["name"]}


@router.get("/me/gym-info")
async def my_gym_info(workspace_id: str, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """Timings, upcoming holidays and contact of the caller's branch (any role in this business)."""
    acc = await load_access(db, user, workspace_id)
    bid = next((r.branch_id for r in acc.roles if r.branch_id), None)
    if bid is None:
        brs = await _branches(db, acc)
        if not brs:
            raise HTTPException(status_code=404, detail="No branch found")
        bid = brs[0]["id"]
    b = (await db.execute(text(f"SELECT name, address, phone FROM {S}workspace_branches WHERE id = :b"), {"b": bid})).mappings().first()
    hours = (await db.execute(text(
        f"SELECT weekday, is_closed, open_time, close_time FROM {S}gym_branch_hours WHERE branch_id = :b ORDER BY weekday"),
        {"b": bid})).mappings().all()
    hols = (await db.execute(text(
        f"SELECT holiday_date, reason FROM {S}gym_holidays WHERE branch_id = :b AND is_active AND holiday_date >= :t ORDER BY holiday_date LIMIT 10"),
        {"b": bid, "t": _today()})).mappings().all()
    upi = (await db.execute(text(f"SELECT upi_id, upi_payee_name FROM {S}gym_branch_settings WHERE branch_id = :b"), {"b": bid})).mappings().first()
    return {"gym": acc.workspace.name, "branch": b["name"], "address": b["address"], "phone": b["phone"],
            "hours": [{"weekday": h["weekday"], "closed": h["is_closed"], "open": _t(h["open_time"]), "close": _t(h["close_time"])} for h in hours],
            "holidays": [{"date": h["holiday_date"].isoformat(), "reason": h["reason"]} for h in hols],
            "upi_id": upi["upi_id"] if upi else None, "upi_payee_name": upi["upi_payee_name"] if upi else None}
#Added By Nikhil 22Nov26 17:36 For member screens: home, check-in/out, visits, payments, renew, gym info END


#Added By Nikhil 22Nov26 20:53 For "Inside now" / "Visits today" lists (who checked in) START
@router.get("/visits")
async def list_visits(workspace_id: str, date_: str | None = Query(None, alias="date"), branch_id: str | None = None,
                      inside: bool = False, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """inside=true → everyone checked in and not yet out (same rule as the 'Inside now' count); else the visits of one day."""
    acc = await load_access(db, user, workspace_id)
    ids = await _scope(db, acc, branch_id, "gym.attendance.view")
    try:
        d = date.fromisoformat(date_) if date_ else _today()
    except ValueError:
        raise HTTPException(status_code=400, detail="Date must look like 2026-11-22")
    s, e = _day_bounds(d)
    rows = (await db.execute(text(f"""
        SELECT a.check_in_at, a.check_out_at, p.id AS profile_id, p.member_code, b.name AS branch_name, u.first_name, u.last_name
          FROM {S}gym_member_attendance a
          JOIN {S}gym_member_profiles p ON p.id = a.member_profile_id
          JOIN {S}workspace_members wm ON wm.id = p.workspace_member_id
          JOIN {S}users u ON u.id = wm.user_id
          JOIN {S}workspace_branches b ON b.id = a.branch_id
         WHERE a.branch_id = ANY(:b)
           AND (CASE WHEN :inside THEN a.check_out_at IS NULL ELSE a.check_in_at >= :s AND a.check_in_at < :e END)
         ORDER BY a.check_in_at DESC"""), {"b": ids, "inside": inside, "s": s, "e": e})).mappings().all()
    tz = now_tz().tzinfo
    today = _today()
    items = [{
        "profile_id": str(r["profile_id"]), "name": f"{r['first_name']} {r['last_name']}", "member_code": r["member_code"],
        "branch_name": r["branch_name"], "check_in_at": r["check_in_at"].astimezone(tz).isoformat(),
        "check_out_at": r["check_out_at"].astimezone(tz).isoformat() if r["check_out_at"] else None,
        "minutes": int((r["check_out_at"] - r["check_in_at"]).total_seconds() // 60) if r["check_out_at"] else None,
        "inside": r["check_out_at"] is None,
        "forgot_checkout": r["check_out_at"] is None and r["check_in_at"].astimezone(tz).date() < today,
    } for r in rows]
    return {"date": d.isoformat(), "inside_only": inside, "visits": items, "count": len(items)}
#Added By Nikhil 22Nov26 20:53 For "Inside now" / "Visits today" lists (who checked in) END
