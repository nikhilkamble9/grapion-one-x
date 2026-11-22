# //Added By Nikhil 18Nov26 21:30 For Subscription Request Schemas
from pydantic import BaseModel
from typing import List, Optional
import uuid

class ModuleItemOut(BaseModel):
    id: str
    code: str
    name: str
    description: Optional[str]
    icon: str
    status: str
    prices: dict # e.g. {"weekly": 599, "monthly": 1999, ...}

class ActiveDiscountOut(BaseModel):
    id: str
    title: str
    percent_off: float
    start_date: str
    end_date: str
    period_percent_off: Optional[dict] = None  #Added By Nikhil 21Nov26 21:00 For per-period discount (filled once DB columns exist)

class StoreCatalogResponse(BaseModel):
    modules: List[ModuleItemOut]
    active_discount: Optional[ActiveDiscountOut] = None
    user_currency: str = "INR"
    #Added By Nikhil 21Nov26 21:00 For display currency conversion START
    base_currency: str = "INR"
    currency_symbol: str = "₹"
    fx_rate: float = 1.0          # 1 INR = fx_rate user_currency
    fx_live: bool = True          # False = provider unreachable, prices shown in INR
    fx_updated_unix: Optional[int] = None
    fx_source: Optional[str] = None
    #Added By Nikhil 21Nov26 21:00 For display currency conversion END

#Added By Nikhil 21Nov26 21:00 For approved user's own modules START
class MyModuleOut(BaseModel):
    id: str
    code: str
    name: str
    description: Optional[str]
    icon: str
    status: str
    expires_at: str
    #Added By Nikhil 21Nov26 22:36 For subscription details in profile START
    starts_at: Optional[str] = None
    billing_period: Optional[str] = None
    days_left: int = 0
    state: str = "active"  # active | expired
    #Added By Nikhil 21Nov26 22:36 For subscription details in profile END

class MyModulesResponse(BaseModel):
    modules: List[MyModuleOut]
    expired_modules: List[MyModuleOut] = []  #Added By Nikhil 21Nov26 22:36 For "ended on … Renew"
#Added By Nikhil 21Nov26 21:00 For approved user's own modules END

class CreateSubscriptionRequest(BaseModel):
    module_ids: List[str]
    billing_period: str # weekly, monthly, quarterly, yearly
