const KEY = "grapion_session_v2";
const LEGACY_KEYS = ["grapion_session_v1"];
const listeners = new Set();

const ls = () => (typeof window === "undefined" ? null : window.localStorage);

export function getSession() {
  try {
    const storage = ls();
    LEGACY_KEYS.forEach((legacy) => storage?.removeItem(legacy));
    const raw = storage?.getItem(KEY);
    return raw ? JSON.parse(raw) : null;
  } catch (e) {
    return null;
  }
}

export function setSession(session) {
  try {
    ls()?.setItem(KEY, JSON.stringify(session));
  } catch (e) {
    /* session persistence is best-effort */
  }
  listeners.forEach((fn) => fn(session));
  return session;
}

export function clearSession() {
  ls()?.removeItem(KEY);
  listeners.forEach((fn) => fn(null));
}

export function onSession(fn) {
  listeners.add(fn);
  return () => listeners.delete(fn);
}