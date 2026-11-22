# //Added By Nikhil 21Nov26 21:00 For live INR exchange rates (display-only conversion)
"""Live exchange rates with INR as the base currency.

Source: ExchangeRate-API open endpoint (https://www.exchangerate-api.com/docs/free) — no API key,
rates refresh once a day, attribution "Rates By Exchange Rate API" must be shown where rates appear.

Rates are cached in memory for FX_CACHE_SECONDS so the provider is called at most a few times a day.
If the provider is down we keep serving the last good rates; with none at all we fall back to INR
(rate 1.0, live=False) so the store never breaks. Amounts are still stored and charged in INR — the
converted figure is for display only.
"""
import asyncio
import logging
import time
from dataclasses import dataclass

import httpx

from app.core.countries import BASE_CURRENCY

logger = logging.getLogger(__name__)

FX_URL = f"https://open.er-api.com/v6/latest/{BASE_CURRENCY}"
FX_CACHE_SECONDS = 6 * 60 * 60
FX_TIMEOUT_SECONDS = 5.0
FX_SOURCE = "Rates By Exchange Rate API"


@dataclass(frozen=True)
class FxQuote:
    currency: str
    rate: float  # 1 INR = rate <currency>
    live: bool
    updated_unix: int | None


_rates: dict[str, float] = {}
_updated_unix: int | None = None
_fetched_at: float = 0.0
_lock = asyncio.Lock()


async def _refresh_if_stale() -> None:
    global _rates, _updated_unix, _fetched_at
    if _rates and time.monotonic() - _fetched_at < FX_CACHE_SECONDS:
        return
    async with _lock:
        if _rates and time.monotonic() - _fetched_at < FX_CACHE_SECONDS:
            return  # another request refreshed while we waited
        try:
            async with httpx.AsyncClient(timeout=FX_TIMEOUT_SECONDS) as client:
                resp = await client.get(FX_URL)
                resp.raise_for_status()
                data = resp.json()
            if data.get("result") != "success" or not isinstance(data.get("rates"), dict):
                raise ValueError("unexpected FX payload")
            _rates = {k: float(v) for k, v in data["rates"].items()}
            _updated_unix = int(data.get("time_last_update_unix") or 0) or None
            _fetched_at = time.monotonic()
        except (httpx.HTTPError, ValueError, TypeError) as exc:
            # Keep the last good rates; retry after a short back-off instead of on every request.
            logger.warning("FX refresh failed: %s", exc.__class__.__name__)
            _fetched_at = time.monotonic() - FX_CACHE_SECONDS + 300


async def quote(currency: str) -> FxQuote:
    currency = currency.upper()
    if currency == BASE_CURRENCY:
        return FxQuote(currency, 1.0, True, _updated_unix)
    await _refresh_if_stale()
    rate = _rates.get(currency)
    if rate is None or rate <= 0:
        return FxQuote(BASE_CURRENCY, 1.0, False, None)
    return FxQuote(currency, rate, True, _updated_unix)
