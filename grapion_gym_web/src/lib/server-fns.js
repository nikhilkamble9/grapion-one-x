import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { requireUser } from "@/lib/auth-middleware";

export const getServerInfo = createServerFn({ method: "GET" }).handler(async () => ({
  renderedAt: new Date().toISOString(),
}));

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

const esc = (value) =>
  String(value).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

const ReminderInput = z.object({
  to: z.string().trim().max(160).regex(EMAIL, "Enter a valid email address"),
  memberName: z.string().trim().min(1).max(80),
  gymName: z.string().trim().min(1).max(80),
  planName: z.string().trim().max(80).optional(),
  expiryDate: z.string().trim().min(1).max(24),
  daysLeft: z.number().int().min(-400).max(400),
});

/**
 * Sends one membership-expiry reminder email. The whole body is built here from
 * bounded inputs, so the caller can never supply free-form content.
 */
export const sendExpiryReminderEmail = createServerFn({ method: "POST" })
  .middleware([requireUser])
  .validator(ReminderInput)
  .handler(async ({ data, context }) => {
    const days = data.daysLeft;
    const plural = days === 1 ? "" : "s";
    const subject =
      days < 0
        ? `Your ${data.gymName} membership has expired`
        : `Your ${data.gymName} membership expires in ${days} day${plural}`;
    const line =
      days < 0
        ? `Your membership ended on ${data.expiryDate}.`
        : `Your membership runs out on ${data.expiryDate} — ${days} day${plural} to go.`;

    const text = [
      `Hi ${data.memberName},`,
      "",
      line,
      data.planName ? `Current plan: ${data.planName}` : null,
      "Sign in to your member dashboard to renew and keep your access and visit history.",
      "",
      `${data.gymName} · via Grapion Gym`,
    ]
      .filter((part) => part !== null)
      .join("\n");

    const body = `<!doctype html><html><body style="margin:0;padding:24px;background:#f4efe4;font-family:Inter,Helvetica,Arial,sans-serif;color:#141317">
  <div style="max-width:520px;margin:0 auto;background:#ffffff;border:1px solid #e6dfd2;border-radius:16px;padding:28px">
    <p style="margin:0 0 10px;font-size:11px;letter-spacing:0.18em;text-transform:uppercase;color:#8a8170">${esc(data.gymName)}</p>
    <h1 style="margin:0 0 14px;font-size:20px;line-height:1.35;font-weight:600">${days < 0 ? "Your membership has expired" : "Your membership is expiring"}</h1>
    <p style="margin:0 0 12px;font-size:14px;line-height:1.6">Hi ${esc(data.memberName)},</p>
    <p style="margin:0 0 12px;font-size:14px;line-height:1.6">${esc(line)}</p>
    ${data.planName ? `<p style="margin:0 0 12px;font-size:14px;line-height:1.6">Current plan: <strong>${esc(data.planName)}</strong></p>` : ""}
    <p style="margin:0 0 20px;font-size:14px;line-height:1.6">Sign in to your member dashboard to renew and keep your access and visit history.</p>
    <p style="margin:0;font-size:11px;line-height:1.6;color:#8a8170">Sent by ${esc(data.gymName)} on Grapion Gym.</p>
  </div>
</body></html>`;

    const base44 = context.getBase44();
    await base44.asServiceRole.integrations.Core.SendEmail({
      to: data.to,
      subject,
      body,
      text,
      from_name: data.gymName,
    });
    return { ok: true, to: data.to };
  });