# //Added By Nikhil 18Nov26 21:33 For Admin Approval & Dashboard
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo
import uuid
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from sqlalchemy.orm import selectinload
from app.db.session import get_db
from app.db.models import User, SubscriptionRequest, SubscriptionRequestItem, SubscriptionPayment, UserModuleSubscription
from app.core.dependencies import require_admin
from app.core.config import settings
from app.modules.admin.schemas import ApprovePaymentRequest, RejectRequest
#Added By Nikhil 21Nov26 22:44 For cancellations in admin START
from app.db.models import SubscriptionCancellation
from app.modules.admin.schemas import ApproveCancellationRequest, RejectCancellationRequest
from app.modules.subscriptions.cancellations import log_event, open_cancellation_for_request, serialize
#Added By Nikhil 21Nov26 22:44 For cancellations in admin END

router = APIRouter(prefix="/admin", tags=["Admin Dashboard"])

@router.get("/dashboard")
async def get_dashboard(
    admin: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db)
):
    # 1. Fetch pending requests with user and module items
    res = await db.execute(
        select(SubscriptionRequest)
        .options(
            selectinload(SubscriptionRequest.user),
            selectinload(SubscriptionRequest.items).selectinload(SubscriptionRequestItem.module)
        )
        .where(SubscriptionRequest.status == "pending")
        .order_by(SubscriptionRequest.created_at.desc())
    )
    pending_list = res.scalars().all()

    # 2. Compute metrics
    total_volume_paise = sum(r.final_amount_paise for r in pending_list)

    #Added By Nikhil 21Nov26 22:44 For cancellation banner on pending requests START
    open_res = await db.execute(
        select(SubscriptionCancellation).where(
            SubscriptionCancellation.request_id.in_([r.id for r in pending_list] or [uuid.uuid4()]),
            SubscriptionCancellation.cancel_type == "pending_request",
            SubscriptionCancellation.status == "requested",
        )
    )
    open_by_request = {c.request_id: c for c in open_res.scalars().all()}
    #Added By Nikhil 21Nov26 22:44 For cancellation banner on pending requests END

    requests_out = []
    for r in pending_list:
        module_names = [it.module.name for it in r.items]
        requests_out.append({
            "id": str(r.id),
            "request_number": r.request_number,
            "user_id": str(r.user_id),
            "user_name": f"{r.user.first_name} {r.user.last_name}",
            "mobile_number": f"{r.user.dial_code} {r.user.mobile_number}",
            "country_code": r.user.country_code,
            "billing_period": r.billing_period,
            "modules": module_names,
            "base_amount": r.base_amount_paise // 100,
            "final_amount": r.final_amount_paise // 100,
            "created_at": r.created_at.astimezone(ZoneInfo(settings.APP_TIMEZONE)).isoformat(),  #Modified By Nikhil 21Nov26 22:44 For IST time on cards. Old: r.created_at.isoformat()
            "cancellation": serialize(open_by_request[r.id]) if r.id in open_by_request else None,  #Added By Nikhil 21Nov26 22:44 For cancellation banner
        })

    return {
        "metrics": {
            "pending_count": len(pending_list),
            "pending_volume_rupees": total_volume_paise // 100
        },
        "pending_requests": requests_out
    }

@router.post("/requests/{request_id}/approve")
async def approve_request(
    request_id: str,
    req: ApprovePaymentRequest,
    admin: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db)
):
    req_uuid = uuid.UUID(request_id)
    res = await db.execute(
        select(SubscriptionRequest)
        .options(selectinload(SubscriptionRequest.items))
        .where(SubscriptionRequest.id == req_uuid)
    )
    sub_req = res.scalar_one_or_none()
    if not sub_req or sub_req.status != "pending":
        raise HTTPException(status_code=404, detail="Pending subscription request not found")

    now_tz = datetime.now(ZoneInfo(settings.APP_TIMEZONE))

    # Calculate expiration based on period
    period_days = {
        "weekly": 7,
        "monthly": 30,
        "quarterly": 90,
        "yearly": 365
    }.get(sub_req.billing_period, 30)
    expires_at = now_tz + timedelta(days=period_days)

    # 1. Record payment transaction
    payment = SubscriptionPayment(
        request_id=sub_req.id,
        payment_method=req.payment_method,
        amount_paise=sub_req.final_amount_paise,
        currency=sub_req.currency,
        payer_upi_id=req.payer_upi_id,
        utr_last_digits=req.utr_last_digits,
        cardholder_name=req.cardholder_name,
        card_last_four=req.card_last_four,
        recorded_by=admin.id,
        verified_at=now_tz
    )
    db.add(payment)

    # 2. Grant module subscription entitlements
    for item in sub_req.items:
        # Check if already exists, else insert
        ex_sub = await db.execute(
            select(UserModuleSubscription).where(
                UserModuleSubscription.user_id == sub_req.user_id,
                UserModuleSubscription.module_id == item.module_id
            )
        )
        existing = ex_sub.scalar_one_or_none()
        if existing:
            #Added By Nikhil 22Nov26 10:47 For renewal extends from the current end date (no lost days) START
            still_running = existing.is_active and existing.expires_at > now_tz
            covers_from = existing.expires_at if still_running else now_tz
            item.covers_from = covers_from
            item.covers_to = covers_from + timedelta(days=period_days)
            if not still_running:
                existing.starts_at = now_tz
            #Added By Nikhil 22Nov26 10:47 For renewal extends from the current end date (no lost days) END
            #Removed By Nikhil 22Nov26 10:47 For renewal extends instead of reset: existing.starts_at = now_tz  #Added By Nikhil 21Nov26 22:36 For renewal starting a fresh period
            existing.request_id = sub_req.id  #Added By Nikhil 21Nov26 22:36 For renewal linked to the new request
            existing.expires_at = item.covers_to  #Modified By Nikhil 22Nov26 10:47 For renewal extends. Old: existing.expires_at = expires_at
            existing.is_active = True
        else:
            item.covers_from, item.covers_to = now_tz, expires_at  #Added By Nikhil 22Nov26 10:47 For period this payment covers
            db.add(UserModuleSubscription(
                user_id=sub_req.user_id,
                module_id=item.module_id,
                request_id=sub_req.id,
                starts_at=now_tz,
                expires_at=expires_at,
                is_active=True
            ))

    # 3. Mark request approved
    sub_req.status = "approved"
    #Added By Nikhil 21Nov26 22:44 For approve = activate anyway (agreed in back office) START
    open_c = await open_cancellation_for_request(db, sub_req.id)
    if open_c:
        open_c.status = "rejected"
        open_c.review_note = "Request approved by admin (settled in back office)"
        open_c.reviewed_by = admin.id
        open_c.reviewed_at = now_tz
        open_c.updated_at = now_tz
        open_c.modified_by = admin.id
        log_event(db, open_c, "rejected", admin, open_c.review_note, now_tz)
    #Added By Nikhil 21Nov26 22:44 For approve = activate anyway (agreed in back office) END
    sub_req.reviewed_by = admin.id
    sub_req.reviewed_at = now_tz

    await db.commit()
    return {"status": "success", "message": f"Request {sub_req.request_number} approved and modules activated"}

@router.post("/requests/{request_id}/reject")
async def reject_request(
    request_id: str,
    req: RejectRequest,
    admin: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db)
):
    req_uuid = uuid.UUID(request_id)
    res = await db.execute(select(SubscriptionRequest).where(SubscriptionRequest.id == req_uuid))
    sub_req = res.scalar_one_or_none()
    if not sub_req or sub_req.status != "pending":
        raise HTTPException(status_code=404, detail="Pending subscription request not found")

    now_tz = datetime.now(ZoneInfo(settings.APP_TIMEZONE))
    sub_req.status = "rejected"
    #Added By Nikhil 21Nov26 22:44 For reject = cancellation honoured START
    open_c = await open_cancellation_for_request(db, sub_req.id)
    if open_c:
        open_c.status = "approved"
        open_c.review_note = req.reason
        open_c.reviewed_by = admin.id
        open_c.reviewed_at = now_tz
        open_c.updated_at = now_tz
        open_c.modified_by = admin.id
        log_event(db, open_c, "approved", admin, req.reason, now_tz)
    #Added By Nikhil 21Nov26 22:44 For reject = cancellation honoured END
    sub_req.rejection_reason = req.reason
    sub_req.reviewed_by = admin.id
    sub_req.reviewed_at = now_tz

    await db.commit()
    return {"status": "rejected", "message": f"Request {sub_req.request_number} rejected"}


#Added By Nikhil 21Nov26 22:44 For active-module cancellations (refund) START
@router.get("/cancellations")
async def list_cancellations(admin: User = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    res = await db.execute(
        select(SubscriptionCancellation)
        .options(
            selectinload(SubscriptionCancellation.user),
            selectinload(SubscriptionCancellation.module_subscription).selectinload(UserModuleSubscription.module),
        )
        .where(SubscriptionCancellation.cancel_type == "active_module", SubscriptionCancellation.status == "requested")
        .order_by(SubscriptionCancellation.created_at.desc())
    )
    out = []
    for c in res.scalars().all():
        item = serialize(c, c.module_subscription.module.name if c.module_subscription else None)
        item["user_name"] = f"{c.user.first_name} {c.user.last_name}"
        item["mobile_number"] = f"{c.user.dial_code} {c.user.mobile_number}"
        item["expires_at"] = c.module_subscription.expires_at.astimezone(ZoneInfo(settings.APP_TIMEZONE)).isoformat() if c.module_subscription else None
        out.append(item)
    return {"cancellations": out}


async def _get_open_module_cancellation(db: AsyncSession, cancellation_id: str) -> SubscriptionCancellation:
    try:
        cid = uuid.UUID(cancellation_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="Cancellation not found")
    res = await db.execute(
        select(SubscriptionCancellation)
        .options(selectinload(SubscriptionCancellation.module_subscription))
        .where(SubscriptionCancellation.id == cid, SubscriptionCancellation.cancel_type == "active_module")
    )
    c = res.scalar_one_or_none()
    if not c or c.status != "requested":
        raise HTTPException(status_code=404, detail="Open cancellation not found (it may have been withdrawn)")
    return c


@router.post("/cancellations/{cancellation_id}/approve")
async def approve_cancellation(
    cancellation_id: str,
    req: ApproveCancellationRequest,
    admin: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    c = await _get_open_module_cancellation(db, cancellation_id)
    now_tz = datetime.now(ZoneInfo(settings.APP_TIMEZONE))
    c.status = "approved"
    c.refund_method = req.refund_method
    c.refund_reference = req.refund_reference
    c.review_note = req.note
    c.reviewed_by = admin.id
    c.reviewed_at = now_tz
    c.updated_at = now_tz
    c.modified_by = admin.id
    #Added By Nikhil 22Nov26 10:47 For cancelling a renewal that has not started: back to the previous end date START
    cancelled_item = None
    if c.module_subscription:
        cancelled_item = (await db.execute(
            select(SubscriptionRequestItem).where(
                SubscriptionRequestItem.request_id == c.request_id,
                SubscriptionRequestItem.module_id == c.module_subscription.module_id,
            )
        )).scalar_one_or_none()
    if c.module_subscription and cancelled_item and cancelled_item.covers_from and cancelled_item.covers_from > now_tz:
        ms = c.module_subscription
        ms.expires_at = cancelled_item.covers_from  # earlier paid period keeps running
        prev = (await db.execute(
            select(SubscriptionRequestItem.request_id)
            .join(SubscriptionRequest, SubscriptionRequest.id == SubscriptionRequestItem.request_id)
            .where(
                SubscriptionRequest.user_id == c.user_id,
                SubscriptionRequest.status == "approved",
                SubscriptionRequestItem.module_id == ms.module_id,
                SubscriptionRequestItem.request_id != c.request_id,
            )
            .order_by(SubscriptionRequestItem.covers_to.desc().nulls_last(), SubscriptionRequest.reviewed_at.desc())
            .limit(1)
        )).scalar_one_or_none()
        if prev:
            ms.request_id = prev
        ms.modified_by = admin.id
    elif c.module_subscription:
    #Added By Nikhil 22Nov26 10:47 For cancelling a renewal that has not started: back to the previous end date END
    #Modified By Nikhil 22Nov26 10:47 For renewal-aware cancel. Old: if c.module_subscription:
        c.module_subscription.is_active = False  # access ends now; refund settled in back office
        c.module_subscription.expires_at = now_tz
        c.module_subscription.modified_by = admin.id
    log_event(db, c, "approved", admin, req.note or f"Refund via {req.refund_method}", now_tz)
    await db.commit()
    return {"status": "approved", "message": f"Cancellation {c.cancellation_number} approved"}


@router.post("/cancellations/{cancellation_id}/reject")
async def reject_cancellation(
    cancellation_id: str,
    req: RejectCancellationRequest,
    admin: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    c = await _get_open_module_cancellation(db, cancellation_id)
    now_tz = datetime.now(ZoneInfo(settings.APP_TIMEZONE))
    c.status = "rejected"
    c.review_note = req.note
    c.reviewed_by = admin.id
    c.reviewed_at = now_tz
    c.updated_at = now_tz
    c.modified_by = admin.id
    log_event(db, c, "rejected", admin, req.note, now_tz)
    await db.commit()
    return {"status": "rejected", "message": f"Cancellation {c.cancellation_number} rejected — subscription continues to its end date"}
#Added By Nikhil 21Nov26 22:44 For active-module cancellations (refund) END
