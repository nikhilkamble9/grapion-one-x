# //Added By Nikhil 21Nov26 23:30 For login routing entries, business setup, people search and invites
import re
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.dependencies import get_current_user
from app.db.models import (
    Module,
    ModuleRole,
    ModuleWorkspace,
    Notification,
    User,
    UserModuleSubscription,
    WorkspaceBranch,
    WorkspaceMember,
)
from app.db.session import get_db
from app.modules.workspaces.access import (
    ADMIN_ROLES,  #Added By Nikhil 22Nov26 14:41 For admin demo businesses
    audit,
    load_access,
    mask_mobile,
    mask_username,
    now_tz,
    owner_subscription_active,
)

router = APIRouter(prefix="/workspaces", tags=["Businesses & Roles"])


# ---------------- login routing ----------------

@router.get("/my-entries")
async def my_entries(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """Every place the user can open: own businesses (from subscriptions) + where they were added.

    The app routes on this: 0 entries → subscribe gate, 1 → straight in, 2+ → picker.
    """
    now = now_tz()
    entries = []

    subs = (await db.execute(
        select(UserModuleSubscription)
        .options(selectinload(UserModuleSubscription.module))
        .where(
            UserModuleSubscription.user_id == user.id,
            UserModuleSubscription.is_active == True,
            UserModuleSubscription.expires_at >= now,
        )
    )).scalars().all()
    owned = {
        w.module_id: w
        for w in (await db.execute(select(ModuleWorkspace).where(ModuleWorkspace.owner_user_id == user.id))).scalars().all()
    }
    for s in sorted(subs, key=lambda s: s.module.display_order):
        ws = owned.get(s.module_id)
        entries.append({
            "module_code": s.module.code,
            "module_name": s.module.name,
            "icon": s.module.icon,
            "workspace_id": str(ws.id) if ws else None,
            "workspace_name": ws.name if ws else None,
            "role_code": "owner",
            "role_name": "Owner",
            "branch_id": None,
            "branch_name": None,
            "needs_setup": ws is None,
            "active": True,
        })

    rows = (await db.execute(
        select(WorkspaceMember)
        .options(
            selectinload(WorkspaceMember.role),
            selectinload(WorkspaceMember.branch),
            selectinload(WorkspaceMember.workspace).selectinload(ModuleWorkspace.module),
        )
        .where(WorkspaceMember.user_id == user.id, WorkspaceMember.status.in_(("active", "invited")))
    )).scalars().all()

    invites = []
    for r in rows:
        ws = r.workspace
        if r.role.is_owner:
            continue  # owners are listed from their subscription above
        item = {
            "member_id": str(r.id),
            "module_code": ws.module.code,
            "module_name": ws.module.name,
            "icon": ws.module.icon,
            "workspace_id": str(ws.id),
            "workspace_name": ws.name,
            "role_code": r.role.code,
            "role_name": r.role.name,
            "branch_id": str(r.branch_id) if r.branch_id else None,
            "branch_name": r.branch.name if r.branch else None,
            "needs_setup": False,
        }
        if r.status == "invited":
            invites.append(item)
        else:
            item["active"] = ws.status == "active" and await owner_subscription_active(db, ws)
            entries.append(item)

    return {"entries": entries, "invites": invites, "must_change_password": bool(user.must_change_password)}


#Added By Nikhil 22Nov26 14:41 For admin "View as Owner / Member": the admin's own demo business START
@router.get("/demo")
async def my_demo(module_code: str = Query(..., max_length=50), user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """Admins only. The admin's own business for this module (an entry like /my-entries), or needs_setup."""
    if user.role not in ADMIN_ROLES:
        raise HTTPException(status_code=403, detail="Admin privileges required")
    module = (await db.execute(select(Module).where(Module.code == module_code))).scalar_one_or_none()
    if not module:
        raise HTTPException(status_code=404, detail="Module not found")
    ws = (await db.execute(select(ModuleWorkspace).where(
        ModuleWorkspace.module_id == module.id, ModuleWorkspace.owner_user_id == user.id))).scalar_one_or_none()
    return {
        "module_code": module.code, "module_name": module.name, "icon": module.icon,
        "workspace_id": str(ws.id) if ws else None, "workspace_name": ws.name if ws else None,
        "role_code": "owner", "role_name": "Owner", "branch_id": None, "branch_name": None,
        "needs_setup": ws is None, "active": True,
    }
#Added By Nikhil 22Nov26 14:41 For admin "View as Owner / Member": the admin's own demo business END


# ---------------- business setup (owner, first time) ----------------

class SetupRequest(BaseModel):
    module_code: str = Field(..., max_length=50)
    business_name: str = Field(..., min_length=2, max_length=120)
    branch_name: str = Field(..., min_length=2, max_length=120)
    address: str | None = Field(None, max_length=500)
    phone: str | None = Field(None, max_length=20)


def _short_code(name: str) -> str:
    words = re.findall(r"[A-Za-z0-9]+", name)
    code = "".join(w[0] for w in words).upper()[:4] or "BIZ"
    return code if len(code) >= 2 else (words[0][:3].upper() if words else "BIZ")


@router.post("", status_code=201)
async def create_workspace(req: SetupRequest, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    module = (await db.execute(select(Module).where(Module.code == req.module_code))).scalar_one_or_none()
    if not module:
        raise HTTPException(status_code=404, detail="Module not found")
    now = now_tz()
    sub = (await db.execute(select(UserModuleSubscription.id).where(
        UserModuleSubscription.user_id == user.id,
        UserModuleSubscription.module_id == module.id,
        UserModuleSubscription.is_active == True,
        UserModuleSubscription.expires_at >= now,
    ))).first()
    #Modified By Nikhil 22Nov26 14:41 For admins creating their own demo business without a subscription. Old: if not sub:
    if not sub and user.role not in ADMIN_ROLES:
        raise HTTPException(status_code=403, detail="An active subscription to this module is required")
    if (await db.execute(select(ModuleWorkspace.id).where(
        ModuleWorkspace.module_id == module.id, ModuleWorkspace.owner_user_id == user.id
    ))).first():
        raise HTTPException(status_code=400, detail="Your business is already set up")
    owner_role = (await db.execute(select(ModuleRole).where(
        ModuleRole.module_id == module.id, ModuleRole.is_owner == True
    ))).scalar_one_or_none()
    if not owner_role:
        raise HTTPException(status_code=400, detail="This module has no owner role configured yet")

    ws = ModuleWorkspace(module_id=module.id, owner_user_id=user.id, name=req.business_name.strip(),
                         short_code=_short_code(req.business_name), status="active",
                         created_at=now, updated_at=now, created_by=user.id, modified_by=user.id)
    db.add(ws)
    await db.flush()
    branch = WorkspaceBranch(workspace_id=ws.id, name=req.branch_name.strip(), address=req.address, phone=req.phone,
                             status="active", created_at=now, updated_at=now, created_by=user.id, modified_by=user.id)
    db.add(branch)
    await db.flush()
    db.add(WorkspaceMember(workspace_id=ws.id, branch_id=None, user_id=user.id, role_id=owner_role.id, status="active",
                           invited_by=user.id, responded_at=now, created_at=now, updated_at=now,
                           created_by=user.id, modified_by=user.id))
    if module.code == "gym":
        await init_gym_branch(db, branch.id, user.id)
    audit(db, user, "workspace.created", "module_workspaces", ws.id, ws.id, {"module": module.code, "branch": branch.name})
    await db.commit()
    return {"workspace_id": str(ws.id), "branch_id": str(branch.id)}


async def init_gym_branch(db: AsyncSession, branch_id, user_id):
    """Default branch settings + timings (Mon–Sat 06:00–22:00, Sunday weekly off)."""
    #Modified By Nikhil 22Nov26 08:35 For new branches using the platform default reminder days. Old: INSERT (branch_id, created_by, modified_by) VALUES (:b, :u, :u)
    from app.core.platform_settings import default_reminder_days
    await db.execute(text(
        "INSERT INTO grapion_one_x.gym_branch_settings (branch_id, reminder_lead_days, created_by, modified_by) VALUES (:b, :d, :u, :u) "
        "ON CONFLICT (branch_id) DO NOTHING"), {"b": branch_id, "d": await default_reminder_days(db), "u": user_id})
    for wd in range(1, 8):
        await db.execute(text(
            "INSERT INTO grapion_one_x.gym_branch_hours (branch_id, weekday, is_closed, open_time, close_time, created_by, modified_by) "
            "VALUES (:b, :wd, :closed, CASE WHEN :closed THEN NULL ELSE TIME '06:00' END, CASE WHEN :closed THEN NULL ELSE TIME '22:00' END, :u, :u) "
            "ON CONFLICT (branch_id, weekday) DO NOTHING"), {"b": branch_id, "wd": wd, "closed": wd == 7, "u": user_id})


# ---------------- people search (exact match only, masked) ----------------

def _perm(module_code: str, name: str) -> str:
    return f"{module_code}.{name}"


@router.get("/{workspace_id}/people/search")
async def search_people(
    workspace_id: str,
    username: str | None = Query(None, max_length=50),
    mobile: str | None = Query(None, max_length=20),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    acc = await load_access(db, user, workspace_id)
    mod = (await db.execute(select(Module).where(Module.id == acc.workspace.module_id))).scalar_one()
    if not (acc.can(_perm(mod.code, "staff.manage")) or acc.can(_perm(mod.code, "members.edit"))):
        raise HTTPException(status_code=403, detail="You do not have permission for this action")
    if bool(username) == bool(mobile):
        raise HTTPException(status_code=400, detail="Search by exact username OR exact mobile number")

    q = select(User).where(User.is_active == True, User.id != user.id)
    if username:
        q = q.where(User.username_clean == username.strip().lower())
    else:
        q = q.where(User.mobile_number == re.sub(r"[\s-]", "", mobile))
    found = (await db.execute(q.limit(5))).scalars().all()
    # Privacy: name + the identifier they typed; the other identifier masked. No browsing.
    return {"results": [{
        "user_id": str(u.id),
        "name": f"{u.first_name} {u.last_name}",
        "username": u.username if username else mask_username(u.username),
        "mobile": mask_mobile(u.dial_code, u.mobile_number) if username else f"{u.dial_code} {u.mobile_number}",
    } for u in found]}


# ---------------- invites ----------------

class InviteRequest(BaseModel):
    user_id: str
    role_code: str = Field(..., max_length=30)
    branch_id: str


@router.post("/{workspace_id}/invites", status_code=201)
async def invite(workspace_id: str, req: InviteRequest, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    acc = await load_access(db, user, workspace_id)
    ws = acc.workspace
    mod = (await db.execute(select(Module).where(Module.id == ws.module_id))).scalar_one()
    try:
        branch_uuid, invitee_uuid = UUID(req.branch_id), UUID(req.user_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid request")
    branch = (await db.execute(select(WorkspaceBranch).where(
        WorkspaceBranch.id == branch_uuid, WorkspaceBranch.workspace_id == ws.id, WorkspaceBranch.status == "active"
    ))).scalar_one_or_none()
    if not branch:
        raise HTTPException(status_code=404, detail="Branch not found")
    role = (await db.execute(select(ModuleRole).where(
        ModuleRole.module_id == ws.module_id, ModuleRole.code == req.role_code, ModuleRole.is_active == True
    ))).scalar_one_or_none()
    if not role or role.is_owner:
        raise HTTPException(status_code=400, detail="Invalid role")
    needed = _perm(mod.code, "staff.manage") if role.is_staff else _perm(mod.code, "members.edit")
    if not acc.can(needed, branch.id):
        raise HTTPException(status_code=403, detail="You do not have permission for this action")
    if not acc.is_owner and role.rank <= acc.best_role.rank:
        raise HTTPException(status_code=403, detail="You can only add roles below your own")  # e.g. manager cannot add managers
    invitee = (await db.execute(select(User).where(User.id == invitee_uuid, User.is_active == True))).scalar_one_or_none()
    if not invitee or invitee.id == ws.owner_user_id:
        raise HTTPException(status_code=404, detail="User not found")
    dup = (await db.execute(select(WorkspaceMember.id).where(
        WorkspaceMember.workspace_id == ws.id, WorkspaceMember.user_id == invitee.id, WorkspaceMember.role_id == role.id,
        WorkspaceMember.branch_id == branch.id, WorkspaceMember.status.in_(("invited", "active")),
    ))).first()
    if dup:
        raise HTTPException(status_code=400, detail="This person already has (or was invited to) this role here")

    now = now_tz()
    m = WorkspaceMember(workspace_id=ws.id, branch_id=branch.id, user_id=invitee.id, role_id=role.id, status="invited",
                        invited_by=user.id, created_at=now, updated_at=now, created_by=user.id, modified_by=user.id)
    db.add(m)
    await db.flush()
    db.add(Notification(user_id=invitee.id, workspace_id=ws.id, branch_id=branch.id, category="invite",
                        title=f"{ws.name} wants to add you",
                        message=f"{ws.name} ({branch.name}) invited you as {role.name}. Open the app to accept or decline.",
                        dedupe_key=f"invite:{m.id}", created_at=now, created_by=user.id))
    audit(db, user, "member.invited", "workspace_members", m.id, ws.id, {"role": role.code, "branch": branch.name})
    await db.commit()
    return {"member_id": str(m.id), "status": "invited"}


class RespondRequest(BaseModel):
    accept: bool


@router.post("/invites/{member_id}/respond")
async def respond(member_id: str, req: RespondRequest, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    try:
        mid = UUID(member_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="Invite not found")
    m = (await db.execute(select(WorkspaceMember).where(
        WorkspaceMember.id == mid, WorkspaceMember.user_id == user.id  # only the invited person
    ))).scalar_one_or_none()
    if not m or m.status != "invited":
        raise HTTPException(status_code=404, detail="Invite not found")
    now = now_tz()
    m.status = "active" if req.accept else "declined"
    m.responded_at = now
    m.updated_at = now
    m.modified_by = user.id
    audit(db, user, "member.accepted" if req.accept else "member.declined", "workspace_members", m.id, m.workspace_id)
    await db.commit()
    return {"status": m.status}
