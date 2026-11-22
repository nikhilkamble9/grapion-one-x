# //Added By Nikhil 22Nov26 00:10 For push notifications via Firebase Cloud Messaging (free on the Spark plan)
"""Sends phone/browser notifications.

The in-app bell (notifications table) is always written first; push is a best-effort extra on top.
If Firebase is not configured or a send fails, nothing breaks — the bell still has the message.
"""
import asyncio
import logging
from pathlib import Path

import firebase_admin
from firebase_admin import credentials, messaging

from app.core.config import settings

logger = logging.getLogger(__name__)
_BACKEND_DIR = Path(__file__).resolve().parents[2]
_app: firebase_admin.App | None = None
_init_failed = False


def _firebase() -> firebase_admin.App | None:
    global _app, _init_failed
    if _app or _init_failed:
        return _app
    path = Path(settings.FIREBASE_CREDENTIALS_PATH)
    if not path.is_absolute():
        path = _BACKEND_DIR / path
    try:
        _app = firebase_admin.initialize_app(credentials.Certificate(str(path)), name="gonex")
    except Exception as exc:  # missing/invalid key file → push disabled, app keeps working
        _init_failed = True
        logger.warning("Firebase disabled: %s", exc.__class__.__name__)
    return _app


def _send_sync(tokens: list[str], title: str, body: str, data: dict[str, str] | None, dry_run: bool) -> list[str]:
    """Returns tokens Firebase says are dead (uninstalled app, expired, invalid)."""
    app = _firebase()
    if not app or not tokens:
        return []
    msg = messaging.MulticastMessage(
        tokens=tokens,
        notification=messaging.Notification(title=title, body=body),
        data={k: str(v) for k, v in (data or {}).items()},
        android=messaging.AndroidConfig(priority="high"),
    )
    resp = messaging.send_each_for_multicast(msg, dry_run=dry_run, app=app)
    dead = []
    for token, r in zip(tokens, resp.responses):
        if not r.success and isinstance(r.exception, (messaging.UnregisteredError, messaging.SenderIdMismatchError)):
            dead.append(token)
        elif not r.success:
            code = getattr(r.exception, "code", r.exception.__class__.__name__)
            if code in ("invalid-argument", "INVALID_ARGUMENT"):
                dead.append(token)
    return dead


async def send_push(tokens: list[str], title: str, body: str, data: dict[str, str] | None = None, dry_run: bool = False) -> list[str]:
    # firebase-admin is synchronous → run it off the event loop.
    try:
        return await asyncio.to_thread(_send_sync, tokens, title, body, data, dry_run)
    except Exception as exc:
        logger.warning("Push send failed: %s", exc.__class__.__name__)
        return []


def credentials_ok() -> bool:
    """True when the key loads and Google issues an access token for it (used by the health check)."""
    app = _firebase()
    if not app:
        return False
    try:
        tok = app.credential.get_access_token()
        return bool(tok.access_token)
    except Exception as exc:
        logger.warning("Firebase credential check failed: %s", exc.__class__.__name__)
        return False
