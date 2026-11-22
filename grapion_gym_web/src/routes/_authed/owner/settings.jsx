import { useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { KeyRound, LogOut, Save } from "lucide-react";
import { OwnerShell } from "@/components/grapion/shells";
import { useRoleSession, useStore } from "@/lib/grapion/useGrapion";
import { PageHead, Panel, Field, KeyValue, Pill } from "@/components/grapion/ui";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Switch } from "@/components/ui/switch";
import { useToast } from "@/components/ui/use-toast";
import { fmtDate, subscriptionStatus } from "@/lib/grapion/util";
import { findGym, logout, ownerOf, saveOwner, subscriptionOf, updateGym } from "@/lib/grapion/repo";

export const Route = createFileRoute("/_authed/owner/settings")({
  component: OwnerSettings,
  head: () => ({ meta: [{ title: "Settings · GRAPION GYM" }] }),
});

function OwnerSettings() {
  const session = useRoleSession();
  const db = useStore();
  const { toast } = useToast();
  const gym = findGym(db, session?.gymId);
  const owner = ownerOf(db, session?.gymId);
  const sub = subscriptionOf(db, session?.gymId);
  const status = subscriptionStatus(sub?.expiryDate, gym?.status);
  const [warnDays, setWarnDays] = useState(String(gym?.expiryWarningDays || db.adminSettings.expiryWarningDays || 7));
  const remindersOn = gym?.remindersEnabled !== false;
  const [password, setPassword] = useState("");

  if (!gym || !owner) return null;

  return (
    <OwnerShell>
      <PageHead eyebrow="Settings" title="Gym settings" description="Workspace preferences and your owner account." />

      <div className="grid gap-4 lg:grid-cols-2">
        <Panel title="Membership reminders" subtitle="Automatic heads-up before a member's plan lapses">
          <div className="flex items-center justify-between gap-3 rounded-xl border border-border/70 px-3 py-3">
            <div className="min-w-0">
              <p className="text-[12.5px] font-semibold">Automatic member reminders</p>
              <p className="mt-0.5 text-[11px] leading-relaxed text-muted-foreground">
                Sent to each member's inbox and email at {Number(warnDays) || 7} days before expiry, then
                again at 3 days, 1 day, and on the day it lapses.
              </p>
            </div>
            <Switch
              checked={remindersOn}
              onCheckedChange={(value) => {
                updateGym(gym.id, { remindersEnabled: value });
                toast({ title: value ? "Reminders switched on" : "Reminders switched off" });
              }}
            />
          </div>

          <div className="mt-4 flex items-end gap-3">
            <Field label="First reminder (days before expiry)" className="flex-1">
              <Input type="number" value={warnDays} onChange={(e) => setWarnDays(e.target.value)} />
            </Field>
            <Button
              onClick={() => {
                updateGym(gym.id, { expiryWarningDays: Number(warnDays) || 7 });
                toast({ title: "Reminder timing saved" });
              }}
            >
              <Save className="mr-1.5 h-3.5 w-3.5" /> Save
            </Button>
          </div>
          <p className="mt-3 text-[11px] leading-relaxed text-muted-foreground">
            Members are also flagged as expiring at this threshold, and each reminder is delivered once
            per stage — never repeated. Reminders generate the next time this workspace is opened.
          </p>
        </Panel>

        <Panel title="Owner account">
          <KeyValue label="Name" value={owner.name} />
          <KeyValue label="Sign-in email" value={owner.email} />
          <div className="mt-4 flex items-end gap-3">
            <Field label="New password" className="flex-1">
              <Input
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="At least 6 characters"
              />
            </Field>
            <Button
              variant="outline"
              onClick={() => {
                if (password.trim().length < 6) {
                  toast({ title: "Password too short", description: "Use at least 6 characters." });
                  return;
                }
                saveOwner({ ...owner, password });
                setPassword("");
                toast({ title: "Password updated" });
              }}
            >
              <KeyRound className="mr-1.5 h-3.5 w-3.5" /> Change
            </Button>
          </div>
        </Panel>

        <Panel title="Grapion subscription" subtitle="Billed by Grapion Digital — not a member payment">
          <div className="flex items-center justify-between">
            <div>
              <p className="font-heading text-[14px] font-semibold capitalize">
                {sub?.cycle || "—"} subscription
              </p>
              <p className="mt-1 text-[11.5px] text-muted-foreground">
                {fmtDate(sub?.startDate)} → {fmtDate(sub?.expiryDate)}
              </p>
            </div>
            <Pill tone={status.tone}>{status.label}</Pill>
          </div>
          <div className="mt-4 grid gap-2 sm:grid-cols-2">
            <KeyValue label="Price" value={`₹${Number(sub?.price || 0).toLocaleString("en-IN")}`} />
            <KeyValue label="Days remaining" value={String(Math.max(0, status.days))} />
          </div>
          <p className="mt-3 text-[11px] text-muted-foreground">
            Contact Grapion Digital to renew. When it expires, gym features pause until renewal.
          </p>
        </Panel>

        <Panel title="Session">
          <p className="text-[12px] leading-relaxed text-muted-foreground">
            You are signed in as {owner.name}. Signing out clears this device's session; data stays
            in the browser until you reset it from the admin console.
          </p>
          <Button
            variant="outline"
            className="mt-4 text-red-300"
            onClick={() => {
              logout();
              window.location.href = "/";
            }}
          >
            <LogOut className="mr-1.5 h-3.5 w-3.5" /> Log out
          </Button>
        </Panel>
      </div>
    </OwnerShell>
  );
}