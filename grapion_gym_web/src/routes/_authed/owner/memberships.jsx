import { useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { Ban, Plus, RefreshCw } from "lucide-react";
import { OwnerShell } from "@/components/grapion/shells";
import { useRoleSession, useStore } from "@/lib/grapion/useGrapion";
import { PageHead, Panel, Pill, StatGrid } from "@/components/grapion/ui";
import { DataTable } from "@/components/grapion/DataTable";
import { FormModal } from "@/components/grapion/FormModal";
import { Button } from "@/components/ui/button";
import { useToast } from "@/components/ui/use-toast";
import { fmtDate, membershipStatus, money, todayISO } from "@/lib/grapion/util";
import {
  assignMembership,
  batchById,
  memberById,
  planById,
  renewMembership,
  updateMembership,
  verifiedPaid,
} from "@/lib/grapion/repo";

export const Route = createFileRoute("/_authed/owner/memberships")({
  component: MembershipsPage,
  head: () => ({ meta: [{ title: "Memberships · GRAPION GYM" }] }),
});

function MembershipsPage() {
  const session = useRoleSession();
  const db = useStore();
  const { toast } = useToast();
  const gymId = session?.gymId;
  const [assigning, setAssigning] = useState(false);
  const [renewing, setRenewing] = useState(null);

  const members = db.gymMembers.filter((m) => m.gymId === gymId && m.status === "active");
  const plans = db.membershipPlans.filter((p) => p.gymId === gymId && p.status === "active");
  const warn = db.adminSettings.expiryWarningDays || 7;
  const rows = db.memberships
    .filter((m) => m.gymId === gymId)
    .sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt)));

  const planOptions = plans.map((p) => ({ value: p.id, label: `${p.name} · ${money(p.price)}` }));
  const memberOptions = members.map((m) => ({ value: m.id, label: `${m.name} · ${m.code}` }));

  const activeCount = rows.filter((m) => membershipStatus(m.expiryDate, warn).key === "active").length;
  const expiringCount = rows.filter((m) => membershipStatus(m.expiryDate, warn).key === "expiring").length;
  const expiredCount = rows.filter((m) => membershipStatus(m.expiryDate, warn).key === "expired").length;

  return (
    <OwnerShell>
      <PageHead
        eyebrow="Memberships"
        title="Membership management"
        description="Every membership period is kept as history — renewals never overwrite old records."
        actions={
          <Button size="sm" onClick={() => setAssigning(true)}>
            <Plus className="mr-1.5 h-3.5 w-3.5" /> Assign plan
          </Button>
        }
      />

      <StatGrid
        cols={4}
        items={[
          { label: "Active periods", value: activeCount, tone: "green" },
          { label: "Expiring soon", value: expiringCount, tone: "amber" },
          { label: "Expired", value: expiredCount, tone: "red" },
          { label: "Total records", value: rows.length },
        ]}
      />

      <Panel className="mt-4" title={`${rows.length} membership records`}>
        <DataTable
          empty="No memberships yet"
          emptyHint="Assign a plan to a member to create the first membership."
          rows={rows}
          columns={[
            {
              key: "member",
              label: "Member",
              render: (row) => {
                const member = memberById(db, row.memberId);
                return (
                  <div>
                    <p className="font-medium">{member?.name || "—"}</p>
                    <p className="text-[10.5px] text-muted-foreground">{member?.code}</p>
                  </div>
                );
              },
            },
            {
              key: "plan",
              label: "Plan",
              render: (row) => planById(db, row.planId)?.name || "—",
            },
            {
              key: "batch",
              label: "Batch",
              render: (row) => batchById(db, row.batchId)?.name || "—",
            },
            { key: "start", label: "Start", render: (row) => fmtDate(row.startDate) },
            { key: "expiry", label: "Expiry", render: (row) => fmtDate(row.expiryDate) },
            {
              key: "payment",
              label: "Paid",
              render: (row) => {
                const paid = verifiedPaid(db, row.id);
                return (
                  <div>
                    <p>{money(paid)} / {money(row.totalAmount)}</p>
                    <p className="text-[10.5px] text-muted-foreground">
                      {paid >= Number(row.totalAmount) ? "Fully paid" : `${money(Number(row.totalAmount) - paid)} pending`}
                    </p>
                  </div>
                );
              },
            },
            {
              key: "status",
              label: "Status",
              render: (row) => {
                if (row.status === "cancelled") return <Pill tone="gray">cancelled</Pill>;
                const st = membershipStatus(row.expiryDate, warn);
                return <Pill tone={st.tone}>{st.label}</Pill>;
              },
            },
            {
              key: "actions",
              label: "",
              align: "right",
              render: (row) => (
                <div className="flex justify-end gap-1">
                  <Button size="icon" variant="ghost" title="Renew" onClick={() => setRenewing(memberById(db, row.memberId))}>
                    <RefreshCw className="h-3.5 w-3.5" />
                  </Button>
                  <Button
                    size="icon"
                    variant="ghost"
                    title="Cancel membership"
                    onClick={() => {
                      if (!window.confirm("Cancel this membership period? The record stays in history.")) return;
                      updateMembership(row.id, { status: "cancelled" });
                      toast({ title: "Membership cancelled" });
                    }}
                  >
                    <Ban className="h-3.5 w-3.5 text-red-400" />
                  </Button>
                </div>
              ),
            },
          ]}
        />
      </Panel>

      <FormModal
        open={assigning}
        onOpenChange={setAssigning}
        title="Assign a membership"
        description="Expiry is calculated with real calendar months from the start date."
        fields={[
          { name: "memberId", label: "Member", type: "select", options: memberOptions },
          { name: "planId", label: "Plan", type: "select", options: planOptions },
          { name: "startDate", label: "Start date", type: "date" },
          { name: "paidAmount", label: "Amount paid now", type: "number" },
          {
            name: "method",
            label: "Payment method",
            type: "select",
            options: [
              { value: "cash", label: "Cash" },
              { value: "upi", label: "UPI" },
              { value: "other", label: "Other" },
            ],
          },
        ]}
        submitLabel="Assign membership"
        onSubmit={(values) => {
          const ms = assignMembership({ ...values, joiningDate: values.startDate || todayISO(), by: session.name });
          toast({ title: "Membership assigned", description: `Expires ${fmtDate(ms.expiryDate)}` });
        }}
      />

      <FormModal
        open={Boolean(renewing)}
        onOpenChange={(open) => !open && setRenewing(null)}
        title={`Renew — ${renewing?.name || ""}`}
        fields={[
          { name: "planId", label: "Plan", type: "select", options: planOptions },
          { name: "amount", label: "Amount collected", type: "number" },
          {
            name: "method",
            label: "Payment method",
            type: "select",
            options: [
              { value: "cash", label: "Cash" },
              { value: "upi", label: "UPI" },
              { value: "other", label: "Other" },
            ],
          },
          { name: "notes", label: "Notes" },
        ]}
        submitLabel="Renew membership"
        onSubmit={(values) => {
          const ms = renewMembership({ ...values, memberId: renewing.id, by: session.name });
          toast({ title: "Renewed", description: `Valid until ${fmtDate(ms.expiryDate)}` });
        }}
      />
    </OwnerShell>
  );
}