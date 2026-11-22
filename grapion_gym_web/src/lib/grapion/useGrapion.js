import { useState, useEffect } from "react";
import { getDB, subscribe } from "./store";
import { getSession, onSession } from "./session";

export function useStore() {
  const [db, setDb] = useState(() => getDB());
  useEffect(() => {
    setDb(getDB());
    const stop = subscribe((next) => setDb(next));
    return () => stop();
  }, []);
  return db;
}

export function useRoleSession() {
  const [session, setLocal] = useState(() => getSession());
  useEffect(() => {
    setLocal(getSession());
    const stop = onSession((next) => setLocal(next));
    return () => stop();
  }, []);
  return session;
}