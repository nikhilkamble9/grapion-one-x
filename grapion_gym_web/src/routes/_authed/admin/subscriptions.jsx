import { useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { Power, RefreshCw } from "lucide-react";
import { AdminShell } from "@/components/grapion/shells";
import { useStore } from "@/lib/grapion/useGrapion";
import { PageHead, Panel, Pill, Empty } from "@/components/grapion/ui";
import { DataTable } from "@/components/grapion/DataTable";
import { FormModal } from "@/components/grapion/FormModal";
import { Button } from "@/components/ui/button";
import { useToast } from "@/components/ui/use-toast";
import { fmtDate, fmtDateTime, money, subscriptionStatus } from "@/lib/grapion/util";
import { renewGymSubscription, setGymStatus, subscriptionOf } from "@/lib/grapion/repo";

export const Route = createFileRoute("/_authed/admin/subscriptions")({
  component: SubscriptionsPage,
  head: () => ({ meta: [{ title: "Subscriptions · GRAPION GYM" }] }),
});

const cycleOptions = [
  { value: "monthly", label: "Monthly" },
  { value: "quarterly", label: "Quarterly" },
  { value: "halfYearly", label: "Half-yearly" },
  { value: "yearly", label: "Yearly" },
];

function SubscriptionsPage() {
  const db = useStore();
  const { toast } = useToast();
  const [renewing, setRenewing] = useState(null);

  const history = db.gyms
    .flatMap((gym) =>
      (subscriptionOf(db, gym.id)?.history || []).map((entry) => ({
        id: `${gym.id}-${entry.at}-${entry.startDate}`,
        gymName: gym.name,
        ...entry,
      })),
    )
    .sort((a, b) => String(b.at).localeCompare(String(a.at)))
    .slice(0, 12);

  return (
    <AdminShell>
      <PageHead
        eyebrow="SaaS billing"
        title="Grapion subscriptions"
        description="What each gym pays Grapion Digital — separate from the memberships gym owners sell."
      />

      <Panel title={`${db.gyms.length} subscriptions`}>
        <DataTable
          empty="No gyms yet"
          rows={db.gyms}
          columns={[
            {
              key: "gym",
              label: "Gym",
              render: (row) => (
                <div>
                  <p className="font-medium">{row.name}</p>
                  <p className="text-[11px] text-muted-foreground">{row.city || "—"}</p>
                </div>
              ),
            },
            {
              key: "plan",
              label: "Plan",
              render: (row) => {
                const sub = subscriptionOf(db, row.id);
                return (
                  <div>
                    <p className="capitalize">{sub?.cycle || "—"}</p>
                    <p className="text-[11px] text-muted-foreground">{money(sub?.price || 0)}</p>
                  </div>
                );
              },
            },
            { key: "start", label: "Start", render: (row) => fmtDate(subscriptionOf(db, row.id)?.startDate) },
            { key: "expiry", label: "Expiry", render: (row) => fmtDate(subscriptionOf(db, row.id)?.expiryDate) },
            {
              key: "status",
              label: "Status",
              render: (row) => {
                const st = subscriptionStatus(subscriptionOf(db, row.id)?.expiryDate, row.status);
                return (
                  <div className="space-y-1">
                    <Pill tone={st.tone}>{st.label}</Pill>
                    <p className="text-[10.5px] text-muted-foreground">
                      {st.days >= 0 ? `${st.days} days remaining` : `${Math.abs(st.days)} days overdue`}
                    </p>
                  </div>
                );
              },
            },
            {
              key: "actions",
              label: "",
              align: "right",
              render: (row) => (
                <div className="flex justify-end gap-1">
                  <Button size="sm" variant="outline" onClick={() => setRenewing(row)}>
                    <RefreshCw className="mr-1.5 h-3 w-3" /> Renew
                  </Button>
                  <Button
                    size="icon"
                    variant="ghost"
                    title={row.status === "active" ? "Suspend gym" : "Activate gym"}
                    onClick={() => setGymStatus(row.id, row.status === "active" ? "suspended" : "active")}
                  >
                    <Power className="h-3.5 w-3.5" />
                  </Button>
                </div>
              ),
            },
          ]}
        />
      </Panel>

      <Panel className="mt-4" title="Renewal history" subtitle="Most recent subscription changes">
        {history.length ? (
          <ul className="space-y-3">
            {history.map((entry) => (
              <li key={entry.id} className="flex items-center justify-between gap-3 border-b border-border/60 pb-3 last:border-0 last:pb-0">
                <div>
                  <p className="text-[12.5px] font-medium">{entry.gymName}</p>
                  <p className="text-[11px] text-muted-foreground">
                    {fmtDate(entry.startDate)} → {fmtDate(entry.expiryDate)} · {entry.cycle}
                  </p>
                </div>
                <div className="text-right">
                  <p className="text-[12.5px] font-medium">{money(entry.amount)}</p>
                  <p className="text-[10.5px] text-muted-foreground">{fmtDateTime(entry.at)}</p>
                </div>
              </li>
            ))}
          </ul>
        ) : (
          <Empty title="No renewals recorded yet" />
        )}
      </Panel>

      <FormModal
        open={Boolean(renewing)}
        onOpenChange={(open) => !open && setRenewing(null)}
        title={`Renew ${renewing?.name || ""}`}
        description="Extends from the current expiry when it is still valid, otherwise from the start date."
        fields={[
          { name: "cycle", label: "Billing cycle", type: "select", options: cycleOptions },
          {
            name: "amount",
            label: "Amount collected",
            type: "number",
            value: String(renewing ? subscriptionOf(db, renewing.id)?.price || 0 : 0),
          },
          { name: "startDate", label: "Start date", type: "date" },
          { name: "note", label: "Note", placeholder: "UPI ref, cheque number…" },
        ]}
        initial={{
          cycle: renewing ? subscriptionOf(db, renewing.id)?.cycle : "monthly",
          amount: renewing ? String(subscriptionOf(db, renewing.id)?.price || "") : "",
        }}
        submitLabel="Renew subscription"
        onSubmit={(values) => {
          const res = renewGymSubscription({
            gymId: renewing.id,
            cycle: values.cycle,
            amount: values.amount,
            startDate: values.startDate,
            note: values.note,
          });
          toast({ title: "Subscription renewed", description: `Valid until ${res.expiryDate}` });
        }}
      />
    </AdminShell>
  );
}