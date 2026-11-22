# //Added By Nikhil 18Nov26 21:26 For SQLAlchemy Models
import uuid
from datetime import datetime
from sqlalchemy import (
    Column, String, Boolean, DateTime, ForeignKey, 
    BigInteger, Numeric, Integer, Text, UniqueConstraint, Index
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from app.db.session import Base

class User(Base):
    __tablename__ = "users"
    __table_args__ = {"schema": "grapion_one_x"}

    # //Added By Nikhil 18Nov26 22:46 For Computed Generated Columns
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    username = Column(String(50), nullable=False)
    username_clean = Column(String(50), server_default="lower(username)", nullable=False)
    email = Column(String(255), nullable=False)
    email_clean = Column(String(255), server_default="lower(email)", nullable=False)
    password_hash = Column(String(255), nullable=False)
    first_name = Column(String(100), nullable=False)
    last_name = Column(String(100), nullable=False)
    country_code = Column(String(10), nullable=False, default="IN")
    dial_code = Column(String(10), nullable=False, default="+91")
    mobile_number = Column(String(20), nullable=False)
    role = Column(String(20), nullable=False, default="user")
    is_active = Column(Boolean, nullable=False, default=True)
    must_change_password = Column(Boolean, nullable=False, default=False)  #Added By Nikhil 21Nov26 23:30 For temporary passwords
    created_at = Column(DateTime(timezone=True), default=datetime.utcnow)
    updated_at = Column(DateTime(timezone=True), default=datetime.utcnow)

    requests = relationship("SubscriptionRequest", back_populates="user", cascade="all, delete-orphan", foreign_keys="SubscriptionRequest.user_id")
    subscriptions = relationship("UserModuleSubscription", back_populates="user", cascade="all, delete-orphan")


class Module(Base):
    __tablename__ = "modules"
    __table_args__ = {"schema": "grapion_one_x"}

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    code = Column(String(50), unique=True, nullable=False)
    name = Column(String(100), nullable=False)
    description = Column(Text)
    icon = Column(String(50), default="🏋️")
    status = Column(String(30), nullable=False, default="active")
    display_order = Column(Integer, nullable=False, default=1)
    created_at = Column(DateTime(timezone=True), default=datetime.utcnow)

    prices = relationship("ModulePrice", back_populates="module", cascade="all, delete-orphan")


class ModulePrice(Base):
    __tablename__ = "module_prices"
    __table_args__ = (
        UniqueConstraint("module_id", "period", name="uq_module_period"),
        {"schema": "grapion_one_x"}
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    module_id = Column(UUID(as_uuid=True), ForeignKey("grapion_one_x.modules.id", ondelete="CASCADE"), nullable=False)
    period = Column(String(20), nullable=False) # weekly, monthly, quarterly, yearly
    price_paise = Column(BigInteger, nullable=False)
    currency = Column(String(5), nullable=False, default="INR")
    is_active = Column(Boolean, default=True, nullable=False)

    module = relationship("Module", back_populates="prices")


class Discount(Base):
    __tablename__ = "discounts"
    __table_args__ = {"schema": "grapion_one_x"}

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    title = Column(String(150), nullable=False)
    percent_off = Column(Numeric(5, 2), nullable=False)
    #Added By Nikhil 21Nov26 22:44 For per-period discount (NULL = use percent_off) START
    weekly_percent_off = Column(Numeric(5, 2))
    monthly_percent_off = Column(Numeric(5, 2))
    quarterly_percent_off = Column(Numeric(5, 2))
    yearly_percent_off = Column(Numeric(5, 2))

    def percent_for(self, period: str) -> float:
        v = getattr(self, f"{period}_percent_off", None)
        return float(v if v is not None else self.percent_off)
    #Added By Nikhil 21Nov26 22:44 For per-period discount END
    start_date = Column(DateTime(timezone=True), nullable=False)
    end_date = Column(DateTime(timezone=True), nullable=False)
    is_active = Column(Boolean, default=True, nullable=False)
    created_at = Column(DateTime(timezone=True), default=datetime.utcnow)


class SubscriptionRequest(Base):
    __tablename__ = "subscription_requests"
    __table_args__ = {"schema": "grapion_one_x"}

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    request_number = Column(String(20), unique=True, nullable=False)
    user_id = Column(UUID(as_uuid=True), ForeignKey("grapion_one_x.users.id", ondelete="CASCADE"), nullable=False)
    billing_period = Column(String(20), nullable=False)
    currency = Column(String(5), nullable=False, default="INR")
    base_amount_paise = Column(BigInteger, nullable=False)
    discount_amount_paise = Column(BigInteger, default=0, nullable=False)
    final_amount_paise = Column(BigInteger, nullable=False)
    applied_discount_id = Column(UUID(as_uuid=True), ForeignKey("grapion_one_x.discounts.id"))
    status = Column(String(20), default="pending", nullable=False) # pending, approved, rejected
    rejection_reason = Column(Text)
    reviewed_by = Column(UUID(as_uuid=True), ForeignKey("grapion_one_x.users.id"))
    reviewed_at = Column(DateTime(timezone=True))
    created_at = Column(DateTime(timezone=True), default=datetime.utcnow)

    user = relationship("User", back_populates="requests", foreign_keys=[user_id])
    items = relationship("SubscriptionRequestItem", back_populates="request", cascade="all, delete-orphan")
    payment = relationship("SubscriptionPayment", back_populates="request", uselist=False, cascade="all, delete-orphan")


class SubscriptionRequestItem(Base):
    __tablename__ = "subscription_request_items"
    __table_args__ = {"schema": "grapion_one_x"}

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    request_id = Column(UUID(as_uuid=True), ForeignKey("grapion_one_x.subscription_requests.id", ondelete="CASCADE"), nullable=False)
    module_id = Column(UUID(as_uuid=True), ForeignKey("grapion_one_x.modules.id"), nullable=False)
    price_paise = Column(BigInteger, nullable=False)
    covers_from = Column(DateTime(timezone=True), nullable=True)  #Added By Nikhil 22Nov26 10:47 For period this payment covers (renewals extend)
    covers_to = Column(DateTime(timezone=True), nullable=True)  #Added By Nikhil 22Nov26 10:47 For period this payment covers (renewals extend)

    request = relationship("SubscriptionRequest", back_populates="items")
    module = relationship("Module")


class SubscriptionPayment(Base):
    __tablename__ = "subscription_payments"
    __table_args__ = {"schema": "grapion_one_x"}

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    request_id = Column(UUID(as_uuid=True), ForeignKey("grapion_one_x.subscription_requests.id", ondelete="CASCADE"), nullable=False)
    payment_method = Column(String(20), nullable=False) # cash, upi, card
    amount_paise = Column(BigInteger, nullable=False)
    currency = Column(String(5), default="INR", nullable=False)
    payer_upi_id = Column(String(100))
    utr_last_digits = Column(String(20))
    cardholder_name = Column(String(100))
    card_last_four = Column(String(4))
    recorded_by = Column(UUID(as_uuid=True), ForeignKey("grapion_one_x.users.id"), nullable=False)
    verified_at = Column(DateTime(timezone=True), default=datetime.utcnow)

    request = relationship("SubscriptionRequest", back_populates="payment")


class UserModuleSubscription(Base):
    __tablename__ = "user_module_subscriptions"
    __table_args__ = (
        UniqueConstraint("user_id", "module_id", name="uq_user_module_active"),
        {"schema": "grapion_one_x"}
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("grapion_one_x.users.id", ondelete="CASCADE"), nullable=False)
    module_id = Column(UUID(as_uuid=True), ForeignKey("grapion_one_x.modules.id"), nullable=False)
    request_id = Column(UUID(as_uuid=True), ForeignKey("grapion_one_x.subscription_requests.id"), nullable=False)
    starts_at = Column(DateTime(timezone=True), default=datetime.utcnow, nullable=False)
    expires_at = Column(DateTime(timezone=True), nullable=False)
    is_active = Column(Boolean, default=True, nullable=False)

    user = relationship("User", back_populates="subscriptions")
    module = relationship("Module")


#Added By Nikhil 21Nov26 22:44 For subscription cancellation + history START
class SubscriptionCancellation(Base):
    __tablename__ = "subscription_cancellations"
    __table_args__ = {"schema": "grapion_one_x"}

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    cancellation_number = Column(String(20), unique=True, nullable=False)
    user_id = Column(UUID(as_uuid=True), ForeignKey("grapion_one_x.users.id"), nullable=False)
    request_id = Column(UUID(as_uuid=True), ForeignKey("grapion_one_x.subscription_requests.id"), nullable=False)
    user_module_subscription_id = Column(UUID(as_uuid=True), ForeignKey("grapion_one_x.user_module_subscriptions.id"))
    cancel_type = Column(String(20), nullable=False)  # pending_request | active_module
    reason = Column(Text, nullable=False)
    status = Column(String(20), nullable=False, default="requested")  # requested | withdrawn | approved | rejected
    total_days = Column(Integer)
    used_days = Column(Integer)
    paid_amount_paise = Column(BigInteger)
    refund_amount_paise = Column(BigInteger)
    refund_method = Column(String(20))
    refund_reference = Column(String(50))
    review_note = Column(Text)
    reviewed_by = Column(UUID(as_uuid=True), ForeignKey("grapion_one_x.users.id"))
    reviewed_at = Column(DateTime(timezone=True))
    created_at = Column(DateTime(timezone=True))
    updated_at = Column(DateTime(timezone=True))
    created_by = Column(UUID(as_uuid=True))
    modified_by = Column(UUID(as_uuid=True))

    user = relationship("User", foreign_keys=[user_id])
    request = relationship("SubscriptionRequest")
    module_subscription = relationship("UserModuleSubscription")


class SubscriptionCancellationEvent(Base):
    __tablename__ = "subscription_cancellation_events"
    __table_args__ = {"schema": "grapion_one_x"}

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    cancellation_id = Column(UUID(as_uuid=True), ForeignKey("grapion_one_x.subscription_cancellations.id"), nullable=False)
    event = Column(String(20), nullable=False)  # requested | withdrawn | approved | rejected
    actor_id = Column(UUID(as_uuid=True), ForeignKey("grapion_one_x.users.id"), nullable=False)
    actor_role = Column(String(20), nullable=False)
    note = Column(Text)
    created_at = Column(DateTime(timezone=True))
    created_by = Column(UUID(as_uuid=True))
#Added By Nikhil 21Nov26 22:44 For subscription cancellation + history END


#Added By Nikhil 21Nov26 23:30 For module role master, businesses, branches, notifications, audit START
from sqlalchemy.dialects.postgresql import JSONB  # noqa: E402


class ModuleRole(Base):
    __tablename__ = "module_roles"
    __table_args__ = {"schema": "grapion_one_x"}
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    module_id = Column(UUID(as_uuid=True), ForeignKey("grapion_one_x.modules.id"), nullable=False)
    code = Column(String(30), nullable=False)
    name = Column(String(60), nullable=False)
    rank = Column(Integer, nullable=False)
    is_owner = Column(Boolean, nullable=False, default=False)
    is_staff = Column(Boolean, nullable=False, default=False)
    is_active = Column(Boolean, nullable=False, default=True)
    module = relationship("Module")


class ModulePermission(Base):
    __tablename__ = "module_permissions"
    __table_args__ = {"schema": "grapion_one_x"}
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    module_id = Column(UUID(as_uuid=True), ForeignKey("grapion_one_x.modules.id"), nullable=False)
    code = Column(String(60), nullable=False)
    name = Column(String(120), nullable=False)


class ModuleRolePermission(Base):
    __tablename__ = "module_role_permissions"
    __table_args__ = {"schema": "grapion_one_x"}
    role_id = Column(UUID(as_uuid=True), ForeignKey("grapion_one_x.module_roles.id"), primary_key=True)
    permission_id = Column(UUID(as_uuid=True), ForeignKey("grapion_one_x.module_permissions.id"), primary_key=True)


class ModuleWorkspace(Base):
    __tablename__ = "module_workspaces"
    __table_args__ = {"schema": "grapion_one_x"}
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    module_id = Column(UUID(as_uuid=True), ForeignKey("grapion_one_x.modules.id"), nullable=False)
    owner_user_id = Column(UUID(as_uuid=True), ForeignKey("grapion_one_x.users.id"), nullable=False)
    name = Column(String(120), nullable=False)
    short_code = Column(String(6), nullable=False)
    status = Column(String(20), nullable=False, default="active")
    created_at = Column(DateTime(timezone=True))
    updated_at = Column(DateTime(timezone=True))
    created_by = Column(UUID(as_uuid=True))
    modified_by = Column(UUID(as_uuid=True))
    module = relationship("Module")
    owner = relationship("User", foreign_keys=[owner_user_id])


class WorkspaceBranch(Base):
    __tablename__ = "workspace_branches"
    __table_args__ = {"schema": "grapion_one_x"}
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    workspace_id = Column(UUID(as_uuid=True), ForeignKey("grapion_one_x.module_workspaces.id"), nullable=False)
    name = Column(String(120), nullable=False)
    address = Column(Text)
    phone = Column(String(20))
    status = Column(String(20), nullable=False, default="active")
    created_at = Column(DateTime(timezone=True))
    updated_at = Column(DateTime(timezone=True))
    created_by = Column(UUID(as_uuid=True))
    modified_by = Column(UUID(as_uuid=True))


class WorkspaceMember(Base):
    __tablename__ = "workspace_members"
    __table_args__ = {"schema": "grapion_one_x"}
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    workspace_id = Column(UUID(as_uuid=True), ForeignKey("grapion_one_x.module_workspaces.id"), nullable=False)
    branch_id = Column(UUID(as_uuid=True), ForeignKey("grapion_one_x.workspace_branches.id"))
    user_id = Column(UUID(as_uuid=True), ForeignKey("grapion_one_x.users.id"), nullable=False)
    role_id = Column(UUID(as_uuid=True), ForeignKey("grapion_one_x.module_roles.id"), nullable=False)
    status = Column(String(20), nullable=False, default="invited")
    invited_by = Column(UUID(as_uuid=True), ForeignKey("grapion_one_x.users.id"))
    responded_at = Column(DateTime(timezone=True))
    created_at = Column(DateTime(timezone=True))
    updated_at = Column(DateTime(timezone=True))
    created_by = Column(UUID(as_uuid=True))
    modified_by = Column(UUID(as_uuid=True))
    workspace = relationship("ModuleWorkspace")
    branch = relationship("WorkspaceBranch")
    role = relationship("ModuleRole")
    user = relationship("User", foreign_keys=[user_id])


class Notification(Base):
    __tablename__ = "notifications"
    __table_args__ = {"schema": "grapion_one_x"}
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("grapion_one_x.users.id"), nullable=False)
    workspace_id = Column(UUID(as_uuid=True))
    branch_id = Column(UUID(as_uuid=True))
    category = Column(String(30), nullable=False)
    title = Column(String(150), nullable=False)
    message = Column(Text, nullable=False)
    dedupe_key = Column(String(120))
    is_read = Column(Boolean, nullable=False, default=False)
    read_at = Column(DateTime(timezone=True))
    created_at = Column(DateTime(timezone=True))
    created_by = Column(UUID(as_uuid=True))


class PlatformAuditLog(Base):
    __tablename__ = "platform_audit_logs"
    __table_args__ = {"schema": "grapion_one_x"}
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    actor_id = Column(UUID(as_uuid=True), ForeignKey("grapion_one_x.users.id"))
    actor_role = Column(String(20))
    action = Column(String(60), nullable=False)
    entity = Column(String(60), nullable=False)
    entity_id = Column(UUID(as_uuid=True))
    workspace_id = Column(UUID(as_uuid=True))
    detail = Column(JSONB)
    created_at = Column(DateTime(timezone=True))
#Added By Nikhil 21Nov26 23:30 For module role master, businesses, branches, notifications, audit END


#Added By Nikhil 22Nov26 08:35 For Platform Settings + announcement banners START
from sqlalchemy.dialects.postgresql import JSONB as _JSONB  # noqa: E402


class PlatformSetting(Base):
    __tablename__ = "platform_settings"
    __table_args__ = {"schema": "grapion_one_x"}
    key = Column(String(60), primary_key=True)
    value = Column(_JSONB, nullable=False)
    description = Column(String(200))
    updated_at = Column(DateTime(timezone=True))
    updated_by = Column(UUID(as_uuid=True), ForeignKey("grapion_one_x.users.id"))


class PlatformAnnouncement(Base):
    __tablename__ = "platform_announcements"
    __table_args__ = {"schema": "grapion_one_x"}
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    title = Column(String(120), nullable=False)
    message = Column(String(500), nullable=False)
    style = Column(String(10), nullable=False, default="info")
    audience = Column(String(10), nullable=False, default="all")
    starts_at = Column(DateTime(timezone=True), nullable=False)
    ends_at = Column(DateTime(timezone=True), nullable=False)
    is_active = Column(Boolean, nullable=False, default=True)
    created_at = Column(DateTime(timezone=True))
    updated_at = Column(DateTime(timezone=True))
    created_by = Column(UUID(as_uuid=True))
    modified_by = Column(UUID(as_uuid=True))
#Added By Nikhil 22Nov26 08:35 For Platform Settings + announcement banners END
