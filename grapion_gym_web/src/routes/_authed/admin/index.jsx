import { createFileRoute, Link } from "@tanstack/react-router";
import {
  ArrowUpRight,
  Building2,
  CreditCard,
  AlertTriangle,
  TrendingUp,
  Users,
} from "lucide-react";
import { AdminShell } from "@/components/grapion/shells";
import { useStore } from "@/lib/grapion/useGrapion";
import { PageHead, Panel, StatGrid, Pill, Bar, Empty, KeyValue } from "@/components/grapion/ui";
import { Button } from "@/components/ui/button";
import { fmtDate, fmtDateTime, money, subscriptionStatus, todayISO, daysUntil } from "@/lib/grapion/util";
import { platformStats, subscriptionOf, gymStats } from "@/lib/grapion/repo";

export const Route = createFileRoute("/_authed/admin/")({
  component: AdminOverview,
  head: () => ({ meta: [{ title: "Admin overview · GRAPION GYM" }] }),
});

function AdminOverview() {
  const db = useStore();
  const stats = platformStats(db);
  const recentGyms = [...db.gyms].sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt))).slice(0, 5);
  const recentLogs = db.auditLogs.slice(0, 6);
  const expiries = stats.subs
    .filter((row) => row.sub)
    .sort((a, b) => String(a.sub.expiryDate).localeCompare(String(b.sub.expiryDate)))
    .slice(0, 5);
  const needAction = stats.subs.filter((row) => {
    const st = subscriptionStatus(row.sub?.expiryDate, row.gym.status);
    return st.key !== "active" || (st.days ?? 99) <= 7;
  });
  const monthKey = todayISO().slice(0, 7);
  const maxMembers = Math.max(1, ...db.gyms.map((g) => db.gymMembers.filter((m) => m.gymId === g.id).length));

  return (
    <AdminShell>
      <PageHead
        eyebrow="Grapion Digital"
        title="Platform overview"
        description="Every gym, owner and subscription across the Grapion Gym network — calculated from stored records."
        actions={
          <Button asChild size="sm">
            <Link to="/admin/gyms">
              Manage gyms <ArrowUpRight className="ml-1.5 h-3.5 w-3.5" />
            </Link>
          </Button>
        }
      />

      <StatGrid
        items={[
          { label: "Total gyms", value: stats.totalGyms, hint: `${stats.activeGyms} active`, icon: Building2, tone: "gray" },
          { label: "Suspended", value: stats.suspendedGyms, hint: "Access restricted", icon: AlertTriangle, tone: stats.suspendedGyms ? "amber" : "gray" },
          { label: "Expired subs", value: stats.expiredGyms, hint: "Needs renewal", tone: stats.expiredGyms ? "red" : "gray" },
          { label: "Total members", value: stats.totalMembers, hint: "Across all gyms", icon: Users, tone: "gray" },
          { label: "Active subs", value: stats.activeSubscriptions, hint: "Live on platform", icon: CreditCard, tone: "green" },
          { label: "Expiring subs", value: stats.expiringSubscriptions, hint: "Within 7 days", tone: stats.expiringSubscriptions ? "amber" : "gray" },
          { label: "Pending payments", value: money(stats.pendingAmount), hint: `${stats.pendingPayments} awaiting review`, tone: "gray" },
          { label: "Recorded revenue", value: money(stats.totalRevenue), hint: `${money(stats.monthlyRevenue)} this month`, icon: TrendingUp, tone: "primary" },
        ]}
      />

      <div className="mt-4 grid gap-4 lg:grid-cols-2">
        <Panel title="Recent gym registrations" subtitle="Newest workspaces on the platform">
          {recentGyms.length ? (
            <ul className="space-y-3">
              {recentGyms.map((gym) => {
                const sub = subscriptionOf(db, gym.id);
                const st = subscriptionStatus(sub?.expiryDate, gym.status);
                return (
                  <li key={gym.id} className="flex items-center justify-between gap-3">
                    <div className="min-w-0">
                      <p className="truncate text-[13px] font-medium">{gym.name}</p>
                      <p className="truncate text-[11px] text-muted-foreground">
                        {gym.city || "—"} · registered {fmtDate(gym.createdAt)}
                        {gym.isDemo ? " · demo" : ""}
                      </p>
                    </div>
                    <Pill tone={st.tone}>{st.label}</Pill>
                  </li>
                );
              })}
            </ul>
          ) : (
            <Empty title="No gyms yet" hint="Create the first gym from Manage Gyms." />
          )}
        </Panel>

        <Panel title="Action required" subtitle="Subscriptions that need your attention">
          {needAction.length ? (
            <ul className="space-y-3">
              {needAction.slice(0, 6).map(({ gym, sub }) => {
                const st = subscriptionStatus(sub?.expiryDate, gym.status);
                return (
                  <li key={gym.id} className="flex items-center justify-between gap-3">
                    <div className="min-w-0">
                      <p className="truncate text-[13px] font-medium">{gym.name}</p>
                      <p className="truncate text-[11px] text-muted-foreground">
                        {sub ? `Expires ${fmtDate(sub.expiryDate)}` : "No subscription configured"}
                      </p>
                    </div>
                    <div className="flex items-center gap-2">
                      <Pill tone={st.tone}>{st.label}</Pill>
                      <Button asChild size="sm" variant="outline">
                        <Link to="/admin/subscriptions">Renew</Link>
                      </Button>
                    </div>
                  </li>
                );
              })}
            </ul>
          ) : (
            <Empty title="Nothing needs attention" hint="Every subscription is active and healthy." />
          )}
        </Panel>

        <Panel title="Upcoming subscription expiries">
          <ul className="space-y-3">
            {expiries.map(({ gym, sub }) => (
              <li key={gym.id} className="flex items-center justify-between gap-3">
                <div>
                  <p className="text-[13px] font-medium">{gym.name}</p>
                  <p className="text-[11px] text-muted-foreground">{fmtDate(sub.expiryDate)}</p>
                </div>
                <Pill tone={daysUntil(sub.expiryDate) < 0 ? "red" : daysUntil(sub.expiryDate) <= 7 ? "amber" : "green"}>
                  {daysUntil(sub.expiryDate) < 0
                    ? `${Math.abs(daysUntil(sub.expiryDate))}d overdue`
                    : `${daysUntil(sub.expiryDate)}d left`}
                </Pill>
              </li>
            ))}
            {!expiries.length && <Empty title="No subscriptions yet" />}
          </ul>
        </Panel>

        <Panel title="Recent activity" action={<Button asChild size="sm" variant="ghost"><Link to="/admin/activity">View all</Link></Button>}>
          {recentLogs.length ? (
            <ul className="space-y-3">
              {recentLogs.map((row) => (
                <li key={row.id} className="flex items-start gap-3">
                  <span className="mt-1.5 h-1.5 w-1.5 shrink-0 rounded-full bg-primary" />
                  <div className="min-w-0">
                    <p className="truncate text-[12.5px] font-medium">{row.action}</p>
                    <p className="truncate text-[11px] text-muted-foreground">
                      {row.detail} · {fmtDateTime(row.date)}
                    </p>
                  </div>
                </li>
              ))}
            </ul>
          ) : (
            <Empty title="No activity recorded yet" />
          )}
        </Panel>
      </div>

      <Panel className="mt-4" title="Gym-wise analytics" subtitle="Members and collections per gym">
        <div className="space-y-4">
          {db.gyms.map((gym) => {
            const gs = gymStats(db, gym.id);
            const members = db.gymMembers.filter((m) => m.gymId === gym.id).length;
            const collected = db.payments
              .filter((p) => p.gymId === gym.id && p.status === "verified" && String(p.date).slice(0, 7) === monthKey)
              .reduce((s, p) => s + Number(p.amount || 0), 0);
            return (
              <div key={gym.id} className="grid gap-2 sm:grid-cols-[1.2fr_0.8fr_0.8fr_1.4fr] sm:items-center">
                <p className="truncate text-[12.5px] font-medium">{gym.name}</p>
                <p className="text-[11.5px] text-muted-foreground">{members} members</p>
                <p className="text-[11.5px] text-muted-foreground">{money(collected)} this month</p>
                <div className="flex items-center gap-3">
                  <Bar value={members} max={maxMembers} />
                  <span className="shrink-0 text-[10.5px] text-muted-foreground">
                    {gs.todayCheckIns} today
                  </span>
                </div>
              </div>
            );
          })}
          {!db.gyms.length && <Empty title="No gyms to analyse yet" />}
        </div>
      </Panel>

      <div className="mt-4">
        <Panel title="Platform snapshot">
          <div className="grid gap-x-8 sm:grid-cols-2">
            <KeyValue label="Company" value={db.adminSettings.company} />
            <KeyValue label="Yearly revenue" value={money(stats.yearlyRevenue)} />
            <KeyValue label="Active members across gyms" value={String(stats.totalMembers)} />
            <KeyValue label="Gyms suspended" value={String(stats.suspendedGyms)} />
          </div>
        </Panel>
      </div>
    </AdminShell>
  );
}