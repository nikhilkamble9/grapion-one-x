# //Added By Nikhil 21Nov26 21:00 For public reference data (country picker)
from fastapi import APIRouter

from app.core.countries import COUNTRIES

router = APIRouter(prefix="/meta", tags=["Meta"])


@router.get("/countries")
async def list_countries():
    # Public on purpose: the Create Account screen needs it before the user has a token.
    # Contains no user data — only country names, dial codes and currency codes.
    return {"countries": COUNTRIES}


#Added By Nikhil 22Nov26 08:35 For support contact (public) + live announcement banners (signed in) START
from fastapi import Depends  # noqa: E402
from sqlalchemy import select  # noqa: E402
from sqlalchemy.ext.asyncio import AsyncSession  # noqa: E402

from app.core.dependencies import get_current_user  # noqa: E402
from app.core.platform_settings import get_setting  # noqa: E402
from app.db.models import PlatformAnnouncement, User  # noqa: E402
from app.db.session import get_db  # noqa: E402
from app.modules.workspaces.access import now_tz  # noqa: E402


@router.get("/support")
async def support_contact(db: AsyncSession = Depends(get_db)):
    # Public: users who cannot sign in (forgot password, disabled account) still need a way to reach support.
    return await get_setting(db, "support_contact")


@router.get("/announcements")
async def live_announcements(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    now = now_tz()
    audiences = ["all", "admins" if user.role in ("super_admin", "admin") else "users"]
    rows = (await db.execute(
        select(PlatformAnnouncement)
        .where(PlatformAnnouncement.is_active == True, PlatformAnnouncement.starts_at <= now,
               PlatformAnnouncement.ends_at >= now, PlatformAnnouncement.audience.in_(audiences))
        .order_by(PlatformAnnouncement.starts_at.desc()).limit(3)
    )).scalars().all()
    return {"announcements": [{"id": str(a.id), "title": a.title, "message": a.message, "style": a.style} for a in rows]}
#Added By Nikhil 22Nov26 08:35 For support contact (public) + live announcement banners (signed in) END


#Added By Nikhil 22Nov26 23:30 For app version (release history; phase-2 forced update) START
from fastapi import HTTPException, Query  # noqa: E402
from sqlalchemy import text  # noqa: E402
from zoneinfo import ZoneInfo  # noqa: E402

from app.core.config import settings  # noqa: E402


@router.get("/app-version")
async def app_version(platform: str = Query(..., pattern="^(android|ios|web|api)$"), db: AsyncSession = Depends(get_db)):
    # Public: an app checks this before (or without) signing in. Holds no user data.
    cur = (await db.execute(text(
        "SELECT version, build_number, released_at, release_notes FROM grapion_one_x.app_releases "
        "WHERE platform = :p AND is_current"), {"p": platform})).first()
    if cur is None:
        raise HTTPException(status_code=404, detail="No release recorded for this platform")
    # Phase 2: an installed build below min_build must update before it can be used.
    min_build = (await db.execute(text(
        "SELECT COALESCE(MAX(build_number), 0) FROM grapion_one_x.app_releases "
        "WHERE platform = :p AND force_update AND build_number <= :b"), {"p": platform, "b": cur.build_number})).scalar_one()
    return {
        "platform": platform,
        "version": cur.version,
        "build_number": cur.build_number,
        "released_at": cur.released_at.astimezone(ZoneInfo(settings.APP_TIMEZONE)).isoformat(),  # server time zone (IST)
        "release_notes": cur.release_notes,
        "min_build": min_build,
    }
#Added By Nikhil 22Nov26 23:30 For app version (release history; phase-2 forced update) END
