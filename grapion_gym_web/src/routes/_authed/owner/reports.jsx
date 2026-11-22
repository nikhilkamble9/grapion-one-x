import { useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { OwnerShell } from "@/components/grapion/shells";
import { useRoleSession, useStore } from "@/lib/grapion/useGrapion";
import { PageHead, Panel, StatGrid, Pill, Empty } from "@/components/grapion/ui";
import { DataTable } from "@/components/grapion/DataTable";
import { BarsChart, TrendChart } from "@/components/grapion/Charts";
import { fmtDate, isoDate, money, todayISO } from "@/lib/grapion/util";
import { batchById, memberById, memberView, planById } from "@/lib/grapion/repo";

export const Route = createFileRoute("/_authed/owner/reports")({
  component: ReportsPage,
  head: () => ({ meta: [{ title: "Reports · GRAPION GYM" }] }),
});

function ReportsPage() {
  const session = useRoleSession();
  const db = useStore();
  const gymId = session?.gymId;
  const [range, setRange] = useState("month");
  const today = todayISO();

  const inRange = (dateValue) => {
    const date = String(dateValue).slice(0, 10);
    if (!date) return false;
    if (range === "all") return true;
    if (range === "month") return date.slice(0, 7) === today.slice(0, 7);
    const start = new Date();
    start.setDate(start.getDate() - 29);
    return date >= isoDate(start) && date <= today;
  };

  const attendance = db.attendance.filter((a) => a.gymId === gymId && inRange(a.date));
  const payments = db.payments.filter((p) => p.gymId === gymId && p.status === "verified" && inRange(p.date));
  const newMembers = db.gymMembers.filter((m) => m.gymId === gymId && inRange(m.joinedAt));
  const renewals = db.payments.filter(
    (p) => p.gymId === gymId && p.status === "verified" && p.type === "renewal" && inRange(p.date),
  );
  const views = db.gymMembers.filter((m) => m.gymId === gymId).map((m) => memberView(db, m.id));
  const expiring = views.filter((v) => v.status.key === "expiring");
  const expired = views.filter((v) => v.status.key === "expired");
  const pendingPayments = db.payments
    .filter((p) => p.gymId === gymId && p.status === "pending")
    .sort((a, b) => String(b.date).localeCompare(String(a.date)));

  const last14 = Array.from({ length: 14 }, (_, i) => {
    const d = new Date();
    d.setDate(d.getDate() - (13 - i));
    const key = isoDate(d);
    return {
      label: d.toLocaleDateString("en-IN", { day: "2-digit" }),
      value: db.attendance.filter((a) => a.gymId === gymId && a.date === key).length,
    };
  });

  const months = Array.from({ length: 6 }, (_, i) => {
    const d = new Date();
    d.setDate(1);
    d.setMonth(d.getMonth() - (5 - i));
    return d;
  });
  const revenueSeries = months.map((d) => {
    const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
    return {
      label: d.toLocaleDateString("en-IN", { month: "short" }),
      value: db.payments
        .filter((p) => p.gymId === gymId && p.status === "verified" && String(p.date).slice(0, 7) === key)
        .reduce((s, p) => s + Number(p.amount || 0), 0),
    };
  });
  const growthSeries = months.map((d) => {
    const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
    return {
      label: d.toLocaleDateString("en-IN", { month: "short" }),
      value: db.gymMembers.filter((m) => m.gymId === gymId && String(m.joinedAt).slice(0, 7) === key).length,
    };
  });

  const batches = db.batches.filter((b) => b.gymId === gymId);
  const batchRows = batches.map((batch) => {
    const members = db.gymMembers.filter((m) => m.gymId === gymId && m.batchId === batch.id);
    const visits = attendance.filter((a) => members.some((m) => m.id === a.memberId)).length;
    return {
      id: batch.id,
      name: batch.name,
      members: members.length,
      visits,
    };
  });

  return (
    <OwnerShell>
      <PageHead
        eyebrow="Reports"
        title="Reports & analytics"
        description="Built from your stored records — change the range to re-calculate everything."
        actions={
          <select
            value={range}
            onChange={(e) => setRange(e.target.value)}
            className="h-9 rounded-md border border-input bg-transparent px-2 text-[12px]"
          >
            <option value="month">This month</option>
            <option value="30">Last 30 days</option>
            <option value="all">All time</option>
          </select>
        }
      />

      <StatGrid
        items={[
          { label: "Visits", value: attendance.length, tone: "gray" },
          { label: "Unique members", value: new Set(attendance.map((a) => a.memberId)).size },
          { label: "Collections", value: money(payments.reduce((s, p) => s + Number(p.amount || 0), 0)), tone: "green" },
          { label: "New members", value: newMembers.length },
          { label: "Renewals", value: renewals.length, tone: "primary" },
          { label: "Expiring now", value: expiring.length, tone: "amber" },
          { label: "Expired", value: expired.length, tone: "red" },
          { label: "Pending payments", value: pendingPayments.length, tone: "amber" },
        ]}
      />

      <div className="mt-4 grid gap-4 lg:grid-cols-2">
        <Panel title="Daily attendance" subtitle="Last 14 days">
          <BarsChart data={last14} name="Visits" />
        </Panel>
        <Panel title="Monthly revenue" subtitle="Verified collections, last 6 months">
          <TrendChart data={revenueSeries} name="Revenue" />
        </Panel>
        <Panel title="Member growth" subtitle="New members per month">
          <BarsChart data={growthSeries} name="New members" />
        </Panel>
        <Panel title="Batch-wise attendance" subtitle="Visits in the selected range">
          <DataTable
            empty="No batches yet"
            rows={batchRows}
            columns={[
              { key: "name", label: "Batch", render: (row) => <span className="font-medium">{row.name}</span> },
              { key: "members", label: "Members", align: "right" },
              { key: "visits", label: "Visits", align: "right" },
            ]}
          />
        </Panel>
      </div>

      <Panel className="mt-4" title="Expiring memberships" subtitle="Nudge these members before they lapse">
        <DataTable
          empty="No memberships expiring"
          rows={expiring}
          columns={[
            { key: "member", label: "Member", render: (row) => row.member.name },
            { key: "plan", label: "Plan", render: (row) => row.plan?.name || "—" },
            { key: "expiry", label: "Expiry", render: (row) => fmtDate(row.membership.expiryDate) },
            {
              key: "remaining",
              label: "Remaining",
              render: (row) => <Pill tone={row.status.tone}>{row.status.label}</Pill>,
            },
            { key: "phone", label: "Mobile", render: (row) => row.member.phone || "—" },
          ]}
        />
      </Panel>

      <Panel className="mt-4" title="Pending payments">
        {pendingPayments.length ? (
          <ul className="space-y-2">
            {pendingPayments.map((p) => (
              <li key={p.id} className="flex items-center justify-between border-b border-border/60 pb-2 text-[12px] last:border-0 last:pb-0">
                <span>
                  {memberById(db, p.memberId)?.name} · {planById(db, p.planId)?.name || "Membership"}
                </span>
                <span className="font-medium">{money(p.amount)}</span>
              </li>
            ))}
          </ul>
        ) : (
          <Empty title="No pending payments" />
        )}
      </Panel>

      <Panel className="mt-4" title="Membership renewals">
        {renewals.length ? (
          <ul className="space-y-2">
            {renewals.map((p) => (
              <li key={p.id} className="flex items-center justify-between border-b border-border/60 pb-2 text-[12px] last:border-0 last:pb-0">
                <span>
                  {memberById(db, p.memberId)?.name} · {planById(db, p.planId)?.name || "Renewal"}
                </span>
                <span className="text-muted-foreground">{fmtDate(p.date)}</span>
                <span className="font-medium">{money(p.amount)}</span>
              </li>
            ))}
          </ul>
        ) : (
          <Empty title="No renewals in this range" />
        )}
      </Panel>
    </OwnerShell>
  );
}