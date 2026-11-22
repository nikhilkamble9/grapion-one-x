# //Added By Nikhil 18Nov26 21:29 For Authentication & 3-Step Password Recovery
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from app.db.session import get_db
from app.db.models import User
from app.core.security import hash_password, verify_password, create_access_token
from app.core.dependencies import get_current_user
from app.modules.auth.schemas import (
    UserRegisterRequest, UserLoginRequest, 
    VerifyUsernameRequest, VerifyMobileRequest, ResetPasswordRequest, TokenResponse
)

router = APIRouter(prefix="/auth", tags=["Authentication"])

@router.post("/register", status_code=status.HTTP_201_CREATED)
async def register(req: UserRegisterRequest, db: AsyncSession = Depends(get_db)):
    clean_username = req.username.strip().lower()
    clean_email = req.email.strip().lower()

    # Check username
    res = await db.execute(select(User).where(User.username_clean == clean_username))
    if res.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Username already taken")

    # Check email
    res = await db.execute(select(User).where(User.email_clean == clean_email))
    if res.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Email already registered")

    # Check mobile
    clean_mobile = req.mobile_number.strip().replace(" ", "").replace("-", "")
    res = await db.execute(select(User).where(User.dial_code == req.dial_code, User.mobile_number == clean_mobile))
    if res.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Mobile number already registered")

    # //Added By Nikhil 18Nov26 22:46 For Excluding generated columns on INSERT
    new_user = User(
        first_name=req.first_name.strip(),
        last_name=req.last_name.strip(),
        email=req.email.strip(),
        username=req.username.strip(),
        password_hash=hash_password(req.password),
        country_code=req.country_code.strip().upper(),
        dial_code=req.dial_code.strip(),
        mobile_number=clean_mobile,
        role="user"
    )
    db.add(new_user)
    await db.commit()
    await db.refresh(new_user)

    token = create_access_token({"sub": str(new_user.id), "role": new_user.role})
    return {
        "message": "User registered successfully",
        "access_token": token,
        "token_type": "bearer",
        "user": {
            "id": str(new_user.id),
            "username": new_user.username,
            "email": new_user.email,
            "first_name": new_user.first_name,
            "last_name": new_user.last_name,
            "dial_code": new_user.dial_code,
            "country_code": new_user.country_code,
            "role": new_user.role
        }
    }

@router.post("/login", response_model=TokenResponse)
async def login(req: UserLoginRequest, db: AsyncSession = Depends(get_db)):
    clean_id = req.username_or_email.strip().lower()

    # Admin shortcut / standard user check
    res = await db.execute(
        select(User).where(
            (User.username_clean == clean_id) | (User.email_clean == clean_id),
            User.is_active == True
        )
    )
    user = res.scalar_one_or_none()
    
    #Removed By Nikhil 21Nov26 22:44 For security: hard-coded admin bootstrap backdoor (admin/Admin@123) START
#    # If admin doesn't exist yet in fresh DB and inputs admin credentials, bootstrap admin
#    if not user and clean_id == "admin" and req.password == "Admin@123":
#        admin_user = User(
#            first_name="Master",
#            last_name="Admin",
#            email="admin@grapion.com",
#            email_clean="admin@grapion.com",
#            username="admin",
#            username_clean="admin",
#            password_hash=hash_password("Admin@123"),
#            country_code="IN",
#            dial_code="+91",
#            mobile_number="9876543210",
#            role="admin"
#        )
#        db.add(admin_user)
#        await db.commit()
#        await db.refresh(admin_user)
#        user = admin_user
    #Removed By Nikhil 21Nov26 22:44 For security: hard-coded admin bootstrap backdoor END

    if not user or not verify_password(req.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Invalid username or password")

    token = create_access_token({"sub": str(user.id), "role": user.role})
    return {
        "access_token": token,
        "token_type": "bearer",
        "user": {
            "id": str(user.id),
            "username": user.username,
            "email": user.email,
            "first_name": user.first_name,
            "last_name": user.last_name,
            "dial_code": user.dial_code,
            "country_code": user.country_code,
            "role": user.role
        }
    }

# --- 3-STEP PASSWORD RECOVERY (Strictly Username -> Mobile Validation -> Reset) ---

@router.post("/forgot-password/verify-username")
async def verify_username(req: VerifyUsernameRequest, db: AsyncSession = Depends(get_db)):
    clean_username = req.username.strip().lower()
    res = await db.execute(select(User).where(User.username_clean == clean_username, User.is_active == True))
    user = res.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="Username not found")
    
    # Masked mobile for hint (e.g. "+91 ******1223")
    masked_mobile = f"{user.dial_code} " + "*" * (len(user.mobile_number) - 4) + user.mobile_number[-4:]
    return {
        "status": "valid",
        "message": "Username confirmed. Please enter your registered mobile number.",
        "masked_mobile": masked_mobile
    }

@router.post("/forgot-password/verify-mobile")
async def verify_mobile(req: VerifyMobileRequest, db: AsyncSession = Depends(get_db)):
    clean_username = req.username.strip().lower()
    clean_mobile = req.mobile_number.strip().replace(" ", "").replace("-", "")

    res = await db.execute(select(User).where(User.username_clean == clean_username, User.is_active == True))
    user = res.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="Username not found")

    if user.mobile_number != clean_mobile:
        raise HTTPException(status_code=400, detail="Mobile number does not match registered records")

    return {
        "status": "matched",
        "message": "Mobile number verified. You may now set a new password."
    }

@router.post("/forgot-password/reset")
async def reset_password(req: ResetPasswordRequest, db: AsyncSession = Depends(get_db)):
    clean_username = req.username.strip().lower()
    clean_mobile = req.mobile_number.strip().replace(" ", "").replace("-", "")

    res = await db.execute(select(User).where(User.username_clean == clean_username, User.is_active == True))
    user = res.scalar_one_or_none()
    if not user or user.mobile_number != clean_mobile:
        raise HTTPException(status_code=400, detail="Invalid verification state")

    user.password_hash = hash_password(req.new_password)
    await db.commit()

    return {
        "status": "success",
        "message": "Password reset successfully. You may now sign in with your new password."
    }

@router.get("/me")
async def get_me(current_user: User = Depends(get_current_user)):
    return {
        "id": str(current_user.id),
        "username": current_user.username,
        "email": current_user.email,
        "first_name": current_user.first_name,
        "last_name": current_user.last_name,
        "dial_code": current_user.dial_code,
        "country_code": current_user.country_code,
        "role": current_user.role
    }

#Added By Nikhil 21Nov26 22:36 For profile settings (current password required) START
from datetime import datetime as _dt  # noqa: E402
from zoneinfo import ZoneInfo as _ZI  # noqa: E402
from app.core.config import settings as _settings  # noqa: E402
from app.core.countries import country_for as _country_for, COUNTRIES as _COUNTRIES  # noqa: E402
from app.modules.auth.schemas import UpdateProfileRequest, ChangePasswordRequest  # noqa: E402


@router.get("/me/profile")
async def get_my_profile(current_user: User = Depends(get_current_user)):
    return {
        "first_name": current_user.first_name,
        "last_name": current_user.last_name,
        "username": current_user.username,
        "email": current_user.email,
        "country_code": current_user.country_code,
        "dial_code": current_user.dial_code,
        "mobile_number": current_user.mobile_number,
        "role": current_user.role,
    }


@router.put("/me/profile")
async def update_my_profile(
    req: UpdateProfileRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    # Every profile change is confirmed with the current password (account takeover protection).
    if not verify_password(req.current_password, current_user.password_hash):
        raise HTTPException(status_code=400, detail="Current password is incorrect")

    known_codes = {c["code"] for c in _COUNTRIES}
    if req.country_code.upper() not in known_codes:
        raise HTTPException(status_code=400, detail="Unknown country")
    country = _country_for(req.country_code)
    if req.dial_code != country["dial"]:
        raise HTTPException(status_code=400, detail="Dial code does not match the selected country")

    clean_email = req.email.strip().lower()
    clean_mobile = req.mobile_number.strip().replace(" ", "").replace("-", "")
    if not clean_mobile.isdigit():
        raise HTTPException(status_code=400, detail="Mobile number must contain digits only")

    # Email / mobile must stay unique across other users.
    dup = await db.execute(select(User.id).where(User.email_clean == clean_email, User.id != current_user.id))
    if dup.first():
        raise HTTPException(status_code=400, detail="Email already registered")
    dup = await db.execute(
        select(User.id).where(User.dial_code == req.dial_code, User.mobile_number == clean_mobile, User.id != current_user.id)
    )
    if dup.first():
        raise HTTPException(status_code=400, detail="Mobile number already registered")

    current_user.first_name = req.first_name.strip()
    current_user.last_name = req.last_name.strip()
    current_user.email = req.email.strip()
    current_user.country_code = country["code"]
    current_user.dial_code = req.dial_code
    current_user.mobile_number = clean_mobile
    current_user.updated_at = _dt.now(_ZI(_settings.APP_TIMEZONE))
    await db.commit()
    return {"status": "success", "message": "Profile updated"}


@router.put("/me/password")
async def change_my_password(
    req: ChangePasswordRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if not verify_password(req.current_password, current_user.password_hash):
        raise HTTPException(status_code=400, detail="Current password is incorrect")
    if req.current_password == req.new_password:
        raise HTTPException(status_code=400, detail="New password must be different from the current one")
    current_user.password_hash = hash_password(req.new_password)
    current_user.must_change_password = False  #Added By Nikhil 22Nov26 08:41 For clearing the temporary-password flag
    current_user.updated_at = _dt.now(_ZI(_settings.APP_TIMEZONE))
    await db.commit()
    return {"status": "success", "message": "Password changed"}
#Added By Nikhil 21Nov26 22:36 For profile settings (current password required) END
