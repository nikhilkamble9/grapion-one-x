# //Added By Nikhil 22Nov26 08:35 For reading Platform Settings with safe defaults
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import PlatformSetting

DEFAULTS: dict[str, dict] = {
    "support_contact": {"phone": "", "email": "", "whatsapp": "", "hours": ""},
    "default_reminder_days": {"days": 7},
}


async def get_setting(db: AsyncSession, key: str) -> dict:
    row = (await db.execute(select(PlatformSetting.value).where(PlatformSetting.key == key))).scalar_one_or_none()
    return {**DEFAULTS.get(key, {}), **(row or {})}


async def default_reminder_days(db: AsyncSession) -> int:
    """Platform-wide default for EVERY module (gym today; wedding, medical, academy read it when built).  #Added By Nikhil 22Nov26 10:47 For reminder days for all modules"""
    try:
        return max(1, min(60, int((await get_setting(db, "default_reminder_days")).get("days", 7))))
    except (TypeError, ValueError):
        return 7
