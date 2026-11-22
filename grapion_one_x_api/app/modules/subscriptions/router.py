# //Added By Nikhil 18Nov26 21:31 For Modules & Subscription Management
from datetime import datetime, timezone
from zoneinfo import ZoneInfo
import uuid
import random
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from sqlalchemy.orm import selectinload
from app.db.session import get_db
from app.db.models import Module, ModulePrice, Discount, SubscriptionRequest, SubscriptionRequestItem, UserModuleSubscription, User
from app.core.dependencies import get_current_user
from app.core.config import settings
from app.modules.subscriptions.schemas import StoreCatalogResponse, ModuleItemOut, ActiveDiscountOut, CreateSubscriptionRequest
from app.modules.subscriptions.schemas import MyModuleOut, MyModulesResponse  #Added By Nikhil 21Nov26 21:00 For approved user's modules
from app.core.countries import country_for, BASE_CURRENCY  #Added By Nikhil 21Nov26 21:00 For display currency
from app.core import fx  #Added By Nikhil 21Nov26 21:00 For display currency

router = APIRouter(prefix="/subscriptions", tags=["Subscriptions"])

@router.get("/catalog", response_model=StoreCatalogResponse)
async def get_store_catalog(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    # 1. Fetch modules and their prices from table
    mod_res = await db.execute(
        select(Module).options(selectinload(Module.prices)).order_by(Module.display_order)
    )
    modules_db = mod_res.scalars().all()

    module_items = []
    for m in modules_db:
        price_dict = {}
        for p in m.prices:
            if p.is_active:
                # Convert integer paise to display amount (e.g. 199900 -> 1999)
                price_dict[p.period] = p.price_paise // 100
        module_items.append(ModuleItemOut(
            id=str(m.id),
            code=m.code,
            name=m.name,
            description=m.description,
            icon=m.icon,
            status=m.status,
            prices=price_dict
        ))

    # 2. Fetch active festival discount dynamically
    now_tz = datetime.now(ZoneInfo(settings.APP_TIMEZONE))
    disc_res = await db.execute(
        select(Discount).where(
            Discount.is_active == True,
            Discount.start_date <= now_tz,
            Discount.end_date >= now_tz
        ).order_by(Discount.percent_off.desc())
    )
    discount_db = disc_res.scalars().first()  #Modified By Nikhil 21Nov26 22:44 For overlapping sales (best one wins). Old: disc_res.scalar_one_or_none()
    active_discount = None
    if discount_db:
        active_discount = ActiveDiscountOut(
            id=str(discount_db.id),
            title=discount_db.title,
            percent_off=float(discount_db.percent_off),
            start_date=discount_db.start_date.astimezone(ZoneInfo(settings.APP_TIMEZONE)).isoformat(),  #Modified By Nikhil 21Nov26 22:44 For IST dates. Old: discount_db.start_date.isoformat()
            end_date=discount_db.end_date.astimezone(ZoneInfo(settings.APP_TIMEZONE)).isoformat(),  #Modified By Nikhil 21Nov26 22:44 For IST dates. Old: discount_db.end_date.isoformat()
            period_percent_off={p: discount_db.percent_for(p) for p in ("weekly", "monthly", "quarterly", "yearly")},  #Added By Nikhil 21Nov26 22:44 For per-period discount
        )

    #Modified By Nikhil 21Nov26 21:00 For user's display currency. Old: return StoreCatalogResponse(modules=module_items, active_discount=active_discount, user_currency="INR")
    country = country_for(current_user.country_code)
    q = await fx.quote(country["currency"])
    return StoreCatalogResponse(
        modules=module_items,
        active_discount=active_discount,
        user_currency=q.currency,
        base_currency=BASE_CURRENCY,
        currency_symbol=country["symbol"] if q.live and q.currency == country["currency"] else "₹",
        fx_rate=q.rate,
        fx_live=q.live,
        fx_updated_unix=q.updated_unix,
        fx_source=fx.FX_SOURCE if q.currency != BASE_CURRENCY else None,
    )

@router.post("/request", status_code=status.HTTP_201_CREATED)
async def create_request(
    req: CreateSubscriptionRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    if not req.module_ids:
        raise HTTPException(status_code=400, detail="Please select at least one module")
    if req.billing_period not in ["weekly", "monthly", "quarterly", "yearly"]:
        raise HTTPException(status_code=400, detail="Invalid billing period")

    # Check if user already has an active pending request
    existing = await db.execute(
        select(SubscriptionRequest).where(
            SubscriptionRequest.user_id == current_user.id,
            SubscriptionRequest.status == "pending"
        )
    )
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="You already have a pending subscription request awaiting approval")

    # Fetch modules
    parsed_ids = [uuid.UUID(mid) for mid in req.module_ids]
    m_res = await db.execute(
        select(Module).options(selectinload(Module.prices)).where(Module.id.in_(parsed_ids))
    )
    selected_modules = m_res.scalars().all()
    if len(selected_modules) != len(parsed_ids):
        raise HTTPException(status_code=400, detail="One or more selected modules are invalid")

    #Removed By Nikhil 22Nov26 10:47 For renewals of an active module (any period) — end date extends on approval. Old: rejected with "You already have an active subscription for one of the selected modules"
    #Added By Nikhil 22Nov26 10:47 For no renewal while that module has an open cancellation START
    from app.db.models import SubscriptionCancellation
    open_c = await db.execute(
        select(SubscriptionCancellation.id)
        .join(UserModuleSubscription, UserModuleSubscription.id == SubscriptionCancellation.user_module_subscription_id)
        .where(
            SubscriptionCancellation.user_id == current_user.id,
            SubscriptionCancellation.status == "requested",
            UserModuleSubscription.module_id.in_(parsed_ids),
        )
    )
    if open_c.first():
        raise HTTPException(status_code=400, detail="One of the selected modules has an open cancellation. Withdraw it first to renew.")
    #Added By Nikhil 22Nov26 10:47 For no renewal while that module has an open cancellation END

    # Calculate total paise
    total_base_paise = 0
    item_prices = {}
    for m in selected_modules:
        price_obj = next((p for p in m.prices if p.period == req.billing_period and p.is_active), None)
        if not price_obj:
            raise HTTPException(status_code=400, detail=f"Pricing not found for module {m.name} ({req.billing_period})")
        item_prices[m.id] = price_obj.price_paise
        total_base_paise += price_obj.price_paise

    # Check active discount
    now_tz = datetime.now(ZoneInfo(settings.APP_TIMEZONE))
    disc_res = await db.execute(
        select(Discount).where(
            Discount.is_active == True,
            Discount.start_date <= now_tz,
            Discount.end_date >= now_tz
        ).order_by(Discount.percent_off.desc())
    )
    discount_db = disc_res.scalars().first()  #Modified By Nikhil 21Nov26 22:44 For overlapping sales (best one wins). Old: disc_res.scalar_one_or_none()
    discount_paise = 0
    if discount_db:
        #Modified By Nikhil 21Nov26 22:44 For per-period discount. Old: int(total_base_paise * (float(discount_db.percent_off) / 100.0))
        discount_paise = int(total_base_paise * (discount_db.percent_for(req.billing_period) / 100.0))

    final_paise = total_base_paise - discount_paise
    # Format: GOX-YYMMDD-XXXX (Server time zone IST + 4-digit unique token)
    # //Added By Nikhil 18Nov26 23:06 For Enterprise Request ID Format
    date_part = now_tz.strftime("%y%m%d")
    random_part = random.randint(1000, 9999)
    req_number = f"GOX-{date_part}-{random_part}"

    sub_req = SubscriptionRequest(
        request_number=req_number,
        user_id=current_user.id,
        billing_period=req.billing_period,
        currency="INR",
        base_amount_paise=total_base_paise,
        discount_amount_paise=discount_paise,
        final_amount_paise=final_paise,
        applied_discount_id=discount_db.id if discount_db else None,
        status="pending"
    )
    db.add(sub_req)
    await db.flush()

    for mid, price in item_prices.items():
        db.add(SubscriptionRequestItem(
            request_id=sub_req.id,
            module_id=mid,
            price_paise=price
        ))

    await db.commit()
    await db.refresh(sub_req)

    return {
        "status": "pending",
        "request_number": sub_req.request_number,
        "message": "Subscription request submitted for admin review",
        "total_amount_display": final_paise // 100
    }

@router.get("/my-status")
async def get_my_status(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    # Check if admin
    if current_user.role in ("super_admin", "admin"):  #Modified By Nikhil 21Nov26 23:30 For super admin role. Old: if current_user.role == "admin":
        return {
            "has_access": True,
            "is_admin": True,
            "active_modules": ["gym", "wedding", "medical", "academy"],
            "pending_request": None
        }

    # Check active subscriptions
    now_tz = datetime.now(ZoneInfo(settings.APP_TIMEZONE))
    subs_res = await db.execute(
        select(UserModuleSubscription)
        .options(selectinload(UserModuleSubscription.module))
        .where(
            UserModuleSubscription.user_id == current_user.id,
            UserModuleSubscription.is_active == True,
            UserModuleSubscription.expires_at >= now_tz
        )
    )
    active_subs = subs_res.scalars().all()
    if active_subs:
        return {
            "has_access": True,
            "is_admin": False,
            "active_modules": [s.module.code for s in active_subs],
            "pending_request": None
        }

    # Check pending request
    req_res = await db.execute(
        select(SubscriptionRequest).where(
            SubscriptionRequest.user_id == current_user.id,
            SubscriptionRequest.status == "pending"
        ).order_by(SubscriptionRequest.created_at.desc())
    )
    pending = req_res.scalar_one_or_none()

    #Added By Nikhil 21Nov26 22:36 For "Your subscription ended on … Renew" START
    ended_res = await db.execute(
        select(UserModuleSubscription)
        .options(selectinload(UserModuleSubscription.module))
        .where(UserModuleSubscription.user_id == current_user.id)
        .order_by(UserModuleSubscription.expires_at.desc())
        .limit(1)
    )
    last_sub = ended_res.scalar_one_or_none()
    ended = {
        "module_code": last_sub.module.code,
        "module_name": last_sub.module.name,
        "ended_at": last_sub.expires_at.astimezone(ZoneInfo(settings.APP_TIMEZONE)).isoformat(),
    } if last_sub else None
    #Added By Nikhil 21Nov26 22:36 For "Your subscription ended on … Renew" END

    return {
        "has_access": False,
        "is_admin": False,
        "active_modules": [],
        "ended_subscription": ended,  #Added By Nikhil 21Nov26 22:36 For ended state on gate
        "pending_request": {
            "request_number": pending.request_number,
            "final_amount": pending.final_amount_paise // 100,
            "created_at": pending.created_at.astimezone(ZoneInfo(settings.APP_TIMEZONE)).isoformat()  #Modified By Nikhil 21Nov26 22:44 For IST. Old: pending.created_at.isoformat()
        } if pending else None
    }

#Added By Nikhil 21Nov26 21:00 For approved user's own modules START
@router.get("/my-modules", response_model=MyModulesResponse)
async def get_my_modules(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    # Filtered on the server by the caller's own user_id, so a user can never list someone else's modules.
    #Modified By Nikhil 21Nov26 22:36 For active + expired modules with dates/days left. Old: only active rows, no dates/period
    tz = ZoneInfo(settings.APP_TIMEZONE)
    now_tz = datetime.now(tz)
    subs_res = await db.execute(
        select(UserModuleSubscription, SubscriptionRequest.billing_period)
        .join(SubscriptionRequest, SubscriptionRequest.id == UserModuleSubscription.request_id)
        .options(selectinload(UserModuleSubscription.module))
        .where(UserModuleSubscription.user_id == current_user.id)
    )
    rows = sorted(subs_res.all(), key=lambda r: r[0].module.display_order)

    def out(s, period, active):
        secs = (s.expires_at - now_tz).total_seconds()
        return MyModuleOut(
            id=str(s.module.id),
            code=s.module.code,
            name=s.module.name,
            description=s.module.description,
            icon=s.module.icon,
            status=s.module.status,
            expires_at=s.expires_at.astimezone(tz).isoformat(),
            starts_at=s.starts_at.astimezone(tz).isoformat(),
            billing_period=period,
            days_left=max(0, -(-int(secs) // 86400)) if active else 0,  # ceil to whole days
            state="active" if active else "expired",
        )

    active, expired = [], []
    for s, period in rows:
        is_active = s.is_active and s.expires_at >= now_tz
        (active if is_active else expired).append(out(s, period, is_active))
    return MyModulesResponse(modules=active, expired_modules=expired)
#Added By Nikhil 21Nov26 21:00 For approved user's own modules END
