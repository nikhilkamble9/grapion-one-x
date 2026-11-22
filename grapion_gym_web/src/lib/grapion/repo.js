import { getDB, setDB, emptyDB, replaceDB, DEFAULT_BRAND, ADMIN_CREDENTIALS } from "./store";
import { setSession, clearSession } from "./session";
import { buildDemo, DEMO_GYM_ID } from "./seed";
import { addMonths, daysUntil, memberCodeFor, membershipStatus, todayISO, uid } from "./util";

export const CYCLE_MONTHS = { monthly: 1, quarterly: 3, halfYearly: 6, yearly: 12 };

/* ------------------------------ selectors ------------------------------ */

export const findGym = (db, gymId) => db.gyms.find((g) => g.id === gymId) || null;
export const ownerOf = (db, gymId) => db.gymOwners.find((o) => o.gymId === gymId) || null;
export const memberById = (db, memberId) => db.gymMembers.find((m) => m.id === memberId) || null;
export const subscriptionOf = (db, gymId) => db.gymSubscriptions.find((s) => s.gymId === gymId) || null;
export const planById = (db, planId) => db.membershipPlans.find((p) => p.id === planId) || null;
export const batchById = (db, batchId) => db.batches.find((b) => b.id === batchId) || null;

export function latestMembership(db, memberId) {
  return (
    db.memberships
      .filter((m) => m.memberId === memberId && m.status !== "cancelled")
      .sort((a, b) => (a.expiryDate < b.expiryDate ? 1 : -1))[0] || null
  );
}

export function verifiedPaid(db, membershipId) {
  return db.payments
    .filter((p) => p.membershipId === membershipId && p.status === "verified")
    .reduce((sum, p) => sum + Number(p.amount || 0), 0);
}

export function memberView(db, memberId) {
  const member = memberById(db, memberId);
  if (!member) return null;
  const membership = latestMembership(db, member.id);
  const plan = membership ? planById(db, membership.planId) : null;
  const gym = findGym(db, member.gymId);
  const batch = member.batchId ? batchById(db, member.batchId) : null;
  const warn = gym?.expiryWarningDays || db.adminSettings.expiryWarningDays || 7;
  const status = membership
    ? membershipStatus(membership.expiryDate, warn)
    : { key: "none", label: "No plan", days: 0, tone: "gray" };
  const paid = membership ? verifiedPaid(db, membership.id) : 0;
  const total = membership ? Number(membership.totalAmount || 0) : 0;
  return {
    member,
    membership,
    plan,
    gym,
    batch,
    status,
    paid,
    total,
    pending: Math.max(0, total - paid),
  };
}

export function gymStats(db, gymId) {
  const members = db.gymMembers.filter((m) => m.gymId === gymId);
  const warn = findGym(db, gymId)?.expiryWarningDays || db.adminSettings.expiryWarningDays || 7;
  const rows = members.map((m) => memberView(db, m.id));
  const today = todayISO();
  const attendance = db.attendance.filter((a) => a.gymId === gymId);
  const payments = db.payments.filter((p) => p.gymId === gymId);
  const monthKey = today.slice(0, 7);
  return {
    totalMembers: members.length,
    activeMembers: rows.filter((r) => r.status.key === "active").length,
    expiringSoon: rows.filter((r) => r.status.key === "expiring").length,
    expiredMembers: rows.filter((r) => r.status.key === "expired" || r.status.key === "none").length,
    inactiveMembers: members.filter((m) => m.status !== "active").length,
    todayCheckIns: attendance.filter((a) => a.date === today).length,
    todayCheckOuts: attendance.filter((a) => a.date === today && a.checkOut).length,
    pendingPayments: payments.filter((p) => p.status === "pending").length,
    pendingAmount: payments
      .filter((p) => p.status === "pending")
      .reduce((s, p) => s + Number(p.amount || 0), 0),
    todayPayments: payments
      .filter((p) => p.status === "verified" && String(p.date).slice(0, 10) === today)
      .reduce((s, p) => s + Number(p.amount || 0), 0),
    monthlyRevenue: payments
      .filter((p) => p.status === "verified" && String(p.date).slice(0, 7) === monthKey)
      .reduce((s, p) => s + Number(p.amount || 0), 0),
    noPlan: rows.filter((r) => !r.membership).length,
    rows,
  };
}

export function platformStats(db) {
  const subs = db.gyms.map((g) => ({ gym: g, sub: subscriptionOf(db, g.id) }));
  const revenue = db.subscriptionPayments
    .filter((p) => p.status === "verified")
    .reduce((s, p) => s + Number(p.amount || 0), 0);
  const yearKey = todayISO().slice(0, 4);
  const monthKey = todayISO().slice(0, 7);
  return {
    totalGyms: db.gyms.length,
    activeGyms: db.gyms.filter((g) => g.status === "active").length,
    suspendedGyms: db.gyms.filter((g) => g.status === "suspended").length,
    inactiveGyms: db.gyms.filter((g) => g.status === "inactive").length,
    expiredGyms: subs.filter((s) => s.sub && daysUntil(s.sub.expiryDate) < 0).length,
    totalMembers: db.gymMembers.length,
    activeSubscriptions: subs.filter(
      (s) => s.gym.status === "active" && s.sub && daysUntil(s.sub.expiryDate) >= 0,
    ).length,
    expiringSubscriptions: subs.filter((s) => {
      const d = s.sub ? daysUntil(s.sub.expiryDate) : -1;
      return s.gym.status === "active" && d >= 0 && d <= 7;
    }).length,
    totalRevenue: revenue,
    monthlyRevenue: db.subscriptionPayments
      .filter((p) => p.status === "verified" && String(p.date).slice(0, 7) === monthKey)
      .reduce((s, p) => s + Number(p.amount || 0), 0),
    yearlyRevenue: db.subscriptionPayments
      .filter((p) => p.status === "verified" && String(p.date).slice(0, 4) === yearKey)
      .reduce((s, p) => s + Number(p.amount || 0), 0),
    pendingPayments: db.subscriptionPayments.filter((p) => p.status === "pending").length,
    pendingAmount: db.subscriptionPayments
      .filter((p) => p.status === "pending")
      .reduce((s, p) => s + Number(p.amount || 0), 0),
    subs,
  };
}

/* ------------------------------ internals ------------------------------ */

function log(db, { actor, role, action, detail, gymId = null }) {
  db.auditLogs.unshift({
    id: uid("log"),
    actor,
    role,
    action,
    detail,
    gymId,
    date: new Date().toISOString(),
  });
  db.auditLogs = db.auditLogs.slice(0, 400);
}

function notify(db, { gymId, audience, memberId = null, title, message, category = "system", dedupeKey = null }) {
  if (dedupeKey && db.notifications.some((n) => n.dedupeKey === dedupeKey)) return;
  db.notifications.unshift({
    id: uid("ntf"),
    gymId,
    audience,
    memberId,
    title,
    message,
    category,
    read: false,
    date: new Date().toISOString(),
    dedupeKey,
  });
  db.notifications = db.notifications.slice(0, 600);
}

function recalcPaid(db, membershipId) {
  const ms = db.memberships.find((m) => m.id === membershipId);
  if (!ms) return;
  ms.paidAmount = verifiedPaid(db, membershipId);
}

const duplicate = (list, value, field = "email") =>
  list.some((row) => String(row[field] || "").trim().toLowerCase() === String(value || "").trim().toLowerCase());

/* -------------------------------- auth -------------------------------- */

export function loginAdmin(email, password) {
  const okEmail = String(email).trim().toLowerCase() === ADMIN_CREDENTIALS.email.toLowerCase();
  if (!okEmail || password !== ADMIN_CREDENTIALS.password) {
    return { ok: false, error: "Incorrect admin email or password." };
  }
  return {
    ok: true,
    session: setSession({
      role: "admin",
      name: ADMIN_CREDENTIALS.name,
      email: ADMIN_CREDENTIALS.email,
      at: new Date().toISOString(),
    }),
  };
}

export function loginOwner(email, password) {
  const db = getDB();
  const owner = db.gymOwners.find(
    (o) => String(o.email).toLowerCase() === String(email).trim().toLowerCase(),
  );
  if (!owner) return { ok: false, error: "No gym owner account exists for this email." };
  if (owner.password !== password) return { ok: false, error: "Incorrect password." };
  if (owner.status !== "active") return { ok: false, error: "This owner account is deactivated." };
  const gym = findGym(db, owner.gymId);
  return {
    ok: true,
    session: setSession({
      role: "owner",
      ownerId: owner.id,
      gymId: owner.gymId,
      name: owner.name,
      email: owner.email,
      gymName: gym?.name || "Your gym",
      at: new Date().toISOString(),
    }),
  };
}

export function loginMember(identifier, password) {
  const db = getDB();
  const value = String(identifier).trim().toLowerCase();
  const member = db.gymMembers.find(
    (m) => String(m.email).toLowerCase() === value || String(m.code).toLowerCase() === value,
  );
  if (!member) return { ok: false, error: "No member account found for this email or member ID." };
  if (member.password !== password) return { ok: false, error: "Incorrect password." };
  if (member.status !== "active") return { ok: false, error: "This member account is deactivated." };
  const gym = findGym(db, member.gymId);
  return {
    ok: true,
    session: setSession({
      role: "member",
      memberId: member.id,
      gymId: member.gymId,
      name: member.name,
      code: member.code,
      gymName: gym?.name || "Your gym",
      at: new Date().toISOString(),
    }),
  };
}

export const logout = () => clearSession();

/* -------------------------------- gyms -------------------------------- */

const defaultServices = () =>
  ["Gym", "Cardio", "Yoga", "Zumba", "Steam Bath"].map((name) => ({
    id: uid("svc"),
    name,
    description: "",
    status: "active",
    gymId: null,
  }));

const defaultPlans = () =>
  [
    ["Monthly Gym Package", 1, 999],
    ["Quarterly Gym Package", 3, 2499],
    ["Half-Yearly Package", 6, 4499],
    ["Yearly Package", 12, 7999],
  ].map(([name, months, price]) => ({
    id: uid("plan"),
    name,
    durationMonths: months,
    price,
    description: `${months} month access`,
    services: [],
    status: "active",
    gymId: null,
  }));

export function createGym(input) {
  return setDB((db) => {
    if (!input.name?.trim()) throw new Error("Gym name is required.");
    if (duplicate(db.gyms, input.name, "name")) throw new Error("A gym with this name already exists.");
    if (duplicate(db.gymOwners, input.ownerEmail)) throw new Error("This owner email is already in use.");

    const gymId = uid("gym");
    const gym = {
      id: gymId,
      name: input.name.trim(),
      phone: input.phone || "",
      email: input.email || "",
      address: input.address || "",
      city: input.city || "",
      description: "",
      openingHours: "Monday – Saturday · 6 AM to 10 PM",
      logo: "",
      upiId: "",
      upiName: input.name.trim(),
      upiQr: "",
      status: input.status || "active",
      brand: { ...DEFAULT_BRAND },
      createdAt: todayISO(),
      isDemo: false,
    };
    db.gyms.unshift(gym);
    db.gymOwners.unshift({
      id: uid("owner"),
      gymId,
      name: input.ownerName,
      email: String(input.ownerEmail).trim(),
      phone: input.phone || "",
      password: input.ownerPassword || "gym12345",
      status: "active",
      createdAt: todayISO(),
      isDemo: false,
    });

    defaultServices().forEach((s) => db.services.unshift({ ...s, gymId }));
    defaultPlans().forEach((p) => db.membershipPlans.unshift({ ...p, gymId }));

    const cycle = input.cycle || "monthly";
    const price = Number(input.price) || db.adminSettings.plans[cycle] || 0;
    const startDate = input.startDate || todayISO();
    const expiryDate = input.expiryDate || addMonths(startDate, CYCLE_MONTHS[cycle] || 1);
    db.gymSubscriptions.unshift({
      id: uid("sub"),
      gymId,
      planName: `${cycle} Subscription`,
      cycle,
      price,
      startDate,
      expiryDate,
      history: [{ startDate, expiryDate, cycle, amount: price, at: new Date().toISOString() }],
      isDemo: false,
    });
    db.subscriptionPayments.unshift({
      id: uid("spay"),
      gymId,
      amount: price,
      date: startDate,
      cycle,
      status: "verified",
      note: "Initial subscription",
      isDemo: false,
    });

    log(db, {
      actor: ADMIN_CREDENTIALS.name,
      role: "admin",
      action: "Gym created",
      detail: `${gym.name} onboarded with owner ${input.ownerName}.`,
      gymId,
    });
    notify(db, {
      gymId,
      audience: "owner",
      title: "Welcome to Grapion Gym",
      message: `Your gym workspace for ${gym.name} is ready.`,
      category: "account",
    });
    return gym;
  });
}

export function updateGym(gymId, patch) {
  return setDB((db) => {
    const gym = findGym(db, gymId);
    if (!gym) throw new Error("Gym not found.");
    Object.assign(gym, patch);
    return gym;
  });
}

export function setGymStatus(gymId, status) {
  return setDB((db) => {
    const gym = findGym(db, gymId);
    if (!gym) throw new Error("Gym not found.");
    gym.status = status;
    const owner = ownerOf(db, gymId);
    log(db, {
      actor: ADMIN_CREDENTIALS.name,
      role: "admin",
      action: `Gym ${status}`,
      detail: `${gym.name} marked ${status}.`,
      gymId,
    });
    if (owner) {
      notify(db, {
        gymId,
        audience: "owner",
        title: status === "active" ? "Gym activated" : `Gym ${status}`,
        message:
          status === "active"
            ? "Your gym workspace is active. Management features are available."
            : "Your gym workspace has been restricted by Grapion Digital. Contact us for renewal.",
        category: "subscription",
      });
    }
    return gym;
  });
}

/* ------------------------------- owners ------------------------------- */

export function saveOwner(input) {
  return setDB((db) => {
    if (input.id) {
      const owner = db.gymOwners.find((o) => o.id === input.id);
      if (!owner) throw new Error("Owner not found.");
      const clash = db.gymOwners.some(
        (o) => o.id !== input.id && String(o.email).toLowerCase() === String(input.email).toLowerCase(),
      );
      if (clash) throw new Error("Another owner already uses this email.");
      Object.assign(owner, {
        name: input.name,
        email: input.email,
        phone: input.phone || "",
        gymId: input.gymId || owner.gymId,
        status: input.status || owner.status,
        ...(input.password ? { password: input.password } : {}),
      });
      log(db, { actor: ADMIN_CREDENTIALS.name, role: "admin", action: "Owner updated", detail: owner.name, gymId: owner.gymId });
      return owner;
    }
    if (duplicate(db.gymOwners, input.email)) throw new Error("This owner email is already in use.");
    const owner = {
      id: uid("owner"),
      gymId: input.gymId,
      name: input.name,
      email: input.email,
      phone: input.phone || "",
      password: input.password || "gym12345",
      status: "active",
      createdAt: todayISO(),
      isDemo: false,
    };
    db.gymOwners.unshift(owner);
    log(db, { actor: ADMIN_CREDENTIALS.name, role: "admin", action: "Owner created", detail: owner.name, gymId: owner.gymId });
    return owner;
  });
}

export function resetOwnerPassword(ownerId, password) {
  return setDB((db) => {
    const owner = db.gymOwners.find((o) => o.id === ownerId);
    if (!owner) throw new Error("Owner not found.");
    owner.password = password;
    log(db, { actor: ADMIN_CREDENTIALS.name, role: "admin", action: "Owner access reset", detail: owner.email, gymId: owner.gymId });
    return owner;
  });
}

/* ------------------------------- members ------------------------------- */

export function createMember(input) {
  return setDB((db) => {
    const gym = findGym(db, input.gymId);
    if (!gym) throw new Error("Gym not found.");
    if (!input.name?.trim()) throw new Error("Member name is required.");
    if (input.email && duplicate(db.gymMembers, input.email)) throw new Error("This member email is already in use.");

    const index = db.gymMembers.filter((m) => m.gymId === gym.id).length + 1;
    const member = {
      id: uid("mem"),
      code: memberCodeFor(gym.name, index),
      gymId: gym.id,
      name: input.name.trim(),
      photo: input.photo || "",
      phone: input.phone || "",
      email: input.email || "",
      password: input.password || "member1234",
      gender: input.gender || "",
      dob: input.dob || "",
      occupation: input.occupation || "",
      address: input.address || "",
      emergencyContact: input.emergencyContact || "",
      notes: input.notes || "",
      status: "active",
      joinedAt: input.joiningDate || todayISO(),
      batchId: input.batchId || "",
      isDemo: false,
    };
    db.gymMembers.unshift(member);

    if (input.planId) {
      addMembershipRecord(db, {
        gymId: gym.id,
        memberId: member.id,
        planId: input.planId,
        batchId: input.batchId,
        startDate: input.startDate || todayISO(),
        joiningDate: input.joiningDate || todayISO(),
        paidAmount: Number(input.paidAmount) || 0,
        method: input.method || "cash",
        by: input.by || "Gym owner",
      });
    }

    notify(db, {
      gymId: gym.id,
      audience: "owner",
      title: "New member added",
      message: `${member.name} (${member.code}) was added to your gym.`,
      category: "member",
      dedupeKey: `member-created:${member.id}`,
    });
    log(db, { actor: input.by || "Gym owner", role: "owner", action: "Member created", detail: member.name, gymId: gym.id });
    return member;
  });
}

export function updateMember(memberId, patch) {
  return setDB((db) => {
    const member = memberById(db, memberId);
    if (!member) throw new Error("Member not found.");
    if (patch.email && duplicate(db.gymMembers.filter((m) => m.id !== memberId), patch.email)) {
      throw new Error("This member email is already in use.");
    }
    Object.assign(member, patch);
    return member;
  });
}

/* ------------------------------ memberships ------------------------------ */

function addMembershipRecord(db, { gymId, memberId, planId, batchId, startDate, joiningDate, paidAmount, method, by, totalAmount }) {
  const plan = planById(db, planId);
  if (!plan) throw new Error("Choose a membership plan.");
  const start = startDate || todayISO();
  const membership = {
    id: uid("mship"),
    gymId,
    memberId,
    planId,
    batchId: batchId || "",
    joiningDate: joiningDate || start,
    startDate: start,
    expiryDate: addMonths(start, plan.durationMonths),
    totalAmount: Number(totalAmount) || plan.price,
    paidAmount: 0,
    status: "active",
    createdAt: new Date().toISOString(),
    isDemo: false,
  };
  db.memberships.unshift(membership);
  if (Number(paidAmount) > 0) {
    db.payments.unshift({
      id: uid("pay"),
      gymId,
      memberId,
      membershipId: membership.id,
      planId,
      amount: Number(paidAmount),
      date: todayISO(),
      method: method || "cash",
      status: "verified",
      type: "membership",
      notes: `${plan.name} payment`,
      verifiedAt: new Date().toISOString(),
      verifiedBy: by || "Gym owner",
      createdAt: new Date().toISOString(),
      isDemo: false,
    });
    membership.paidAmount = Number(paidAmount);
  }
  return membership;
}

export function assignMembership(input) {
  return setDB((db) => {
    const member = memberById(db, input.memberId);
    if (!member) throw new Error("Member not found.");
    const membership = addMembershipRecord(db, {
      gymId: member.gymId,
      memberId: member.id,
      planId: input.planId,
      batchId: input.batchId || member.batchId,
      startDate: input.startDate,
      joiningDate: input.joiningDate,
      paidAmount: input.paidAmount,
      method: input.method,
      by: input.by,
      totalAmount: input.totalAmount,
    });
    log(db, { actor: input.by || "Gym owner", role: "owner", action: "Membership assigned", detail: member.name, gymId: member.gymId });
    return membership;
  });
}

export function updateMembership(membershipId, patch) {
  return setDB((db) => {
    const ms = db.memberships.find((m) => m.id === membershipId);
    if (!ms) throw new Error("Membership not found.");
    Object.assign(ms, patch);
    return ms;
  });
}

export function renewMembership({ memberId, planId, amount, method, notes, by }) {
  return setDB((db) => {
    const member = memberById(db, memberId);
    if (!member) throw new Error("Member not found.");
    const plan = planById(db, planId);
    if (!plan) throw new Error("Choose a plan to renew.");
    const previous = latestMembership(db, memberId);
    const base = previous && daysUntil(previous.expiryDate) >= 0 ? previous.expiryDate : todayISO();
    const expiryDate = addMonths(base, plan.durationMonths);
    const paid = Number(amount ?? plan.price);

    const membership = {
      id: uid("mship"),
      gymId: member.gymId,
      memberId,
      planId,
      batchId: member.batchId || "",
      joiningDate: todayISO(),
      startDate: base,
      expiryDate,
      totalAmount: plan.price,
      paidAmount: paid,
      status: "active",
      createdAt: new Date().toISOString(),
      isDemo: false,
      renewedFrom: previous?.id || null,
    };
    db.memberships.unshift(membership);
    db.payments.unshift({
      id: uid("pay"),
      gymId: member.gymId,
      memberId,
      membershipId: membership.id,
      planId,
      amount: paid,
      date: todayISO(),
      method: method || "cash",
      status: "verified",
      type: "renewal",
      notes: notes || `${plan.name} renewal`,
      verifiedAt: new Date().toISOString(),
      verifiedBy: by || "Gym owner",
      createdAt: new Date().toISOString(),
      isDemo: false,
    });
    notify(db, {
      gymId: member.gymId,
      audience: "member",
      memberId,
      title: "Membership renewed",
      message: `Your membership is active until ${expiryDate}. Plan: ${plan.name}.`,
      category: "membership",
      dedupeKey: `renewed:${membership.id}`,
    });
    log(db, { actor: by || "Gym owner", role: "owner", action: "Membership renewed", detail: `${member.name} until ${expiryDate}`, gymId: member.gymId });
    return membership;
  });
}

/* ------------------------------ attendance ------------------------------ */

export function checkIn(memberId, by = "Member") {
  return setDB((db) => {
    const member = memberById(db, memberId);
    if (!member) throw new Error("Member not found.");
    const today = todayISO();
    const open = db.attendance.find((a) => a.memberId === memberId && a.date === today && !a.checkOut);
    if (open) throw new Error("This member is already checked in.");
    const record = {
      id: uid("att"),
      gymId: member.gymId,
      memberId,
      date: today,
      checkIn: new Date().toISOString(),
      checkOut: null,
      isDemo: false,
    };
    db.attendance.unshift(record);
    notify(db, {
      gymId: member.gymId,
      audience: "owner",
      title: "Check-in",
      message: `${member.name} checked in at ${new Date().toLocaleTimeString("en-IN", { hour: "2-digit", minute: "2-digit" })}.`,
      category: "attendance",
      dedupeKey: `in:${record.id}`,
    });
    return record;
  });
}

export function checkOut(memberId) {
  return setDB((db) => {
    const member = memberById(db, memberId);
    if (!member) throw new Error("Member not found.");
    const open = db.attendance.find((a) => a.memberId === memberId && !a.checkOut);
    if (!open) throw new Error("No active check-in found for this member.");
    open.checkOut = new Date().toISOString();
    notify(db, {
      gymId: member.gymId,
      audience: "owner",
      title: "Check-out",
      message: `${member.name} checked out at ${new Date().toLocaleTimeString("en-IN", { hour: "2-digit", minute: "2-digit" })}.`,
      category: "attendance",
      dedupeKey: `out:${open.id}`,
    });
    return open;
  });
}

/* --------------------- plans / batches / trainers / services --------------------- */

function upsert(db, collection, input, prefix, label) {
  if (input.id) {
    const row = db[collection].find((r) => r.id === input.id);
    if (!row) throw new Error(`${label} not found.`);
    Object.assign(row, input);
    return row;
  }
  const row = { id: uid(prefix), status: "active", isDemo: false, ...input };
  db[collection].unshift(row);
  return row;
}

export function savePlan(input) {
  return setDB((db) =>
    upsert(
      db,
      "membershipPlans",
      {
        ...input,
        durationMonths: Number(input.durationMonths) || 1,
        price: Number(input.price) || 0,
      },
      "plan",
      "Plan",
    ),
  );
}

export function saveBatch(input) {
  return setDB((db) =>
    upsert(
      db,
      "batches",
      {
        ...input,
        capacity: Number(input.capacity) || 0,
        days: Array.isArray(input.days)
          ? input.days
          : String(input.days || "")
              .split(",")
              .map((d) => d.trim())
              .filter(Boolean),
      },
      "batch",
      "Batch",
    ),
  );
}

export function deleteBatch(batchId) {
  return setDB((db) => {
    db.batches = db.batches.filter((b) => b.id !== batchId);
    db.gymMembers.forEach((m) => {
      if (m.batchId === batchId) m.batchId = "";
    });
  });
}

export function assignBatchMembers(memberIds, batchId) {
  return setDB((db) => {
    db.gymMembers.forEach((m) => {
      if (memberIds.includes(m.id)) m.batchId = batchId;
    });
  });
}

export function saveTrainer(input) {
  return setDB((db) => upsert(db, "trainers", input, "trn", "Trainer"));
}

export function saveService(input) {
  return setDB((db) => upsert(db, "services", input, "svc", "Service"));
}

export function setRowStatus(collection, id, status) {
  return setDB((db) => {
    const row = (db[collection] || []).find((r) => r.id === id);
    if (!row) throw new Error("Record not found.");
    row.status = status;
    return row;
  });
}

/* -------------------------------- payments -------------------------------- */

export function recordPayment({ memberId, amount, method, notes, planId, membershipId, status = "verified", by = "Gym owner" }) {
  return setDB((db) => {
    const member = memberById(db, memberId);
    if (!member) throw new Error("Member not found.");
    const value = Number(amount);
    if (!value || value <= 0) throw new Error("Enter a payment amount greater than zero.");
    const payment = {
      id: uid("pay"),
      gymId: member.gymId,
      memberId,
      membershipId: membershipId || latestMembership(db, memberId)?.id || "",
      planId: planId || "",
      amount: value,
      date: todayISO(),
      method: method || "cash",
      status,
      type: "membership",
      notes: notes || "",
      verifiedAt: status === "verified" ? new Date().toISOString() : null,
      verifiedBy: status === "verified" ? by : "",
      createdAt: new Date().toISOString(),
      isDemo: false,
    };
    db.payments.unshift(payment);
    if (payment.membershipId) recalcPaid(db, payment.membershipId);
    notify(db, {
      gymId: member.gymId,
      audience: "owner",
      title: status === "verified" ? "Payment recorded" : "Payment pending",
      message: `${member.name} · ₹${value} recorded via ${payment.method.toUpperCase()}.`,
      category: "payment",
      dedupeKey: `pay:${payment.id}`,
    });
    log(db, { actor: by, role: "owner", action: "Payment recorded", detail: `${member.name} · ₹${value}`, gymId: member.gymId });
    return payment;
  });
}

export function submitRenewalRequest({ memberId, planId, amount, method, notes }) {
  return setDB((db) => {
    const member = memberById(db, memberId);
    if (!member) throw new Error("Member not found.");
    const plan = planById(db, planId);
    if (!plan) throw new Error("Choose a plan to renew.");
    const existing = db.payments.find(
      (p) => p.memberId === memberId && p.status === "pending" && p.type === "renewal",
    );
    if (existing) throw new Error("You already have a renewal waiting for gym verification.");
    const payment = {
      id: uid("pay"),
      gymId: member.gymId,
      memberId,
      membershipId: "",
      planId,
      amount: Number(amount) || plan.price,
      date: todayISO(),
      method: method || "upi",
      status: "pending",
      type: "renewal",
      notes: notes || "",
      createdAt: new Date().toISOString(),
      isDemo: false,
    };
    db.payments.unshift(payment);
    notify(db, {
      gymId: member.gymId,
      audience: "owner",
      title: "Renewal payment submitted",
      message: `${member.name} submitted ₹${payment.amount} for ${plan.name}. Verify to renew.`,
      category: "payment",
      dedupeKey: `renew-req:${payment.id}`,
    });
    notify(db, {
      gymId: member.gymId,
      audience: "member",
      memberId,
      title: "Renewal submitted",
      message: "Your renewal payment is pending gym verification. Your membership updates once verified.",
      category: "payment",
      dedupeKey: `renew-ack:${payment.id}`,
    });
    return payment;
  });
}

export function verifyPayment(paymentId, by = "Gym owner") {
  return setDB((db) => {
    const payment = db.payments.find((p) => p.id === paymentId);
    if (!payment) throw new Error("Payment not found.");
    if (payment.status === "verified") throw new Error("This payment is already verified.");
    const member = memberById(db, payment.memberId);
    payment.status = "verified";
    payment.verifiedAt = new Date().toISOString();
    payment.verifiedBy = by;

    if (payment.type === "renewal" && payment.planId) {
      const plan = planById(db, payment.planId);
      const previous = latestMembership(db, payment.memberId);
      const base = previous && daysUntil(previous.expiryDate) >= 0 ? previous.expiryDate : todayISO();
      const membership = {
        id: uid("mship"),
        gymId: payment.gymId,
        memberId: payment.memberId,
        planId: payment.planId,
        batchId: member?.batchId || "",
        joiningDate: todayISO(),
        startDate: base,
        expiryDate: addMonths(base, plan.durationMonths),
        totalAmount: plan.price,
        paidAmount: payment.amount,
        status: "active",
        createdAt: new Date().toISOString(),
        isDemo: false,
        renewedFrom: previous?.id || null,
      };
      db.memberships.unshift(membership);
      payment.membershipId = membership.id;
      notify(db, {
        gymId: payment.gymId,
        audience: "member",
        memberId: payment.memberId,
        title: "Membership renewed",
        message: `Payment verified. Your new expiry date is ${membership.expiryDate}.`,
        category: "membership",
        dedupeKey: `verified-renew:${payment.id}`,
      });
    } else {
      if (payment.membershipId) recalcPaid(db, payment.membershipId);
      notify(db, {
        gymId: payment.gymId,
        audience: "member",
        memberId: payment.memberId,
        title: "Payment verified",
        message: `Your payment of ₹${payment.amount} has been verified by the gym.`,
        category: "payment",
        dedupeKey: `verified:${payment.id}`,
      });
    }
    log(db, { actor: by, role: "owner", action: "Payment verified", detail: `₹${payment.amount} · ${member?.name || "member"}`, gymId: payment.gymId });
    return payment;
  });
}

export function cancelPayment(paymentId, by = "Gym owner") {
  return setDB((db) => {
    const payment = db.payments.find((p) => p.id === paymentId);
    if (!payment) throw new Error("Payment not found.");
    payment.status = "cancelled";
    payment.cancelledAt = new Date().toISOString();
    if (payment.membershipId) recalcPaid(db, payment.membershipId);
    log(db, { actor: by, role: "owner", action: "Payment cancelled", detail: `₹${payment.amount}`, gymId: payment.gymId });
    return payment;
  });
}

/* ----------------------------- subscriptions ----------------------------- */

export function renewGymSubscription({ gymId, cycle, amount, startDate, note }) {
  return setDB((db) => {
    const sub = subscriptionOf(db, gymId);
    const gym = findGym(db, gymId);
    if (!gym) throw new Error("Gym not found.");
    const months = CYCLE_MONTHS[cycle] || 1;
    const start = startDate || todayISO();
    const base = sub && daysUntil(sub.expiryDate) >= 0 ? sub.expiryDate : start;
    const expiryDate = addMonths(base, months);
    const price = Number(amount) || db.adminSettings.plans[cycle] || 0;
    const entry = { startDate: start, expiryDate, cycle, amount: price, at: new Date().toISOString() };

    if (sub) {
      sub.startDate = start;
      sub.expiryDate = expiryDate;
      sub.cycle = cycle;
      sub.price = price;
      sub.planName = `${cycle} Subscription`;
      sub.history = [...(sub.history || []), entry];
    } else {
      db.gymSubscriptions.unshift({
        id: uid("sub"),
        gymId,
        planName: `${cycle} Subscription`,
        cycle,
        price,
        startDate: start,
        expiryDate,
        history: [entry],
        isDemo: false,
      });
    }
    if (gym.status !== "active") gym.status = "active";
    db.subscriptionPayments.unshift({
      id: uid("spay"),
      gymId,
      amount: price,
      date: start,
      cycle,
      status: "verified",
      note: note || "Subscription renewal",
      isDemo: false,
    });
    notify(db, {
      gymId,
      audience: "owner",
      title: "Subscription renewed",
      message: `Your Grapion subscription is active until ${expiryDate}.`,
      category: "subscription",
      dedupeKey: `sub-renew:${expiryDate}`,
    });
    log(db, {
      actor: ADMIN_CREDENTIALS.name,
      role: "admin",
      action: "Subscription renewed",
      detail: `${gym.name} until ${expiryDate}`,
      gymId,
    });
    return { expiryDate };
  });
}

export function recordSubscriptionPayment({ gymId, amount, cycle, date, status = "pending", note }) {
  return setDB((db) => {
    const gym = findGym(db, gymId);
    if (!gym) throw new Error("Gym not found.");
    const value = Number(amount);
    if (!value || value <= 0) throw new Error("Enter an amount greater than zero.");
    const payment = {
      id: uid("spay"),
      gymId,
      amount: value,
      date: date || todayISO(),
      cycle: cycle || "monthly",
      status,
      note: note || "",
      isDemo: false,
    };
    db.subscriptionPayments.unshift(payment);
    log(db, {
      actor: ADMIN_CREDENTIALS.name,
      role: "admin",
      action: "Subscription payment recorded",
      detail: `${gym.name} · ₹${value} (${status})`,
      gymId,
    });
    return payment;
  });
}

export function setSubscriptionPaymentStatus(id, status) {
  return setDB((db) => {
    const pay = db.subscriptionPayments.find((p) => p.id === id);
    if (!pay) throw new Error("Subscription payment not found.");
    pay.status = status;
    return pay;
  });
}

/* ------------------------------- branding ------------------------------- */

export function updateBranding(gymId, brand) {
  return setDB((db) => {
    const gym = findGym(db, gymId);
    if (!gym) throw new Error("Gym not found.");
    gym.brand = { ...(gym.brand || DEFAULT_BRAND), ...brand };
    return gym;
  });
}

export function saveSettings(patch) {
  return setDB((db) => {
    db.adminSettings = { ...db.adminSettings, ...patch };
    return db.adminSettings;
  });
}

/* ----------------------------- notifications ----------------------------- */

export function markNotificationRead(id) {
  return setDB((db) => {
    const row = db.notifications.find((n) => n.id === id);
    if (row) row.read = true;
    return row;
  });
}

export function markAllRead({ gymId, audience, memberId }) {
  return setDB((db) => {
    db.notifications.forEach((n) => {
      const gymOk = !gymId || n.gymId === gymId;
      const audOk = !audience || n.audience === audience;
      const memOk = !memberId || n.memberId === memberId;
      if (gymOk && audOk && memOk) n.read = true;
    });
  });
}

/** Reminder stage for a membership, derived from the days left. */
function reminderStage(days, lead) {
  if (days < 0) return "expired";
  if (days <= 1) return "day1";
  if (days <= 3) return "day3";
  if (days <= lead) return "lead";
  return null;
}

/**
 * Derives expiry reminders from stored dates, so they stay accurate even if the
 * app was closed for days. Safe to call on every load and on a timer.
 * Each membership produces at most one reminder per stage.
 */
export function runExpirySweep() {
  const db = getDB();
  const fresh = [];
  db.memberships.forEach((ms) => {
    const member = memberById(db, ms.memberId);
    if (!member || member.status !== "active") return;
    if (latestMembership(db, member.id)?.id !== ms.id) return;
    const gym = findGym(db, ms.gymId);
    if (gym && gym.remindersEnabled === false) return;
    const lead = Number(gym?.expiryWarningDays || db.adminSettings.expiryWarningDays) || 7;
    const days = daysUntil(ms.expiryDate);
    const stage = reminderStage(days, lead);
    if (!stage) return;
    const memberKey = `expiry:${ms.id}:${stage}`;
    const ownerKey = `owner-expiry:${ms.id}:${stage}`;
    const left = `${days} day${days === 1 ? "" : "s"}`;
    if (!db.notifications.some((n) => n.dedupeKey === memberKey)) {
      fresh.push({
        id: uid("ntf"),
        gymId: ms.gymId,
        audience: "member",
        memberId: member.id,
        title: stage === "expired" ? "Membership expired" : "Membership expiring soon",
        message:
          stage === "expired"
            ? `Your membership expired on ${ms.expiryDate}. Renew to keep your access and visit history.`
            : `Your membership expires on ${ms.expiryDate} — ${left} left. You can renew from the Renew Plan page.`,
        category: "membership",
        read: false,
        date: new Date().toISOString(),
        dedupeKey: memberKey,
        email: member.email
          ? {
              to: member.email,
              memberName: member.name,
              gymName: gym?.name || "Your gym",
              planName: planById(db, ms.planId)?.name || "",
              expiryDate: ms.expiryDate,
              daysLeft: days,
            }
          : null,
      });
    }
    if (!db.notifications.some((n) => n.dedupeKey === ownerKey)) {
      fresh.push({
        id: uid("ntf"),
        gymId: ms.gymId,
        audience: "owner",
        memberId: member.id,
        title: stage === "expired" ? "Membership expired" : "Membership expiring soon",
        message:
          stage === "expired"
            ? `${member.name} · membership expired on ${ms.expiryDate}.`
            : `${member.name} · ${left} left (expires ${ms.expiryDate}).`,
        category: "membership",
        read: false,
        date: new Date().toISOString(),
        dedupeKey: ownerKey,
      });
    }
  });
  if (!fresh.length) return 0;
  setDB((draft) => {
    fresh.forEach((n) => draft.notifications.unshift(n));
  });
  return fresh.length;
}

/** Member reminders still waiting for an email, with retries capped. */
export function pendingReminderEmails(db = getDB()) {
  return db.notifications
    .filter((n) => n.email?.to && !n.emailSent && (n.emailAttempts || 0) < 2)
    .slice(0, 10);
}

export function markReminderEmail(notificationId, patch) {
  return setDB((db) => {
    const row = db.notifications.find((n) => n.id === notificationId);
    if (!row) return null;
    Object.assign(row, patch);
    if (!patch.emailSent) row.emailAttempts = (row.emailAttempts || 0) + 1;
    return row;
  });
}

/* ---------------------------- data management ---------------------------- */

export function seedDemoData() {
  const bundle = buildDemo();
  return setDB((db) => {
    if (db.gyms.some((g) => g.id === DEMO_GYM_ID)) throw new Error("The demo gym is already loaded.");
    db.gyms.unshift(bundle.gym);
    db.gymOwners.unshift(bundle.owner);
    bundle.services.forEach((s) => db.services.unshift(s));
    bundle.plans.forEach((p) => db.membershipPlans.unshift(p));
    bundle.trainers.forEach((t) => db.trainers.unshift(t));
    bundle.batches.forEach((b) => db.batches.unshift(b));
    bundle.members.forEach((m) => db.gymMembers.unshift(m));
    bundle.memberships.forEach((m) => db.memberships.unshift(m));
    bundle.payments.forEach((p) => db.payments.unshift(p));
    bundle.attendance.forEach((a) => db.attendance.unshift(a));
    db.gymSubscriptions.unshift(bundle.subscription);
    db.subscriptionPayments.unshift({
      id: uid("spay"),
      gymId: DEMO_GYM_ID,
      amount: bundle.subscription.price,
      date: bundle.subscription.startDate,
      cycle: bundle.subscription.cycle,
      status: "verified",
      note: "Demo subscription",
      isDemo: true,
    });
    log(db, { actor: ADMIN_CREDENTIALS.name, role: "admin", action: "Demo data loaded", detail: "Nishchay Fitness sample records", gymId: DEMO_GYM_ID });
  });
}

export function clearDemoData() {
  return setDB((db) => {
    const demoGymIds = new Set(db.gyms.filter((g) => g.isDemo).map((g) => g.id));
    const isDemoRow = (row) => row.isDemo || demoGymIds.has(row.gymId);
    ["gyms", "gymOwners", "gymMembers", "membershipPlans", "memberships", "batches", "trainers", "services", "attendance", "payments", "subscriptionPayments", "notifications", "gymSubscriptions"].forEach(
      (name) => {
        db[name] = db[name].filter((row) => !isDemoRow(row));
      },
    );
    log(db, { actor: ADMIN_CREDENTIALS.name, role: "admin", action: "Demo data removed", detail: "Sample records cleared" });
  });
}

export function resetAllData() {
  replaceDB(emptyDB());
  clearSession();
}

export function importBackup(text) {
  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch (e) {
    throw new Error("This file is not valid JSON.");
  }
  const db = parsed?.data && parsed?.app === "grapion-gym" ? parsed.data : parsed;
  if (!db || !Array.isArray(db.gyms)) throw new Error("This backup does not look like a Grapion Gym backup.");
  replaceDB(db);
}

export function exportBackupText() {
  return JSON.stringify({ app: "grapion-gym", exportedAt: new Date().toISOString(), data: getDB() }, null, 2);
}