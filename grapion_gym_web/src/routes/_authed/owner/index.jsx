import { createFileRoute, Link } from "@tanstack/react-router";
import {
  AlertTriangle,
  ArrowRight,
  CalendarClock,
  Clock,
  LogIn,
  LogOut,
  Plus,
  ScanLine,
  UserPlus,
  Users,
  Wallet,
} from "lucide-react";
import { OwnerShell } from "@/components/grapion/shells";
import { useRoleSession, useStore } from "@/lib/grapion/useGrapion";
import { PageHead, Panel, StatGrid, Pill, Empty, Photo } from "@/components/grapion/ui";
import { BarsChart } from "@/components/grapion/Charts";
import { Button } from "@/components/ui/button";
import {
  fmtDate,
  fmtTime,
  membershipStatus,
  money,
  todayISO,
} from "@/lib/grapion/util";
import { gymStats, memberById, planById } from "@/lib/grapion/repo";

export const Route = createFileRoute("/_authed/owner/")({
  component: OwnerDashboard,
  head: () => ({ meta: [{ title: "Gym dashboard · GRAPION GYM" }] }),
});

const quickActions = [
  { to: "/owner/members", label: "Add member", icon: UserPlus },
  { to: "/owner/memberships", label: "Add membership", icon: CalendarClock },
  { to: "/owner/payments", label: "Record payment", icon: Wallet },
  { to: "/owner/checkin", label: "Check-in member", icon: ScanLine },
  { to: "/owner/batches", label: "Create batch", icon: Clock },
  { to: "/owner/members", label: "View expiring", icon: Users },
];

function OwnerDashboard() {
  const session = useRoleSession();
  const db = useStore();
  const gymId = session?.gymId;
  const stats = gymStats(db, gymId);
  const today = todayISO();

  const warn = db.adminSettings.expiryWarningDays || 7;
  const expiring = stats.rows.filter((r) => r.membership && r.status.days >= 0 && r.status.days <= warn);
  const tomorrow = stats.rows.filter((r) => r.status.days === 1);
  const expired = stats.rows.filter((r) => r.status.key === "expired");
  const noPlan = stats.rows.filter((r) => !r.membership);
  const pending = db.payments.filter((p) => p.gymId === gymId && p.status === "pending");
  const recentMembers = [...db.gymMembers.filter((m) => m.gymId === gymId)]
    .sort((a, b) => String(b.joinedAt).localeCompare(String(a.joinedAt)))
    .slice(0, 5);
  const recentVisits = db.attendance
    .filter((a) => a.gymId === gymId)
    .sort((a, b) => String(b.checkIn).localeCompare(String(a.checkIn)))
    .slice(0, 5);
  const recentPayments = db.payments
    .filter((p) => p.gymId === gymId)
    .sort((a, b) => String(b.createdAt || b.date).localeCompare(String(a.createdAt || a.date)))
    .slice(0, 5);

  const months = Array.from({ length: 6 }, (_, i) => {
    const d = new Date();
    d.setDate(1);
    d.setMonth(d.getMonth() - (5 - i));
    return d;
  });
  const attendanceSeries = months.map((d) => {
    const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
    return {
      label: d.toLocaleDateString("en-IN", { month: "short" }),
      value: db.attendance.filter((a) => a.gymId === gymId && String(a.date).slice(0, 7) === key).length,
    };
  });

  return (
    <OwnerShell>
      <PageHead
        eyebrow={`${fmtDate(today)}`}
        title="Gym dashboard"
        description="Live operations snapshot — every number comes from your stored records."
        actions={
          <Button asChild size="sm">
            <Link to="/owner/checkin">
              <ScanLine className="mr-1.5 h-3.5 w-3.5" /> Open check-in desk
            </Link>
          </Button>
        }
      />

      <StatGrid
        items={[
          { label: "Total members", value: stats.totalMembers, icon: Users, hint: `${stats.activeMembers} active` },
          { label: "Expiring soon", value: stats.expiringSoon, tone: "amber", hint: `${warn}-day window` },
          { label: "Expired", value: stats.expiredMembers, tone: "red", hint: "Need renewal" },
          { label: "Inactive", value: stats.inactiveMembers, hint: "Deactivated accounts" },
          { label: "Check-ins today", value: stats.todayCheckIns, icon: LogIn, tone: "green", hint: "Members inside" },
          { label: "Check-outs today", value: stats.todayCheckOuts, icon: LogOut, hint: "Completed visits" },
          { label: "Collected today", value: money(stats.todayPayments), icon: Wallet, tone: "green" },
          { label: "Monthly revenue", value: money(stats.monthlyRevenue), tone: "primary", hint: today.slice(0, 7) },
        ]}
      />

      <div className="mt-4 grid gap-4 lg:grid-cols-[1.05fr_0.95fr]">
        <Panel
          title="Action required"
          subtitle="Memberships and payments that need a nudge"
          action={<Pill tone={expiring.length + expired.length + pending.length ? "amber" : "green"}>
            {expiring.length + expired.length + pending.length} open
          </Pill>}
        >
          <div className="space-y-4">
            {[
              { label: `Expiring within ${warn} days`, value: expiring.length, tone: "amber" },
              { label: "Expiring tomorrow", value: tomorrow.length, tone: "amber" },
              { label: "Expired memberships", value: expired.length, tone: "red" },
              { label: "Pending payments", value: pending.length, tone: "blue" },
              { label: "Members without a plan", value: noPlan.length, tone: "gray" },
            ].map((row) => (
              <div key={row.label} className="flex items-center justify-between gap-3">
                <div className="flex items-center gap-2.5">
                  <AlertTriangle className={`h-3.5 w-3.5 ${row.value ? "text-amber-400" : "text-muted-foreground/40"}`} />
                  <span className="text-[12.5px]">{row.label}</span>
                </div>
                <Pill tone={row.value ? row.tone : "gray"}>{row.value}</Pill>
              </div>
            ))}
            {expiring.length > 0 && (
              <div className="space-y-2 border-t border-border pt-3">
                {expiring.slice(0, 3).map((row) => (
                  <div key={row.member.id} className="flex items-center gap-2.5">
                    <Photo src={row.member.photo} name={row.member.name} size={26} />
                    <span className="flex-1 truncate text-[12px]">{row.member.name}</span>
                    <span className="text-[11px] text-muted-foreground">{fmtDate(row.membership.expiryDate)}</span>
                  </div>
                ))}
              </div>
            )}
          </div>
        </Panel>

        <Panel title="Quick actions" subtitle="The six things front desks do most">
          <div className="grid grid-cols-2 gap-2">
            {quickActions.map((action) => (
              <Link
                key={action.label}
                to={action.to}
                className="flex items-center gap-2 rounded-xl border border-border px-3 py-3 text-[12px] font-medium transition-colors hover:border-primary/40 hover:text-primary"
              >
                <action.icon className="h-3.5 w-3.5" /> {action.label}
              </Link>
            ))}
          </div>
          <div className="mt-3 rounded-xl border border-border px-3 py-3">
            <p className="gp-eyebrow">Membership overview</p>
            <div className="mt-2 grid grid-cols-3 gap-2 text-center">
              <div>
                <p className="gp-num font-heading text-lg font-semibold text-emerald-400">{stats.activeMembers}</p>
                <p className="text-[10px] text-muted-foreground">Active</p>
              </div>
              <div>
                <p className="gp-num font-heading text-lg font-semibold text-amber-400">{stats.expiringSoon}</p>
                <p className="text-[10px] text-muted-foreground">Expiring</p>
              </div>
              <div>
                <p className="gp-num font-heading text-lg font-semibold text-red-400">{stats.expiredMembers}</p>
                <p className="text-[10px] text-muted-foreground">Expired</p>
              </div>
            </div>
          </div>
        </Panel>
      </div>

      <div className="mt-4 grid gap-4 lg:grid-cols-2">
        <Panel title="Recent member registrations">
          {recentMembers.length ? (
            <ul className="space-y-3">
              {recentMembers.map((member) => (
                <li key={member.id} className="flex items-center gap-2.5">
                  <Photo src={member.photo} name={member.name} size={30} />
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-[12.5px] font-medium">{member.name}</p>
                    <p className="text-[10.5px] text-muted-foreground">
                      {member.code} · {fmtDate(member.joinedAt)}
                      {member.isDemo ? " · demo" : ""}
                    </p>
                  </div>
                  <Link to="/owner/members" className="text-[11px] text-primary">Open</Link>
                </li>
              ))}
            </ul>
          ) : (
            <Empty title="No members yet" hint="Add your first member to get started." />
          )}
        </Panel>

        <Panel title="Recent check-in activity">
          {recentVisits.length ? (
            <ul className="space-y-3">
              {recentVisits.map((record) => {
                const member = memberById(db, record.memberId);
                return (
                  <li key={record.id} className="flex items-center gap-2.5">
                    <Photo src={member?.photo} name={member?.name} size={26} />
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-[12px]">{member?.name || "Member"}</p>
                      <p className="text-[10.5px] text-muted-foreground">{fmtDate(record.date)}</p>
                    </div>
                    <span className="text-[11px] text-muted-foreground">
                      {fmtTime(record.checkIn)} {record.checkOut ? `→ ${fmtTime(record.checkOut)}` : "· inside"}
                    </span>
                  </li>
                );
              })}
            </ul>
          ) : (
            <Empty title="No visits recorded yet" />
          )}
        </Panel>

        <Panel title="Monthly attendance" subtitle="Visits over the last 6 months">
          <BarsChart data={attendanceSeries} name="Visits" />
        </Panel>

        <Panel
          title="Recent payments"
          action={<Button asChild size="sm" variant="ghost"><Link to="/owner/payments">All payments <ArrowRight className="ml-1 h-3 w-3" /></Link></Button>}
        >
          {recentPayments.length ? (
            <ul className="space-y-3">
              {recentPayments.map((payment) => {
                const member = memberById(db, payment.memberId);
                return (
                  <li key={payment.id} className="flex items-center gap-2.5">
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-[12px]">
                        {member?.name || "Member"} · {planById(db, payment.planId)?.name || payment.type}
                      </p>
                      <p className="text-[10.5px] text-muted-foreground">
                        {fmtDate(payment.date)} · {payment.method}
                      </p>
                    </div>
                    <span className="text-[12px] font-medium">{money(payment.amount)}</span>
                    <Pill tone={payment.status === "verified" ? "green" : payment.status === "pending" ? "amber" : "red"}>
                      {payment.status}
                    </Pill>
                  </li>
                );
              })}
            </ul>
          ) : (
            <Empty title="No payments recorded yet" />
          )}
        </Panel>
      </div>

      <p className="mt-6 text-center text-[10px] uppercase tracking-[0.2em] text-muted-foreground/60">
        Powered by Grapion Digital
      </p>
    </OwnerShell>
  );
}