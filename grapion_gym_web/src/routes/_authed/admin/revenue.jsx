import { createFileRoute } from "@tanstack/react-router";
import { AdminShell } from "@/components/grapion/shells";
import { useStore } from "@/lib/grapion/useGrapion";
import { PageHead, Panel, StatGrid, Empty } from "@/components/grapion/ui";
import { DataTable } from "@/components/grapion/DataTable";
import { TrendChart } from "@/components/grapion/Charts";
import { fmtDate, money, todayISO } from "@/lib/grapion/util";
import { platformStats, subscriptionOf } from "@/lib/grapion/repo";

export const Route = createFileRoute("/_authed/admin/revenue")({
  component: RevenuePage,
  head: () => ({ meta: [{ title: "Revenue · GRAPION GYM" }] }),
});

function lastMonths(count = 6) {
  return Array.from({ length: count }, (_, i) => {
    const d = new Date();
    d.setDate(1);
    d.setMonth(d.getMonth() - (count - 1 - i));
    return d;
  });
}

function RevenuePage() {
  const db = useStore();
  const stats = platformStats(db);
  const monthKey = todayISO().slice(0, 7);

  const series = lastMonths().map((d) => {
    const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
    const value = db.subscriptionPayments
      .filter((p) => p.status === "verified" && String(p.date).slice(0, 7) === key)
      .reduce((s, p) => s + Number(p.amount || 0), 0);
    return { label: d.toLocaleDateString("en-IN", { month: "short" }), value };
  });

  const gymRows = db.gyms.map((gym) => {
    const payments = db.subscriptionPayments.filter((p) => p.gymId === gym.id);
    const verified = payments
      .filter((p) => p.status === "verified")
      .reduce((s, p) => s + Number(p.amount || 0), 0);
    const pending = payments
      .filter((p) => p.status === "pending")
      .reduce((s, p) => s + Number(p.amount || 0), 0);
    const sub = subscriptionOf(db, gym.id);
    return {
      id: gym.id,
      name: gym.name,
      verified,
      pending,
      thisMonth: payments
        .filter((p) => p.status === "verified" && String(p.date).slice(0, 7) === monthKey)
        .reduce((s, p) => s + Number(p.amount || 0), 0),
      lastRenewal: sub?.history?.[sub.history.length - 1],
    };
  });

  return (
    <AdminShell>
      <PageHead
        eyebrow="Finance"
        title="Revenue"
        description="Verified subscription collections only — pending amounts are never counted."
      />

      <StatGrid
        items={[
          { label: "Total recorded", value: money(stats.totalRevenue), tone: "primary", hint: "All verified payments" },
          { label: "This month", value: money(stats.monthlyRevenue), hint: monthKey },
          { label: "This year", value: money(stats.yearlyRevenue), hint: todayISO().slice(0, 4) },
          { label: "Pending", value: money(stats.pendingAmount), tone: "amber", hint: `${stats.pendingPayments} unverified` },
        ]}
      />

      <Panel className="mt-4" title="Monthly subscription revenue" subtitle="Last 6 months of verified collections">
        <TrendChart data={series} name="Revenue" />
      </Panel>

      <Panel className="mt-4" title="Gym-wise payments">
        <DataTable
          empty="No gyms yet"
          rows={gymRows}
          columns={[
            { key: "name", label: "Gym", render: (row) => <span className="font-medium">{row.name}</span> },
            { key: "thisMonth", label: "This month", align: "right", render: (row) => money(row.thisMonth) },
            { key: "pending", label: "Pending", align: "right", render: (row) => money(row.pending) },
            {
              key: "lastRenewal",
              label: "Last renewal",
              render: (row) => (row.lastRenewal ? fmtDate(row.lastRenewal.at) : "—"),
            },
            {
              key: "verified",
              label: "Total collected",
              align: "right",
              render: (row) => <span className="font-medium">{money(row.verified)}</span>,
            },
          ]}
        />
      </Panel>

      <Panel className="mt-4" title="Renewal records">
        {db.gymSubscriptions.some((s) => s.history?.length) ? (
          <ul className="space-y-3">
            {db.gyms
              .flatMap((gym) =>
                (subscriptionOf(db, gym.id)?.history || []).map((h) => ({
                  key: `${gym.id}-${h.startDate}-${h.at}`,
                  gymName: gym.name,
                  ...h,
                })),
              )
              .sort((a, b) => String(b.at).localeCompare(String(a.at)))
              .slice(0, 10)
              .map((h) => (
                <li key={h.key} className="flex items-center justify-between border-b border-border/60 pb-3 text-[12.5px] last:border-0 last:pb-0">
                  <div>
                    <p className="font-medium">{h.gymName}</p>
                    <p className="text-[11px] text-muted-foreground">
                      {fmtDate(h.startDate)} → {fmtDate(h.expiryDate)} · {h.cycle}
                    </p>
                  </div>
                  <p className="font-medium">{money(h.amount)}</p>
                </li>
              ))}
          </ul>
        ) : (
          <Empty title="No renewals yet" />
        )}
      </Panel>
    </AdminShell>
  );
}