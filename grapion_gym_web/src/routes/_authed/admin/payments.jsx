import { useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { Check, Plus, X } from "lucide-react";
import { AdminShell } from "@/components/grapion/shells";
import { useStore } from "@/lib/grapion/useGrapion";
import { PageHead, Panel, Pill, StatGrid } from "@/components/grapion/ui";
import { DataTable } from "@/components/grapion/DataTable";
import { FormModal } from "@/components/grapion/FormModal";
import { Button } from "@/components/ui/button";
import { useToast } from "@/components/ui/use-toast";
import { fmtDate, money } from "@/lib/grapion/util";
import { findGym, recordSubscriptionPayment, setSubscriptionPaymentStatus } from "@/lib/grapion/repo";

export const Route = createFileRoute("/_authed/admin/payments")({
  component: SubscriptionPayments,
  head: () => ({ meta: [{ title: "Subscription payments · GRAPION GYM" }] }),
});

const toneFor = (status) => ({ verified: "green", pending: "amber", cancelled: "red" }[status] || "gray");

function SubscriptionPayments() {
  const db = useStore();
  const { toast } = useToast();
  const [creating, setCreating] = useState(false);
  const [filter, setFilter] = useState("all");

  const rows = db.subscriptionPayments.filter((p) => filter === "all" || p.status === filter);
  const verified = db.subscriptionPayments
    .filter((p) => p.status === "verified")
    .reduce((s, p) => s + Number(p.amount || 0), 0);
  const pending = db.subscriptionPayments
    .filter((p) => p.status === "pending")
    .reduce((s, p) => s + Number(p.amount || 0), 0);

  return (
    <AdminShell>
      <PageHead
        eyebrow="Billing"
        title="Subscription payments"
        description="Payments from gym owners to Grapion Digital. Only verified amounts count as revenue."
        actions={
          <Button size="sm" onClick={() => setCreating(true)} disabled={!db.gyms.length}>
            <Plus className="mr-1.5 h-3.5 w-3.5" /> Record payment
          </Button>
        }
      />

      <StatGrid
        cols={3}
        items={[
          { label: "Verified collected", value: money(verified), tone: "green", hint: "Counted as revenue" },
          { label: "Pending review", value: money(pending), tone: "amber", hint: "Not counted yet" },
          { label: "Records", value: db.subscriptionPayments.length, hint: "All subscription payments" },
        ]}
      />

      <Panel
        className="mt-4"
        title={`${rows.length} payment records`}
        action={
          <select
            value={filter}
            onChange={(e) => setFilter(e.target.value)}
            className="h-9 rounded-md border border-input bg-transparent px-2 text-[12px]"
          >
            <option value="all">All</option>
            <option value="verified">Verified</option>
            <option value="pending">Pending</option>
            <option value="cancelled">Cancelled</option>
          </select>
        }
      >
        <DataTable
          empty="No subscription payments yet"
          rows={rows}
          columns={[
            { key: "date", label: "Date", render: (row) => fmtDate(row.date) },
            { key: "gym", label: "Gym", render: (row) => findGym(db, row.gymId)?.name || "—" },
            { key: "cycle", label: "Cycle", render: (row) => <span className="capitalize">{row.cycle}</span> },
            {
              key: "amount",
              label: "Amount",
              align: "right",
              render: (row) => <span className="font-medium">{money(row.amount)}</span>,
            },
            { key: "note", label: "Note", render: (row) => row.note || "—" },
            {
              key: "status",
              label: "Status",
              render: (row) => <Pill tone={toneFor(row.status)}>{row.status}</Pill>,
            },
            {
              key: "actions",
              label: "",
              align: "right",
              render: (row) => (
                <div className="flex justify-end gap-1">
                  {row.status !== "verified" && (
                    <Button
                      size="icon"
                      variant="ghost"
                      title="Mark verified"
                      onClick={() => {
                        setSubscriptionPaymentStatus(row.id, "verified");
                        toast({ title: "Payment verified" });
                      }}
                    >
                      <Check className="h-3.5 w-3.5 text-emerald-400" />
                    </Button>
                  )}
                  {row.status !== "cancelled" && (
                    <Button
                      size="icon"
                      variant="ghost"
                      title="Cancel payment"
                      onClick={() => {
                        setSubscriptionPaymentStatus(row.id, "cancelled");
                        toast({ title: "Payment cancelled" });
                      }}
                    >
                      <X className="h-3.5 w-3.5 text-red-400" />
                    </Button>
                  )}
                </div>
              ),
            },
          ]}
        />
      </Panel>

      <FormModal
        open={creating}
        onOpenChange={setCreating}
        title="Record subscription payment"
        description="Use this for money received outside the renewal flow."
        fields={[
          { name: "gymId", label: "Gym", type: "select", options: db.gyms.map((g) => ({ value: g.id, label: g.name })) },
          { name: "amount", label: "Amount", type: "number", required: true },
          {
            name: "cycle",
            label: "Billing cycle",
            type: "select",
            options: [
              { value: "monthly", label: "Monthly" },
              { value: "quarterly", label: "Quarterly" },
              { value: "halfYearly", label: "Half-yearly" },
              { value: "yearly", label: "Yearly" },
            ],
          },
          { name: "date", label: "Payment date", type: "date" },
          {
            name: "status",
            label: "Status",
            type: "select",
            options: [
              { value: "verified", label: "Verified" },
              { value: "pending", label: "Pending" },
            ],
          },
          { name: "note", label: "Note", placeholder: "Reference or remark" },
        ]}
        submitLabel="Save payment"
        onSubmit={(values) => {
          recordSubscriptionPayment(values);
          toast({ title: "Payment recorded" });
        }}
      />
    </AdminShell>
  );
}