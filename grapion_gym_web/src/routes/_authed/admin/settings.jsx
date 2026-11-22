import { useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { DatabaseBackup, Download, RotateCcw, Trash2, Upload } from "lucide-react";
import { AdminShell } from "@/components/grapion/shells";
import { useStore } from "@/lib/grapion/useGrapion";
import { PageHead, Panel, Pill } from "@/components/grapion/ui";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { useToast } from "@/components/ui/use-toast";
import { download, fmtDate, money, todayISO } from "@/lib/grapion/util";
import { storageSize } from "@/lib/grapion/store";
import {
  clearDemoData,
  exportBackupText,
  importBackup,
  resetAllData,
  saveSettings,
  seedDemoData,
} from "@/lib/grapion/repo";

export const Route = createFileRoute("/_authed/admin/settings")({
  component: AdminSettings,
  head: () => ({ meta: [{ title: "Settings · GRAPION GYM" }] }),
});

function AdminSettings() {
  const db = useStore();
  const { toast } = useToast();
  const [form, setForm] = useState({
    company: db.adminSettings.company,
    expiryWarningDays: String(db.adminSettings.expiryWarningDays),
    monthly: String(db.adminSettings.plans.monthly),
    quarterly: String(db.adminSettings.plans.quarterly),
    halfYearly: String(db.adminSettings.plans.halfYearly),
    yearly: String(db.adminSettings.plans.yearly),
  });
  const size = storageSize();
  const demoOwner = db.gymOwners.find((o) => o.isDemo);
  const demoMember = db.gymMembers.find((m) => m.isDemo && m.status === "active");

  const save = () => {
    saveSettings({
      company: form.company,
      expiryWarningDays: Number(form.expiryWarningDays) || 7,
      plans: {
        monthly: Number(form.monthly) || 0,
        quarterly: Number(form.quarterly) || 0,
        halfYearly: Number(form.halfYearly) || 0,
        yearly: Number(form.yearly) || 0,
      },
    });
    toast({ title: "Settings saved" });
  };

  const run = (fn, message) => {
    try {
      fn();
      toast({ title: message });
    } catch (err) {
      toast({ title: "Action failed", description: err.message });
    }
  };

  return (
    <AdminShell>
      <PageHead
        eyebrow="Configuration"
        title="Platform settings"
        description="Subscription pricing, warnings and the local data store."
        actions={<Button size="sm" onClick={save}>Save settings</Button>}
      />

      <div className="grid gap-4 lg:grid-cols-2">
        <Panel title="Subscription pricing" subtitle="Default prices used when onboarding a gym">
          <div className="grid gap-4 sm:grid-cols-2">
            {[
              ["monthly", "Monthly price"],
              ["quarterly", "Quarterly price"],
              ["halfYearly", "Half-yearly price"],
              ["yearly", "Yearly price"],
            ].map(([key, label]) => (
              <label key={key} className="block">
                <span className="mb-1.5 block text-[11.5px] text-muted-foreground">{label}</span>
                <Input
                  type="number"
                  value={form[key]}
                  onChange={(e) => setForm({ ...form, [key]: e.target.value })}
                />
              </label>
            ))}
            <label className="block">
              <span className="mb-1.5 block text-[11.5px] text-muted-foreground">Company name</span>
              <Input value={form.company} onChange={(e) => setForm({ ...form, company: e.target.value })} />
            </label>
            <label className="block">
              <span className="mb-1.5 block text-[11.5px] text-muted-foreground">
                Expiry warning (days)
              </span>
              <Input
                type="number"
                value={form.expiryWarningDays}
                onChange={(e) => setForm({ ...form, expiryWarningDays: e.target.value })}
              />
            </label>
          </div>
        </Panel>

        <Panel title="Data & backup" subtitle={`Local store · ${size} KB used`}>
          <div className="space-y-3">
            <div className="flex flex-wrap gap-2">
              <Button
                variant="outline"
                onClick={() =>
                  run(
                    () => download(`grapion-gym-backup-${todayISO()}.json`, exportBackupText()),
                    "Backup downloaded",
                  )
                }
              >
                <Download className="mr-1.5 h-3.5 w-3.5" /> Export backup
              </Button>
              <label className="inline-flex cursor-pointer items-center gap-1.5 rounded-md border border-border px-3 py-2 text-[12px] font-medium hover:bg-accent">
                <Upload className="h-3.5 w-3.5" /> Import backup
                <input
                  type="file"
                  accept="application/json"
                  className="hidden"
                  onChange={async (event) => {
                    const file = event.target.files?.[0];
                    if (!file) return;
                    try {
                      importBackup(await file.text());
                      toast({ title: "Backup restored" });
                    } catch (err) {
                      toast({ title: "Import failed", description: err.message });
                    }
                    event.target.value = "";
                  }}
                />
              </label>
            </div>

            <div className="flex flex-wrap gap-2 border-t border-border pt-3">
              <Button variant="outline" onClick={() => run(seedDemoData, "Demo gym loaded")}>
                <DatabaseBackup className="mr-1.5 h-3.5 w-3.5" /> Load demo data
              </Button>
              <Button variant="outline" onClick={() => run(clearDemoData, "Demo data removed")}>
                <Trash2 className="mr-1.5 h-3.5 w-3.5" /> Remove demo data
              </Button>
              <Button
                variant="outline"
                className="text-red-300"
                onClick={() => {
                  if (!window.confirm("Erase every record in this browser? This cannot be undone.")) return;
                  run(resetAllData, "All data reset");
                }}
              >
                <RotateCcw className="mr-1.5 h-3.5 w-3.5" /> Reset all data
              </Button>
            </div>

            <p className="text-[11px] leading-relaxed text-muted-foreground">
              Data lives in this browser only. Photos are downscaled before saving so the store stays
              small; export a backup before clearing browser data.
            </p>
          </div>
        </Panel>
      </div>

      <Panel className="mt-4" title="Demo accounts" subtitle="For local walkthroughs only">
        {demoOwner || demoMember ? (
          <div className="grid gap-4 sm:grid-cols-2">
            {demoOwner && (
              <div className="rounded-xl border border-border p-3">
                <Pill tone="primary">Gym owner</Pill>
                <p className="mt-2 text-[12.5px] font-medium">{demoOwner.name}</p>
                <p className="text-[11.5px] text-muted-foreground">
                  {demoOwner.email} · {demoOwner.password}
                </p>
                <p className="mt-1 text-[10.5px] text-muted-foreground/80">
                  Subscription valid until {fmtDate(db.gymSubscriptions.find((s) => s.gymId === demoOwner.gymId)?.expiryDate)}
                </p>
              </div>
            )}
            {demoMember && (
              <div className="rounded-xl border border-border p-3">
                <Pill tone="blue">Gym member</Pill>
                <p className="mt-2 text-[12.5px] font-medium">{demoMember.name}</p>
                <p className="text-[11.5px] text-muted-foreground">
                  {demoMember.code} · {demoMember.password}
                </p>
              </div>
            )}
          </div>
        ) : (
          <p className="text-[12px] text-muted-foreground">
            No demo data loaded. Use “Load demo data” to add the Nishchay Fitness sample gym.
          </p>
        )}
      </Panel>

      <Panel className="mt-4" title="Platform totals">
        <div className="grid gap-4 sm:grid-cols-4">
          <div>
            <p className="gp-eyebrow">Gyms</p>
            <p className="gp-num mt-1 font-heading text-xl font-semibold">{db.gyms.length}</p>
          </div>
          <div>
            <p className="gp-eyebrow">Owners</p>
            <p className="gp-num mt-1 font-heading text-xl font-semibold">{db.gymOwners.length}</p>
          </div>
          <div>
            <p className="gp-eyebrow">Members</p>
            <p className="gp-num mt-1 font-heading text-xl font-semibold">{db.gymMembers.length}</p>
          </div>
          <div>
            <p className="gp-eyebrow">Recorded revenue</p>
            <p className="gp-num mt-1 font-heading text-xl font-semibold">
              {money(db.subscriptionPayments.filter((p) => p.status === "verified").reduce((s, p) => s + Number(p.amount || 0), 0))}
            </p>
          </div>
        </div>
      </Panel>
    </AdminShell>
  );
}