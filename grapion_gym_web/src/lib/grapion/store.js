/**
 * Central localStorage data layer for GRAPION GYM.
 * Every dashboard reads and writes the same store, so a change in one
 * workspace shows up in the others without a reload.
 */
const KEY = "grapion_gym_db_v2";
/** Superseded stores, wiped so a fresh install never inherits old records. */
const LEGACY_KEYS = ["grapion_gym_db_v1"];
export const SCHEMA_VERSION = 4;

/** Temporary local demo credential — replace with server-side auth in production. */
export const ADMIN_CREDENTIALS = {
  email: "hellograpiondigital@gmail.com",
  password: "GP@grapion2204",
  name: "Grapion Admin",
};

export const COLLECTIONS = [
  "gyms",
  "gymOwners",
  "gymMembers",
  "membershipPlans",
  "memberships",
  "batches",
  "trainers",
  "services",
  "attendance",
  "payments",
  "subscriptionPayments",
  "notifications",
  "gymSubscriptions",
  "auditLogs",
];

export const DEFAULT_BRAND = {
  primary: "#e2932b",
  secondary: "#3d2a12",
  accent: "#4bb8a9",
  bg: "#111013",
  button: "#e2932b",
  text: "#f6f1e7",
};

const defaultSettings = () => ({
  company: "Grapion Digital",
  currency: "INR",
  expiryWarningDays: 7,
  plans: { monthly: 1499, quarterly: 3999, halfYearly: 7499, yearly: 12999 },
});

export function emptyDB() {
  const base = { version: SCHEMA_VERSION, adminSettings: defaultSettings() };
  COLLECTIONS.forEach((name) => {
    base[name] = [];
  });
  return base;
}

const ls = () => (typeof window === "undefined" ? null : window.localStorage);
let cache = null;
const listeners = new Set();

function migrate(raw) {
  const db = { ...emptyDB(), ...(raw || {}) };
  db.adminSettings = { ...defaultSettings(), ...(raw?.adminSettings || {}) };
  db.adminSettings.plans = { ...defaultSettings().plans, ...(raw?.adminSettings?.plans || {}) };
  COLLECTIONS.forEach((name) => {
    if (!Array.isArray(db[name])) db[name] = [];
  });
  db.version = SCHEMA_VERSION;
  return db;
}

function read() {
  try {
    const storage = ls();
    if (!storage) return emptyDB();
    LEGACY_KEYS.forEach((legacy) => storage.removeItem(legacy));
    const raw = storage.getItem(KEY);
    if (!raw) return emptyDB();
    return migrate(JSON.parse(raw));
  } catch (e) {
    return emptyDB();
  }
}

export function getDB() {
  if (!ls()) return emptyDB();
  if (!cache) cache = read();
  return cache;
}

function persist(db) {
  const storage = ls();
  if (!storage) return;
  try {
    storage.setItem(KEY, JSON.stringify(db));
  } catch (e) {
    throw new Error(
      "Local browser storage is full. Remove a few member photos or export a backup and reset demo data.",
    );
  }
}

const clone = (value) => JSON.parse(JSON.stringify(value));

export function setDB(mutator) {
  const draft = clone(getDB());
  const result = mutator(draft);
  draft.updatedAt = new Date().toISOString();
  persist(draft);
  cache = draft;
  listeners.forEach((fn) => fn(draft));
  return result === undefined ? draft : result;
}

export function subscribe(fn) {
  listeners.add(fn);
  return () => listeners.delete(fn);
}

export function replaceDB(next) {
  const db = migrate(next);
  persist(db);
  cache = db;
  listeners.forEach((fn) => fn(db));
  return db;
}

export function storageSize() {
  try {
    const raw = ls()?.getItem(KEY) || "";
    return Math.round((raw.length / 1024) * 10) / 10;
  } catch (e) {
    return 0;
  }
}