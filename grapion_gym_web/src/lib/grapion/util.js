export const uid = (prefix = "id") =>
  `${prefix}_${Date.now().toString(36)}${Math.random().toString(36).slice(2, 7)}`;

const pad = (n) => String(n).padStart(2, "0");

export const isoDate = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;

export const todayISO = () => isoDate(new Date());

export const parseDate = (value) => {
  if (!value) return null;
  const d = new Date(String(value).length <= 10 ? `${value}T00:00:00` : value);
  return Number.isNaN(d.getTime()) ? null : d;
};

/** Real calendar month addition — 11 Nov + 3 months = 11 Feb, never 90 days. */
export function addMonths(dateStr, months) {
  const d = parseDate(dateStr);
  if (!d) return dateStr;
  const day = d.getDate();
  const target = new Date(d.getFullYear(), d.getMonth() + Number(months || 0), 1);
  const lastDay = new Date(target.getFullYear(), target.getMonth() + 1, 0).getDate();
  target.setDate(Math.min(day, lastDay));
  return isoDate(target);
}

export function daysUntil(dateStr) {
  const d = parseDate(dateStr);
  if (!d) return 0;
  const today = parseDate(todayISO());
  return Math.round((d.getTime() - today.getTime()) / 86400000);
}

export const fmtDate = (value) => {
  const d = parseDate(value);
  return d ? d.toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric" }) : "—";
};

export const fmtDateShort = (value) => {
  const d = parseDate(value);
  return d ? d.toLocaleDateString("en-IN", { day: "2-digit", month: "short" }) : "—";
};

export const fmtTime = (value) => {
  const d = parseDate(value);
  return d ? d.toLocaleTimeString("en-IN", { hour: "2-digit", minute: "2-digit" }) : "—";
};

export const fmtDateTime = (value) => {
  const d = parseDate(value);
  if (!d) return "—";
  return `${d.toLocaleDateString("en-IN", { day: "2-digit", month: "short" })} · ${d.toLocaleTimeString(
    "en-IN",
    { hour: "2-digit", minute: "2-digit" },
  )}`;
};

export const money = (value) =>
  `₹${Number(value || 0).toLocaleString("en-IN", { maximumFractionDigits: 0 })}`;

export const initials = (name = "") =>
  name
    .trim()
    .split(/\s+/)
    .map((w) => w[0])
    .join("")
    .slice(0, 2)
    .toUpperCase() || "GP";

export const durationLabel = (months) => {
  const m = Number(months);
  if (m === 1) return "1 Month";
  if (m === 12) return "12 Months";
  return `${m} Months`;
};

export function membershipStatus(expiryDate, warnDays = 7) {
  const days = daysUntil(expiryDate);
  if (days < 0) return { key: "expired", label: "Expired", days, tone: "red" };
  if (days === 0) return { key: "expiring", label: "Expires today", days, tone: "red" };
  if (days <= warnDays)
    return {
      key: "expiring",
      label: days === 1 ? "Expires tomorrow" : `${days} days left`,
      days,
      tone: "amber",
    };
  return { key: "active", label: "Active", days, tone: "green" };
}

export function subscriptionStatus(expiryDate, gymStatus) {
  if (gymStatus === "suspended" || gymStatus === "inactive") {
    return { key: "suspended", label: "Suspended", tone: "red", days: daysUntil(expiryDate) };
  }
  const days = daysUntil(expiryDate);
  if (days < 0) return { key: "expired", label: "Expired", tone: "red", days };
  if (days <= 7) return { key: "expiring", label: "Expiring soon", tone: "amber", days };
  return { key: "active", label: "Active", tone: "green", days };
}

export const waLink = (phone, text) => {
  const digits = String(phone || "").replace(/\D/g, "");
  const withCode = digits.length === 10 ? `91${digits}` : digits;
  return `https://wa.me/${withCode}?text=${encodeURIComponent(text)}`;
};

export const memberCodeFor = (gymName, index) => {
  const prefix =
    String(gymName || "gym")
      .trim()
      .split(/\s+/)
      .map((w) => w[0])
      .join("")
      .slice(0, 3)
      .toUpperCase() || "GYM";
  return `${prefix}-${String(index).padStart(4, "0")}`;
};

/* ---------- image handling: kept small so localStorage never blows up ---------- */

export function fileToDataUrl(file, max = 420) {
  return new Promise((resolve, reject) => {
    if (!file.type.startsWith("image/")) {
      reject(new Error("Please choose an image file."));
      return;
    }
    const reader = new FileReader();
    reader.onload = () => {
      const img = new Image();
      img.onload = () => {
        const scale = Math.min(1, max / Math.max(img.width, img.height));
        const canvas = document.createElement("canvas");
        canvas.width = Math.max(1, Math.round(img.width * scale));
        canvas.height = Math.max(1, Math.round(img.height * scale));
        const ctx = canvas.getContext("2d");
        ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
        resolve(canvas.toDataURL("image/jpeg", 0.78));
      };
      img.onerror = () => reject(new Error("This image could not be read."));
      img.src = reader.result;
    };
    reader.onerror = () => reject(new Error("This file could not be read."));
    reader.readAsDataURL(file);
  });
}

function rgbToHsl(r, g, b) {
  r /= 255;
  g /= 255;
  b /= 255;
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const l = (max + min) / 2;
  let h = 0;
  let s = 0;
  if (max !== min) {
    const d = max - min;
    s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    if (max === r) h = ((g - b) / d + (g < b ? 6 : 0)) * 60;
    else if (max === g) h = ((b - r) / d + 2) * 60;
    else h = ((r - g) / d + 4) * 60;
  }
  return [h, s, l];
}

export function hslToHex(h, s, l) {
  const a = s * Math.min(l, 1 - l);
  const f = (n) => {
    const k = (n + h / 30) % 12;
    const color = l - a * Math.max(Math.min(k - 3, 9 - k, 1), -1);
    return Math.round(255 * color)
      .toString(16)
      .padStart(2, "0");
  };
  return `#${f(0)}${f(8)}${f(4)}`;
}

export function hexToChannels(hex) {
  const clean = String(hex || "").replace("#", "");
  if (clean.length !== 6) return null;
  const r = parseInt(clean.slice(0, 2), 16);
  const g = parseInt(clean.slice(2, 4), 16);
  const b = parseInt(clean.slice(4, 6), 16);
  const [h, s, l] = rgbToHsl(r, g, b);
  return `${Math.round(h)} ${Math.round(s * 100)}% ${Math.round(l * 100)}%`;
}

/** Reads the uploaded logo and suggests a brand palette from its dominant colours. */
export function brandFromImage(dataUrl) {
  return new Promise((resolve) => {
    const img = new Image();
    img.onload = () => {
      try {
        const size = 48;
        const canvas = document.createElement("canvas");
        canvas.width = size;
        canvas.height = size;
        const ctx = canvas.getContext("2d");
        ctx.drawImage(img, 0, 0, size, size);
        const { data } = ctx.getImageData(0, 0, size, size);
        let best = null;
        for (let i = 0; i < data.length; i += 4) {
          const r = data[i];
          const g = data[i + 1];
          const b = data[i + 2];
          const a = data[i + 3];
          if (a < 140) continue;
          const [h, s, l] = rgbToHsl(r, g, b);
          if (l < 0.14 || l > 0.9 || s < 0.14) continue;
          if (!best || s * (1 - Math.abs(l - 0.5)) > best.score) {
            best = { h, s, l, score: s * (1 - Math.abs(l - 0.5)) };
          }
        }
        const base = best || { h: 38, s: 0.88, l: 0.55 };
        const sat = Math.max(0.62, Math.min(0.95, base.s));
        resolve({
          primary: hslToHex(base.h, sat, Math.max(0.44, Math.min(0.6, base.l))),
          secondary: hslToHex(base.h, sat * 0.55, 0.3),
          accent: hslToHex((base.h + 158) % 360, Math.min(0.9, sat), 0.58),
          bg: hslToHex(base.h, 0.22, 0.07),
          button: hslToHex(base.h, sat, 0.54),
          text: "#f6f1e7",
        });
      } catch (e) {
        resolve(null);
      }
    };
    img.onerror = () => resolve(null);
    img.src = dataUrl;
  });
}

export function download(filename, text) {
  const blob = new Blob([text], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}