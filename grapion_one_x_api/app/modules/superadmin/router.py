# //Added By Nikhil 22Nov26 01:22 For Super Admin pages: admins, module prices, sales & discounts, audit history
"""Only role = super_admin may call anything here (require_super_admin on every route).

Every change is written to platform_audit_logs. The super admin account itself can never be
demoted, disabled or edited through these endpoints.
"""
from datetime import date, datetime, time
from uuid import UUID
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field, model_validator
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.config import settings
from app.core.dependencies import require_super_admin
from app.db.models import Discount, Module, ModulePrice, PlatformAuditLog, User
from app.db.session import get_db
from app.modules.workspaces.access import audit, now_tz

router = APIRouter(prefix="/superadmin", tags=["Super Admin"])
PERIODS = ("weekly", "monthly", "quarterly", "yearly")
TZ = ZoneInfo(settings.APP_TIMEZONE)


def _uuid(v: str, what: str) -> UUID:
    try:
        return UUID(v)
    except ValueError:
        raise HTTPException(status_code=404, detail=f"{what} not found")


# ---------------- Admins ----------------

def _admin_out(u: User) -> dict:
    return {
        "id": str(u.id),
        "name": f"{u.first_name} {u.last_name}",
        "username": u.username,
        "email": u.email,
        "mobile": f"{u.dial_code} {u.mobile_number}",
        "role": u.role,
        "is_active": u.is_active,
    }


@router.get("/admins")
async def list_admins(me: User = Depends(require_super_admin), db: AsyncSession = Depends(get_db)):
    rows = (await db.execute(
        select(User).where(User.role.in_(("super_admin", "admin"))).order_by(User.role.desc(), User.first_name)
    )).scalars().all()
    return {"admins": [_admin_out(u) for u in rows]}


class PromoteRequest(BaseModel):
    username: str = Field(..., min_length=3, max_length=50)


@router.post("/admins/promote")
async def promote_admin(req: PromoteRequest, me: User = Depends(require_super_admin), db: AsyncSession = Depends(get_db)):
    """Makes an existing registered user an admin (exact username)."""
    u = (await db.execute(select(User).where(User.username_clean == req.username.strip().lower()))).scalar_one_or_none()
    if not u:
        raise HTTPException(status_code=404, detail="No user with that exact username")
    if u.role != "user":
        raise HTTPException(status_code=400, detail="This account is already an admin")
    if not u.is_active:
        raise HTTPException(status_code=400, detail="This account is disabled")
    u.role = "admin"
    u.updated_at = now_tz()
    audit(db, me, "admin.promoted", "users", u.id, detail={"username": u.username})
    await db.commit()
    return _admin_out(u)


async def _target_admin(db: AsyncSession, me: User, admin_id: str) -> User:
    u = (await db.execute(select(User).where(User.id == _uuid(admin_id, "Admin")))).scalar_one_or_none()
    if not u or u.role != "admin":
        # super_admin (and therefore yourself) can never be targeted
        raise HTTPException(status_code=404, detail="Admin not found")
    return u


@router.post("/admins/{admin_id}/demote")
async def demote_admin(admin_id: str, me: User = Depends(require_super_admin), db: AsyncSession = Depends(get_db)):
    u = await _target_admin(db, me, admin_id)
    u.role = "user"
    u.updated_at = now_tz()
    audit(db, me, "admin.demoted", "users", u.id, detail={"username": u.username})
    await db.commit()
    return {"status": "demoted"}


class ActiveRequest(BaseModel):
    is_active: bool


@router.post("/admins/{admin_id}/active")
async def set_admin_active(admin_id: str, req: ActiveRequest, me: User = Depends(require_super_admin), db: AsyncSession = Depends(get_db)):
    u = await _target_admin(db, me, admin_id)
    u.is_active = req.is_active
    u.updated_at = now_tz()
    audit(db, me, "admin.enabled" if req.is_active else "admin.disabled", "users", u.id, detail={"username": u.username})
    await db.commit()
    return {"status": "enabled" if req.is_active else "disabled"}


# ---------------- Module pricing ----------------

@router.get("/modules")
async def list_module_prices(me: User = Depends(require_super_admin), db: AsyncSession = Depends(get_db)):
    mods = (await db.execute(select(Module).options(selectinload(Module.prices)).order_by(Module.display_order))).scalars().all()
    return {"modules": [{
        "code": m.code, "name": m.name, "icon": m.icon, "status": m.status,
        "prices": {p.period: p.price_paise // 100 for p in m.prices if p.is_active},
    } for m in mods]}


class PricesRequest(BaseModel):
    # Whole rupees, as typed by the super admin. Stored as paise.
    weekly: int = Field(..., ge=0, le=10_000_000)
    monthly: int = Field(..., ge=0, le=10_000_000)
    quarterly: int = Field(..., ge=0, le=10_000_000)
    yearly: int = Field(..., ge=0, le=10_000_000)


@router.put("/modules/{code}/prices")
async def update_module_prices(code: str, req: PricesRequest, me: User = Depends(require_super_admin), db: AsyncSession = Depends(get_db)):
    m = (await db.execute(select(Module).options(selectinload(Module.prices)).where(Module.code == code))).scalar_one_or_none()
    if not m:
        raise HTTPException(status_code=404, detail="Module not found")
    before = {p.period: p.price_paise // 100 for p in m.prices}
    by_period = {p.period: p for p in m.prices}
    for period in PERIODS:
        paise = getattr(req, period) * 100
        if period in by_period:
            by_period[period].price_paise = paise
            by_period[period].is_active = True
        else:
            db.add(ModulePrice(module_id=m.id, period=period, price_paise=paise, currency="INR", is_active=True))
    # Existing requests keep the price they were created with (items store their own price).
    audit(db, me, "module_price.updated", "module_prices", m.id, detail={"module": code, "before": before, "after": req.model_dump()})
    await db.commit()
    return {"status": "updated"}


# ---------------- Sales & discounts ----------------

def _discount_out(d: Discount) -> dict:
    return {
        "id": str(d.id),
        "title": d.title,
        "percent_off": float(d.percent_off),
        "period_percent_off": {p: d.percent_for(p) for p in PERIODS},
        "start_date": d.start_date.astimezone(TZ).date().isoformat(),
        "end_date": d.end_date.astimezone(TZ).date().isoformat(),
        "is_active": d.is_active,
        "is_live": d.is_active and d.start_date <= now_tz() <= d.end_date,
    }


@router.get("/discounts")
async def list_discounts(me: User = Depends(require_super_admin), db: AsyncSession = Depends(get_db)):
    rows = (await db.execute(select(Discount).order_by(Discount.start_date.desc()))).scalars().all()
    return {"discounts": [_discount_out(d) for d in rows]}


class DiscountRequest(BaseModel):
    title: str = Field(..., min_length=2, max_length=150)
    weekly: float = Field(..., ge=0, le=100)
    monthly: float = Field(..., ge=0, le=100)
    quarterly: float = Field(..., ge=0, le=100)
    yearly: float = Field(..., ge=0, le=100)
    start_date: date  # whole days in IST: start 00:00, end 23:59:59
    end_date: date
    is_active: bool = True

    @model_validator(mode="after")
    def check(self):
        if self.end_date < self.start_date:
            raise ValueError("End date must be on or after the start date")
        if max(self.weekly, self.monthly, self.quarterly, self.yearly) <= 0:
            raise ValueError("At least one period needs a discount above 0%")
        return self


def _apply(d: Discount, req: DiscountRequest):
    d.title = req.title.strip()
    d.weekly_percent_off = req.weekly
    d.monthly_percent_off = req.monthly
    d.quarterly_percent_off = req.quarterly
    d.yearly_percent_off = req.yearly
    d.percent_off = max(req.weekly, req.monthly, req.quarterly, req.yearly)  # legacy column: must be > 0
    d.start_date = datetime.combine(req.start_date, time(0, 0, 0), TZ)
    d.end_date = datetime.combine(req.end_date, time(23, 59, 59), TZ)
    d.is_active = req.is_active


@router.post("/discounts", status_code=201)
async def create_discount(req: DiscountRequest, me: User = Depends(require_super_admin), db: AsyncSession = Depends(get_db)):
    d = Discount(created_at=now_tz())
    _apply(d, req)
    db.add(d)
    await db.flush()
    audit(db, me, "discount.created", "discounts", d.id, detail=req.model_dump(mode="json"))
    await db.commit()
    return _discount_out(d)


@router.put("/discounts/{discount_id}")
async def update_discount(discount_id: str, req: DiscountRequest, me: User = Depends(require_super_admin), db: AsyncSession = Depends(get_db)):
    d = (await db.execute(select(Discount).where(Discount.id == _uuid(discount_id, "Sale")))).scalar_one_or_none()
    if not d:
        raise HTTPException(status_code=404, detail="Sale not found")
    before = _discount_out(d)
    _apply(d, req)
    audit(db, me, "discount.updated", "discounts", d.id, detail={"before": before, "after": req.model_dump(mode="json")})
    await db.commit()
    return _discount_out(d)


# ---------------- Audit history ----------------

@router.get("/audit")
async def audit_history(
    limit: int = Query(50, ge=1, le=200),
    before: str | None = Query(None, description="ISO time of the last row seen (keyset pagination)"),
    me: User = Depends(require_super_admin),
    db: AsyncSession = Depends(get_db),
):
    q = select(PlatformAuditLog, User.first_name, User.last_name, User.username).outerjoin(
        User, User.id == PlatformAuditLog.actor_id
    )
    if before:
        try:
            q = q.where(PlatformAuditLog.created_at < datetime.fromisoformat(before))
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid cursor")
    rows = (await db.execute(q.order_by(PlatformAuditLog.created_at.desc()).limit(limit))).all()
    items = [{
        "id": str(a.id),
        "when": a.created_at.astimezone(TZ).isoformat() if a.created_at else None,
        "actor": f"{fn} {ln} (@{un})" if un else "system",
        "actor_role": a.actor_role,
        "action": a.action,
        "entity": a.entity,
        "detail": a.detail,
    } for a, fn, ln, un in rows]
    return {"items": items, "next_before": items[-1]["when"] if len(items) == limit else None}


#Added By Nikhil 22Nov26 08:35 For Platform Settings (support contact, reminder days) + announcement banners START
from app.core.platform_settings import get_setting  # noqa: E402
from app.db.models import PlatformAnnouncement, PlatformSetting  # noqa: E402


class SupportContact(BaseModel):
    phone: str = Field("", max_length=20, pattern=r"^[0-9+\-\s]*$")
    email: str = Field("", max_length=120, pattern=r"^$|^[^@\s]+@[^@\s]+\.[^@\s]+$")
    whatsapp: str = Field("", max_length=20, pattern=r"^[0-9+\-\s]*$")
    hours: str = Field("", max_length=80)


class SettingsRequest(BaseModel):
    support_contact: SupportContact
    default_reminder_days: int = Field(..., ge=1, le=60)


@router.get("/settings")
async def get_settings(me: User = Depends(require_super_admin), db: AsyncSession = Depends(get_db)):
    return {
        "support_contact": await get_setting(db, "support_contact"),
        "default_reminder_days": (await get_setting(db, "default_reminder_days"))["days"],
    }


async def _put_setting(db: AsyncSession, me: User, key: str, value: dict) -> dict:
    row = (await db.execute(select(PlatformSetting).where(PlatformSetting.key == key))).scalar_one_or_none()
    before = dict(row.value) if row else None
    if row:
        row.value = value
        row.updated_at = now_tz()
        row.updated_by = me.id
    else:
        db.add(PlatformSetting(key=key, value=value, updated_at=now_tz(), updated_by=me.id))
    return {"before": before, "after": value}


@router.put("/settings")
async def update_settings(req: SettingsRequest, me: User = Depends(require_super_admin), db: AsyncSession = Depends(get_db)):
    changes = {
        "support_contact": await _put_setting(db, me, "support_contact", req.support_contact.model_dump()),
        "default_reminder_days": await _put_setting(db, me, "default_reminder_days", {"days": req.default_reminder_days}),
    }
    audit(db, me, "platform_settings.updated", "platform_settings", detail=changes)
    await db.commit()
    return {"status": "updated"}


def _announcement_out(a: PlatformAnnouncement) -> dict:
    now = now_tz()
    return {
        "id": str(a.id), "title": a.title, "message": a.message, "style": a.style, "audience": a.audience,
        "start_date": a.starts_at.astimezone(TZ).date().isoformat(),
        "end_date": a.ends_at.astimezone(TZ).date().isoformat(),
        "is_active": a.is_active,
        "is_live": a.is_active and a.starts_at <= now <= a.ends_at,
    }


class AnnouncementRequest(BaseModel):
    title: str = Field(..., min_length=2, max_length=120)
    message: str = Field(..., min_length=2, max_length=500)
    style: str = Field("info", pattern="^(info|success|warning)$")
    audience: str = Field("all", pattern="^(all|users|admins)$")
    start_date: date  # whole IST days, like sales
    end_date: date
    is_active: bool = True

    @model_validator(mode="after")
    def check(self):
        if self.end_date < self.start_date:
            raise ValueError("End date must be on or after the start date")
        return self


def _apply_announcement(a: PlatformAnnouncement, req: AnnouncementRequest, me: User):
    a.title = req.title.strip()
    a.message = req.message.strip()
    a.style = req.style
    a.audience = req.audience
    a.starts_at = datetime.combine(req.start_date, time(0, 0, 0), TZ)
    a.ends_at = datetime.combine(req.end_date, time(23, 59, 59), TZ)
    a.is_active = req.is_active
    a.updated_at = now_tz()
    a.modified_by = me.id


@router.get("/announcements")
async def list_announcements(me: User = Depends(require_super_admin), db: AsyncSession = Depends(get_db)):
    rows = (await db.execute(select(PlatformAnnouncement).order_by(PlatformAnnouncement.starts_at.desc()).limit(100))).scalars().all()
    return {"announcements": [_announcement_out(a) for a in rows]}


@router.post("/announcements", status_code=201)
async def create_announcement(req: AnnouncementRequest, me: User = Depends(require_super_admin), db: AsyncSession = Depends(get_db)):
    a = PlatformAnnouncement(created_at=now_tz(), created_by=me.id)
    _apply_announcement(a, req, me)
    db.add(a)
    await db.flush()
    audit(db, me, "announcement.created", "platform_announcements", a.id, detail=req.model_dump(mode="json"))
    await db.commit()
    return _announcement_out(a)


@router.put("/announcements/{announcement_id}")
async def update_announcement(announcement_id: str, req: AnnouncementRequest, me: User = Depends(require_super_admin), db: AsyncSession = Depends(get_db)):
    a = (await db.execute(select(PlatformAnnouncement).where(
        PlatformAnnouncement.id == _uuid(announcement_id, "Announcement")))).scalar_one_or_none()
    if not a:
        raise HTTPException(status_code=404, detail="Announcement not found")
    before = _announcement_out(a)
    _apply_announcement(a, req, me)
    audit(db, me, "announcement.updated", "platform_announcements", a.id, detail={"before": before, "after": req.model_dump(mode="json")})
    await db.commit()
    return _announcement_out(a)
#Added By Nikhil 22Nov26 08:35 For Platform Settings (support contact, reminder days) + announcement banners END


#Added By Nikhil 22Nov26 23:30 For app release history (record each Play Store / web / API release) START
from sqlalchemy import text  # noqa: E402
from sqlalchemy.exc import IntegrityError  # noqa: E402


class ReleaseRequest(BaseModel):
    platform: str = Field(..., pattern="^(android|ios|web|api)$")
    version: str = Field(..., pattern=r"^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,4}$")
    build_number: int = Field(..., ge=1, le=2_000_000_000)
    git_commit: str | None = Field(None, pattern="^[0-9a-f]{7,40}$")
    release_notes: str | None = Field(None, max_length=1000)
    force_update: bool = False
    make_current: bool = True


def _release_out(r) -> dict:
    return {
        "id": str(r.id), "platform": r.platform, "version": r.version, "build_number": r.build_number,
        "git_commit": r.git_commit, "release_notes": r.release_notes, "is_current": r.is_current,
        "force_update": r.force_update, "released_at": r.released_at.astimezone(TZ).isoformat(),
    }


@router.get("/releases")
async def list_releases(me: User = Depends(require_super_admin), db: AsyncSession = Depends(get_db)):
    rows = (await db.execute(text(
        "SELECT id, platform, version, build_number, git_commit, release_notes, is_current, force_update, released_at "
        "FROM grapion_one_x.app_releases ORDER BY platform, build_number DESC"))).all()
    return {"releases": [_release_out(r) for r in rows]}


@router.post("/releases", status_code=201)
async def create_release(req: ReleaseRequest, me: User = Depends(require_super_admin), db: AsyncSession = Depends(get_db)):
    # Play Store rule: every upload needs a higher build number (versionCode) than the last one.
    last = (await db.execute(text(
        "SELECT COALESCE(MAX(build_number), 0) FROM grapion_one_x.app_releases WHERE platform = :p"),
        {"p": req.platform})).scalar_one()
    if req.build_number <= last:
        raise HTTPException(status_code=400, detail=f"Build number must be higher than {last} (the last {req.platform} build)")
    try:
        if req.make_current:
            await db.execute(text("UPDATE grapion_one_x.app_releases SET is_current = FALSE WHERE platform = :p AND is_current"),
                             {"p": req.platform})
        row = (await db.execute(text(
            "INSERT INTO grapion_one_x.app_releases (platform, version, build_number, git_commit, release_notes, is_current, force_update, released_at, created_by) "
            "VALUES (:platform, :version, :build_number, :git_commit, :release_notes, :is_current, :force_update, :at, :by) "
            "RETURNING id, platform, version, build_number, git_commit, release_notes, is_current, force_update, released_at"),
            {**req.model_dump(exclude={"make_current"}), "is_current": req.make_current, "at": now_tz(), "by": me.id})).first()
        audit(db, me, "app_release.created", "app_releases", row.id, detail=req.model_dump())
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(status_code=400, detail="This release is already recorded")
    return _release_out(row)
#Added By Nikhil 22Nov26 23:30 For app release history (record each Play Store / web / API release) END
