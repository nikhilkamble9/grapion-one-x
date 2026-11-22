# //Added By Nikhil 21Nov26 23:30 For scoped role-based access (module role master + business/branch)
"""Who may do what, where.

A user's power inside a module comes from workspace_members rows: (business, branch?, role).
Permissions come from module_role_permissions. Every gym endpoint calls `require_perm`, which also
checks that the business owner's module subscription is still active (staff/members ride on it).
"""
from dataclasses import dataclass, field
from datetime import datetime
from uuid import UUID
from zoneinfo import ZoneInfo

from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.config import settings
from app.db.models import (
    ModulePermission,
    ModuleRole,
    ModuleRolePermission,
    ModuleWorkspace,
    PlatformAuditLog,
    User,
    UserModuleSubscription,
    WorkspaceMember,
)


def now_tz() -> datetime:
    return datetime.now(ZoneInfo(settings.APP_TIMEZONE))


@dataclass
class Access:
    workspace: ModuleWorkspace
    roles: list[WorkspaceMember] = field(default_factory=list)  # active assignments of the caller
    permissions: dict[UUID | None, set[str]] = field(default_factory=dict)  # branch_id (None = all) -> perms

    @property
    def is_owner(self) -> bool:
        return any(r.role.is_owner for r in self.roles)

    @property
    def best_role(self) -> ModuleRole:
        return min((r.role for r in self.roles), key=lambda r: r.rank)

    def can(self, perm: str, branch_id: UUID | None = None) -> bool:
        if perm in self.permissions.get(None, set()):
            return True  # all-branch role (owner)
        if branch_id is None:
            return any(perm in p for p in self.permissions.values())
        return perm in self.permissions.get(branch_id, set())

    def branch_ids_with(self, perm: str) -> set[UUID] | None:
        """None = every branch of the business."""
        if perm in self.permissions.get(None, set()):
            return None
        return {b for b, p in self.permissions.items() if b is not None and perm in p}


async def owner_subscription_active(db: AsyncSession, workspace: ModuleWorkspace) -> bool:
    res = await db.execute(
        select(UserModuleSubscription.id).where(
            UserModuleSubscription.user_id == workspace.owner_user_id,
            UserModuleSubscription.module_id == workspace.module_id,
            UserModuleSubscription.is_active == True,
            UserModuleSubscription.expires_at >= now_tz(),
        )
    )
    return res.first() is not None


async def load_access(db: AsyncSession, user: User, workspace_id: UUID | str) -> Access:
    try:
        wid = UUID(str(workspace_id))
    except ValueError:
        raise HTTPException(status_code=404, detail="Business not found")
    ws = (await db.execute(select(ModuleWorkspace).where(ModuleWorkspace.id == wid))).scalar_one_or_none()
    if not ws:
        raise HTTPException(status_code=404, detail="Business not found")
    res = await db.execute(
        select(WorkspaceMember)
        .options(selectinload(WorkspaceMember.role))
        .where(WorkspaceMember.workspace_id == ws.id, WorkspaceMember.user_id == user.id, WorkspaceMember.status == "active")
    )
    rows = res.scalars().all()
    if not rows:
        # Same answer as "not found" so outsiders cannot probe which businesses exist.
        raise HTTPException(status_code=404, detail="Business not found")
    if ws.status != "active" or not await owner_subscription_active(db, ws):
        raise HTTPException(status_code=403, detail="This business's account is currently inactive — please contact the owner")

    perm_res = await db.execute(
        select(ModuleRolePermission.role_id, ModulePermission.code)
        .join(ModulePermission, ModulePermission.id == ModuleRolePermission.permission_id)
        .where(ModuleRolePermission.role_id.in_([r.role_id for r in rows]))
    )
    by_role: dict[UUID, set[str]] = {}
    for role_id, code in perm_res.all():
        by_role.setdefault(role_id, set()).add(code)
    perms: dict[UUID | None, set[str]] = {}
    for r in rows:
        perms.setdefault(r.branch_id, set()).update(by_role.get(r.role_id, set()))
    return Access(workspace=ws, roles=rows, permissions=perms)


async def require_perm(db: AsyncSession, user: User, workspace_id, perm: str, branch_id: UUID | None = None) -> Access:
    acc = await load_access(db, user, workspace_id)
    if not acc.can(perm, branch_id):
        raise HTTPException(status_code=403, detail="You do not have permission for this action")
    return acc


def audit(db: AsyncSession, actor: User, action: str, entity: str, entity_id=None, workspace_id=None, detail: dict | None = None):
    db.add(PlatformAuditLog(
        actor_id=actor.id,
        actor_role=actor.role,
        action=action,
        entity=entity,
        entity_id=entity_id,
        workspace_id=workspace_id,
        detail=detail,
        created_at=now_tz(),
    ))


def mask_mobile(dial: str, mobile: str) -> str:
    return f"{dial} {'•' * max(0, len(mobile) - 4)}{mobile[-4:]}"


def mask_username(username: str) -> str:
    return username[:2] + "•" * max(2, len(username) - 2)
