import { createFileRoute } from "@tanstack/react-router";
import { AdminShell } from "@/components/grapion/shells";
import { useStore } from "@/lib/grapion/useGrapion";
import { PageHead, Panel, StatGrid } from "@/components/grapion/ui";
import { DataTable } from "@/components/grapion/DataTable";
import { BarsChart } from "@/components/grapion/Charts";
import { money, todayISO } from "@/lib/grapion/util";
import { platformStats, subscriptionOf } from "@/lib/grapion/repo";

export const Route = createFileRoute("/_authed/admin/analytics")({
  component: AnalyticsPage,
  head: () => ({ meta: [{ title: "Analytics · GRAPION GYM" }] }),
});

function AnalyticsPage() {
  const db = useStore();
  const stats = platformStats(db);
  const monthKey = todayISO().slice(0, 7);

  const membersByGym = db.gyms.map((gym) => ({
    label: gym.name.split(" ")[0],
    value: db.gymMembers.filter((m) => m.gymId === gym.id).length,
  }));

  const statusCounts = [
    { label: "Active", value: stats.activeGyms },
    { label: "Suspended", value: stats.suspendedGyms },
    { label: "Inactive", value: stats.inactiveGyms },
    { label: "Expired", value: stats.expiredGyms },
  ];

  const rows = db.gyms.map((gym) => {
    const members = db.gymMembers.filter((m) => m.gymId === gym.id);
    const revenue = db.payments
      .filter((p) => p.gymId === gym.id && p.status === "verified" && String(p.date).slice(0, 7) === monthKey)
      .reduce((s, p) => s + Number(p.amount || 0), 0);
    const attendance = db.attendance.filter((a) => a.gymId === gym.id && a.date === todayISO()).length;
    return {
      id: gym.id,
      name: gym.name,
      members: members.length,
      attendance,
      revenue,
      cycle: subscriptionOf(db, gym.id)?.cycle || "—",
    };
  });

  return (
    <AdminShell>
      <PageHead eyebrow="Insights" title="Platform analytics" description="Live figures derived from stored gym records." />

      <StatGrid
        items={[
          { label: "Total members", value: stats.totalMembers },
          { label: "Gym workspaces", value: stats.totalGyms },
          { label: "Active subscriptions", value: stats.activeSubscriptions, tone: "green" },
          { label: "Monthly revenue", value: money(stats.monthlyRevenue), tone: "primary" },
        ]}
      />

      <div className="mt-4 grid gap-4 lg:grid-cols-2">
        <Panel title="Members per gym">
          <BarsChart data={membersByGym} name="Members" />
        </Panel>
        <Panel title="Gym status distribution">
          <BarsChart data={statusCounts} name="Gyms" />
        </Panel>
      </div>

      <Panel className="mt-4" title="Gym performance" subtitle="Members, today's visits and this month's collections">
        <DataTable
          empty="No gyms yet"
          rows={rows}
          columns={[
            { key: "name", label: "Gym", render: (row) => <span className="font-medium">{row.name}</span> },
            { key: "members", label: "Members", align: "right" },
            { key: "attendance", label: "Visits today", align: "right" },
            { key: "revenue", label: "Collected this month", align: "right", render: (row) => money(row.revenue) },
            { key: "cycle", label: "Plan", render: (row) => <span className="capitalize">{row.cycle}</span> },
          ]}
        />
      </Panel>
    </AdminShell>
  );
}