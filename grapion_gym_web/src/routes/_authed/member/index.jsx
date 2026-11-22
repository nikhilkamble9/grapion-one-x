import { createFileRoute, Link } from "@tanstack/react-router";
import { ArrowRight, CalendarCheck, CreditCard, LogIn, LogOut, Wallet } from "lucide-react";
import { MemberShell } from "@/components/grapion/shells";
import { useRoleSession, useStore } from "@/lib/grapion/useGrapion";
import { Pill, Photo, Panel, Empty, Bar } from "@/components/grapion/ui";
import { Button } from "@/components/ui/button";
import { useToast } from "@/components/ui/use-toast";
import { fmtDate, fmtTime, money, todayISO } from "@/lib/grapion/util";
import { checkIn, checkOut, memberView } from "@/lib/grapion/repo";

export const Route = createFileRoute("/_authed/member/")({
  component: MemberDashboard,
  head: () => ({ meta: [{ title: "My dashboard · GRAPION GYM" }] }),
});

function MemberDashboard() {
  const session = useRoleSession();
  const db = useStore();
  const { toast } = useToast();
  const view = memberView(db, session?.memberId);
  if (!view) return null;
  const { member, membership, plan, gym, batch, status, paid, total, pending } = view;

  const today = todayISO();
  const open = db.attendance.find((a) => a.memberId === member.id && !a.checkOut);
  const todayRecord = db.attendance.find((a) => a.memberId === member.id && a.date === today);
  const visits = db.attendance
    .filter((a) => a.memberId === member.id)
    .sort((a, b) => String(b.checkIn).localeCompare(String(a.checkIn)));
  const payments = db.payments
    .filter((p) => p.memberId === member.id)
    .sort((a, b) => String(b.date).localeCompare(String(a.date)));
  const notes = db.notifications
    .filter((n) => n.audience === "member" && n.memberId === member.id)
    .slice(0, 3);

  const act = (fn, label) => {
    try {
      fn(member.id);
      toast({ title: label });
    } catch (err) {
      toast({ title: "Not possible", description: err.message });
    }
  };

  return (
    <MemberShell>
      <section className="overflow-hidden rounded-2xl border border-border bg-card">
        <div className="flex flex-col gap-4 p-5 sm:flex-row sm:items-center">
          <Photo src={member.photo} name={member.name} size={64} rounded="rounded-2xl" />
          <div className="min-w-0 flex-1">
            <p className="gp-eyebrow">{gym?.name || "Your gym"}</p>
            <h1 className="mt-1.5 font-heading text-[22px] font-semibold leading-tight">{member.name}</h1>
            <p className="mt-1 text-[11.5px] text-muted-foreground">
              {member.code} · joined {fmtDate(member.joinedAt)}
            </p>
          </div>
          <div className="flex flex-col items-start gap-1.5 sm:items-end">
            <Pill tone={status.tone}>{status.label}</Pill>
            <span className="text-[11px] text-muted-foreground">
              {status.key === "none" ? "No active plan" : `${Math.max(0, status.days)} days remaining`}
            </span>
          </div>
        </div>

        <div className="grid gap-3 border-t border-border p-5 sm:grid-cols-2">
          <Button
            disabled={Boolean(open) || member.status !== "active"}
            onClick={() => act(checkIn, "Checked in")}
            className="h-12"
          >
            <LogIn className="mr-2 h-4 w-4" /> CHECK IN
          </Button>
          <Button
            variant="outline"
            disabled={!open}
            onClick={() => act(checkOut, "Checked out")}
            className="h-12"
          >
            <LogOut className="mr-2 h-4 w-4" /> CHECK OUT
          </Button>
          {open && (
            <p className="text-[11px] text-emerald-400 sm:col-span-2">
              You are checked in since {fmtTime(open.checkIn)}.
            </p>
          )}
          {!open && todayRecord?.checkOut && (
            <p className="text-[11px] text-muted-foreground sm:col-span-2">
              Today's visit: {fmtTime(todayRecord.checkIn)} → {fmtTime(todayRecord.checkOut)}
            </p>
          )}
        </div>
      </section>

      <div className="mt-4 grid gap-3 sm:grid-cols-2">
        <Panel title="Membership" bodyClass="p-5">
          <div className="flex items-start justify-between">
            <div>
              <p className="font-heading text-[14px] font-semibold">{plan?.name || "No active plan"}</p>
              <p className="mt-1 text-[11.5px] text-muted-foreground">
                {membership ? `${fmtDate(membership.startDate)} → ${fmtDate(membership.expiryDate)}` : "Contact your gym"}
              </p>
            </div>
            <Pill tone={status.tone}>{status.label}</Pill>
          </div>
          <div className="mt-4">
            <Bar
              value={Math.max(0, status.days)}
              max={Math.max(30, status.days + 30)}
              tone={status.tone === "red" ? "red" : status.tone === "amber" ? "primary" : "green"}
            />
            <p className="mt-2 text-[11px] text-muted-foreground">
              {status.key === "expired" ? "Expired — renew to continue training." : `${Math.max(0, status.days)} days remaining`}
            </p>
          </div>
          <Button asChild variant="outline" className="mt-4 w-full">
            <Link to="/member/renew">
              RENEW MEMBERSHIP <ArrowRight className="ml-1.5 h-3.5 w-3.5" />
            </Link>
          </Button>
        </Panel>

        <Panel title="Payments & batch" bodyClass="p-5">
          <div className="flex items-center justify-between text-[12px]">
            <span className="text-muted-foreground">Paid</span>
            <span className="font-medium">{money(paid)} of {money(total)}</span>
          </div>
          <div className="mt-2 flex items-center justify-between text-[12px]">
            <span className="text-muted-foreground">Pending</span>
            <span className={pending > 0 ? "font-medium text-amber-400" : "font-medium"}>{money(pending)}</span>
          </div>
          <div className="mt-2 flex items-center justify-between text-[12px]">
            <span className="text-muted-foreground">Batch</span>
            <span className="font-medium">{batch?.name || "Not assigned"}</span>
          </div>
          <div className="mt-2 flex items-center justify-between text-[12px]">
            <span className="text-muted-foreground">Total visits</span>
            <span className="font-medium">{visits.length}</span>
          </div>
          <div className="mt-4 grid grid-cols-2 gap-2">
            <Button asChild size="sm" variant="outline">
              <Link to="/member/payments"><Wallet className="mr-1.5 h-3.5 w-3.5" /> Payments</Link>
            </Button>
            <Button asChild size="sm" variant="outline">
              <Link to="/member/attendance"><CalendarCheck className="mr-1.5 h-3.5 w-3.5" /> Visits</Link>
            </Button>
          </div>
        </Panel>
      </div>

      <div className="mt-4 grid gap-3 sm:grid-cols-2">
        <Panel title="Membership plan" bodyClass="p-5">
          <div className="flex items-center gap-2 text-[12px] text-muted-foreground">
            <CreditCard className="h-4 w-4" /> {plan?.description || "No plan description"}
          </div>
          <p className="mt-3 text-[11.5px] text-muted-foreground">
            Gym hours: {gym?.openingHours || "Ask your gym"}
          </p>
        </Panel>

        <Panel
          title="Notifications"
          action={<Button asChild size="sm" variant="ghost"><Link to="/member/notifications">All</Link></Button>}
          bodyClass="p-5"
        >
          {notes.length ? (
            <ul className="space-y-2">
              {notes.map((n) => (
                <li key={n.id} className="text-[12px]">
                  <p className={n.read ? "font-medium text-muted-foreground" : "font-semibold"}>{n.title}</p>
                  <p className="text-[11px] text-muted-foreground">{n.message}</p>
                </li>
              ))}
            </ul>
          ) : (
            <Empty title="Nothing new" />
          )}
        </Panel>
      </div>

      <Panel className="mt-4" title="Recent visits" bodyClass="p-5">
        {visits.length ? (
          <ul className="space-y-2">
            {visits.slice(0, 5).map((v) => (
              <li key={v.id} className="flex items-center justify-between text-[12px]">
                <span>{fmtDate(v.date)}</span>
                <span className="text-muted-foreground">
                  {fmtTime(v.checkIn)} → {v.checkOut ? fmtTime(v.checkOut) : "inside"}
                </span>
              </li>
            ))}
          </ul>
        ) : (
          <Empty title="No visits yet" hint="Check in when you reach the gym." />
        )}
      </Panel>

      <p className="mt-6 text-center text-[10px] uppercase tracking-[0.2em] text-muted-foreground/60">
        Powered by Grapion Digital
      </p>
    </MemberShell>
  );
}