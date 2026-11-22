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
