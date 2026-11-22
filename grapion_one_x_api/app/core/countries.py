# //Added By Nikhil 21Nov26 21:00 For country, dial code and currency master (design list)
"""Single source for the country picker (app) and the user's display currency (API).

The app loads this list from GET /api/v1/meta/countries, so it is maintained in one place.
"""
from typing import TypedDict


class Country(TypedDict):
    code: str
    name: str
    dial: str
    currency: str
    symbol: str


COUNTRIES: list[Country] = [
    {"code": "IN", "name": "India", "dial": "+91", "currency": "INR", "symbol": "₹"},
    {"code": "US", "name": "United States", "dial": "+1", "currency": "USD", "symbol": "$"},
    {"code": "GB", "name": "United Kingdom", "dial": "+44", "currency": "GBP", "symbol": "£"},
    {"code": "CA", "name": "Canada", "dial": "+1", "currency": "CAD", "symbol": "CA$"},
    {"code": "AU", "name": "Australia", "dial": "+61", "currency": "AUD", "symbol": "AU$"},
    {"code": "AE", "name": "United Arab Emirates", "dial": "+971", "currency": "AED", "symbol": "AED "},
    {"code": "SA", "name": "Saudi Arabia", "dial": "+966", "currency": "SAR", "symbol": "SAR "},
    {"code": "DE", "name": "Germany", "dial": "+49", "currency": "EUR", "symbol": "€"},
    {"code": "FR", "name": "France", "dial": "+33", "currency": "EUR", "symbol": "€"},
    {"code": "IT", "name": "Italy", "dial": "+39", "currency": "EUR", "symbol": "€"},
    {"code": "ES", "name": "Spain", "dial": "+34", "currency": "EUR", "symbol": "€"},
    {"code": "NL", "name": "Netherlands", "dial": "+31", "currency": "EUR", "symbol": "€"},
    {"code": "CH", "name": "Switzerland", "dial": "+41", "currency": "CHF", "symbol": "CHF "},
    {"code": "SG", "name": "Singapore", "dial": "+65", "currency": "SGD", "symbol": "SG$"},
    {"code": "MY", "name": "Malaysia", "dial": "+60", "currency": "MYR", "symbol": "RM "},
    {"code": "ID", "name": "Indonesia", "dial": "+62", "currency": "IDR", "symbol": "Rp "},
    {"code": "TH", "name": "Thailand", "dial": "+66", "currency": "THB", "symbol": "฿"},
    {"code": "VN", "name": "Vietnam", "dial": "+84", "currency": "VND", "symbol": "₫"},
    {"code": "PH", "name": "Philippines", "dial": "+63", "currency": "PHP", "symbol": "₱"},
    {"code": "JP", "name": "Japan", "dial": "+81", "currency": "JPY", "symbol": "¥"},
    {"code": "KR", "name": "South Korea", "dial": "+82", "currency": "KRW", "symbol": "₩"},
    {"code": "CN", "name": "China", "dial": "+86", "currency": "CNY", "symbol": "¥"},
    {"code": "HK", "name": "Hong Kong", "dial": "+852", "currency": "HKD", "symbol": "HK$"},
    {"code": "NZ", "name": "New Zealand", "dial": "+64", "currency": "NZD", "symbol": "NZ$"},
    {"code": "ZA", "name": "South Africa", "dial": "+27", "currency": "ZAR", "symbol": "R "},
    {"code": "NG", "name": "Nigeria", "dial": "+234", "currency": "NGN", "symbol": "₦"},
    {"code": "KE", "name": "Kenya", "dial": "+254", "currency": "KES", "symbol": "KSh "},
    {"code": "EG", "name": "Egypt", "dial": "+20", "currency": "EGP", "symbol": "E£"},
    {"code": "BR", "name": "Brazil", "dial": "+55", "currency": "BRL", "symbol": "R$"},
    {"code": "MX", "name": "Mexico", "dial": "+52", "currency": "MXN", "symbol": "Mex$"},
    {"code": "QA", "name": "Qatar", "dial": "+974", "currency": "QAR", "symbol": "QR "},
    {"code": "KW", "name": "Kuwait", "dial": "+965", "currency": "KWD", "symbol": "KD "},
    {"code": "OM", "name": "Oman", "dial": "+968", "currency": "OMR", "symbol": "OMR "},
    {"code": "BH", "name": "Bahrain", "dial": "+973", "currency": "BHD", "symbol": "BD "},
    {"code": "TR", "name": "Turkey", "dial": "+90", "currency": "TRY", "symbol": "₺"},
    {"code": "RU", "name": "Russia", "dial": "+7", "currency": "RUB", "symbol": "₽"},
    {"code": "SE", "name": "Sweden", "dial": "+46", "currency": "SEK", "symbol": "kr "},
    {"code": "NO", "name": "Norway", "dial": "+47", "currency": "NOK", "symbol": "kr "},
    {"code": "DK", "name": "Denmark", "dial": "+45", "currency": "DKK", "symbol": "kr "},
    {"code": "PL", "name": "Poland", "dial": "+48", "currency": "PLN", "symbol": "zł"},
    {"code": "IE", "name": "Ireland", "dial": "+353", "currency": "EUR", "symbol": "€"},
    {"code": "IL", "name": "Israel", "dial": "+972", "currency": "ILS", "symbol": "₪"},
    {"code": "BD", "name": "Bangladesh", "dial": "+880", "currency": "BDT", "symbol": "৳"},
    {"code": "PK", "name": "Pakistan", "dial": "+92", "currency": "PKR", "symbol": "Rs "},
    {"code": "LK", "name": "Sri Lanka", "dial": "+94", "currency": "LKR", "symbol": "Rs "},
    {"code": "NP", "name": "Nepal", "dial": "+977", "currency": "NPR", "symbol": "Rs "},
]

_BY_CODE: dict[str, Country] = {c["code"]: c for c in COUNTRIES}
BASE_CURRENCY = "INR"


def country_for(code: str | None) -> Country:
    """Country row for a user's country_code; unknown codes fall back to India (base currency)."""
    return _BY_CODE.get((code or "").upper(), _BY_CODE["IN"])
