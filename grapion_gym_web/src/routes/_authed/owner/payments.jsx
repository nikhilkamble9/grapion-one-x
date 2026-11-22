import { useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { Check, Plus, X } from "lucide-react";
import { OwnerShell } from "@/components/grapion/shells";
import { useRoleSession, useStore } from "@/lib/grapion/useGrapion";
import { PageHead, Panel, Pill, StatGrid, Empty } from "@/components/grapion/ui";
import { DataTable } from "@/components/grapion/DataTable";
import { FormModal } from "@/components/grapion/FormModal";
import { Button } from "@/components/ui/button";
import { useToast } from "@/components/ui/use-toast";
import { fmtDate, money, todayISO } from "@/lib/grapion/util";
import {
  cancelPayment,
  memberById,
  planById,
  recordPayment,
  verifyPayment,
} from "@/lib/grapion/repo";

export const Route = createFileRoute("/_authed/owner/payments")({
  component: PaymentsPage,
  head: () => ({ meta: [{ title: "Payments · GRAPION GYM" }] }),
});

const toneFor = (status) => ({ verified: "green", pending: "amber", cancelled: "red" }[status] || "gray");

function PaymentsPage() {
  const session = useRoleSession();
  const db = useStore();
  const { toast } = useToast();
  const gymId = session?.gymId;
  const today = todayISO();
  const [filter, setFilter] = useState("all");
  const [recording, setRecording] = useState(false);

  const all = db.payments.filter((p) => p.gymId === gymId);
  const rows = all
    .filter((p) => filter === "all" || p.status === filter)
    .sort((a, b) => String(b.createdAt || b.date).localeCompare(String(a.createdAt || a.date)));
  const pendingRows = all.filter((p) => p.status === "pending");
  const members = db.gymMembers.filter((m) => m.gymId === gymId);
  const plans = db.membershipPlans.filter((p) => p.gymId === gymId);

  const verifiedTotal = all
    .filter((p) => p.status === "verified")
    .reduce((s, p) => s + Number(p.amount || 0), 0);
  const pendingTotal = pendingRows.reduce((s, p) => s + Number(p.amount || 0), 0);

  const act = (fn, id, label) => {
    try {
      fn(id, session.name);
      toast({ title: label });
    } catch (err) {
      toast({ title: "Action failed", description: err.message });
    }
  };

  return (
    <OwnerShell>
      <PageHead
        eyebrow="Collections"
        title="Payment management"
        description="Cash, UPI and manual payments. Only verified amounts count towards revenue."
        actions={
          <Button size="sm" onClick={() => setRecording(true)}>
            <Plus className="mr-1.5 h-3.5 w-3.5" /> Record payment
          </Button>
        }
      />

      <StatGrid
        items={[
          { label: "Verified collected", value: money(verifiedTotal), tone: "green" },
          { label: "Pending verification", value: money(pendingTotal), tone: "amber", hint: `${pendingRows.length} submissions` },
          {
            label: "Collected today",
            value: money(
              all.filter((p) => p.status === "verified" && String(p.date).slice(0, 10) === today)
                .reduce((s, p) => s + Number(p.amount || 0), 0),
            ),
          },
          {
            label: "Collected this month",
            value: money(
              all.filter((p) => p.status === "verified" && String(p.date).slice(0, 7) === today.slice(0, 7))
                .reduce((s, p) => s + Number(p.amount || 0), 0),
            ),
            tone: "primary",
          },
        ]}
      />

      {pendingRows.length > 0 && (
        <Panel className="mt-4" title="Awaiting your verification" subtitle="Member-submitted UPI confirmations">
          <ul className="space-y-3">
            {pendingRows.map((row) => {
              const member = memberById(db, row.memberId);
              return (
                <li key={row.id} className="flex flex-wrap items-center gap-3 rounded-xl border border-primary/25 bg-primary/5 px-3 py-3">
                  <div className="min-w-0 flex-1">
                    <p className="text-[12.5px] font-medium">
                      {member?.name} · {money(row.amount)}
                    </p>
                    <p className="text-[11px] text-muted-foreground">
                      {planById(db, row.planId)?.name || row.type} · {row.method.toUpperCase()} · {fmtDate(row.date)}
                      {row.notes ? ` · ${row.notes}` : ""}
                    </p>
                  </div>
                  <Button size="sm" onClick={() => act(verifyPayment, row.id, "Payment verified & renewal applied")}>
                    <Check className="mr-1.5 h-3.5 w-3.5" /> Verify
                  </Button>
                  <Button size="sm" variant="outline" onClick={() => act(cancelPayment, row.id, "Payment cancelled")}>
                    <X className="mr-1.5 h-3.5 w-3.5" /> Cancel
                  </Button>
                </li>
              );
            })}
          </ul>
        </Panel>
      )}

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
          empty="No payments recorded yet"
          rows={rows}
          columns={[
            { key: "date", label: "Date", render: (row) => fmtDate(row.date) },
            {
              key: "member",
              label: "Member",
              render: (row) => memberById(db, row.memberId)?.name || "—",
            },
            {
              key: "plan",
              label: "For",
              render: (row) => planById(db, row.planId)?.name || (row.type === "renewal" ? "Renewal" : "Membership"),
            },
            { key: "method", label: "Method", render: (row) => <span className="uppercase">{row.method}</span> },
            {
              key: "amount",
              label: "Amount",
              align: "right",
              render: (row) => <span className="font-medium">{money(row.amount)}</span>,
            },
            { key: "status", label: "Status", render: (row) => <Pill tone={toneFor(row.status)}>{row.status}</Pill> },
            {
              key: "actions",
              label: "",
              align: "right",
              render: (row) => (
                <div className="flex justify-end gap-1">
                  {row.status === "pending" && (
                    <Button size="icon" variant="ghost" title="Verify" onClick={() => act(verifyPayment, row.id, "Payment verified")}>
                      <Check className="h-3.5 w-3.5 text-emerald-400" />
                    </Button>
                  )}
                  {row.status !== "cancelled" && (
                    <Button size="icon" variant="ghost" title="Cancel" onClick={() => act(cancelPayment, row.id, "Payment cancelled")}>
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
        open={recording}
        onOpenChange={setRecording}
        title="Record a payment"
        fields={[
          {
            name: "memberId",
            label: "Member",
            type: "select",
            options: members.map((m) => ({ value: m.id, label: `${m.name} · ${m.code}` })),
          },
          { name: "amount", label: "Amount (₹)", type: "number", required: true },
          {
            name: "method",
            label: "Method",
            type: "select",
            options: [
              { value: "cash", label: "Cash" },
              { value: "upi", label: "UPI" },
              { value: "other", label: "Other manual payment" },
            ],
          },
          {
            name: "planId",
            label: "Against plan",
            type: "select",
            options: plans.map((p) => ({ value: p.id, label: `${p.name} · ${money(p.price)}` })),
          },
          {
            name: "status",
            label: "Mark as",
            type: "select",
            options: [
              { value: "verified", label: "Verified (money received)" },
              { value: "pending", label: "Pending" },
            ],
          },
          { name: "notes", label: "Notes", placeholder: "Reference, remarks…" },
        ]}
        submitLabel="Save payment"
        onSubmit={(values) => {
          recordPayment({ ...values, by: session.name });
          toast({ title: "Payment recorded" });
        }}
      />
    </OwnerShell>
  );
}