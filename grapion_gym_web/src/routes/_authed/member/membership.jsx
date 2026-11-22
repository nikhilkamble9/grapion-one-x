import { createFileRoute, Link } from "@tanstack/react-router";
import { ArrowRight } from "lucide-react";
import { MemberShell } from "@/components/grapion/shells";
import { useRoleSession, useStore } from "@/lib/grapion/useGrapion";
import { PageHead, Panel, Pill, KeyValue, Bar, Empty } from "@/components/grapion/ui";
import { Button } from "@/components/ui/button";
import { durationLabel, fmtDate, money } from "@/lib/grapion/util";
import { memberView, planById } from "@/lib/grapion/repo";

export const Route = createFileRoute("/_authed/member/membership")({
  component: MyMembership,
  head: () => ({ meta: [{ title: "My membership · GRAPION GYM" }] }),
});

function MyMembership() {
  const session = useRoleSession();
  const db = useStore();
  const view = memberView(db, session?.memberId);
  if (!view) return null;
  const { member, membership, plan, status, paid, total, pending, gym } = view;

  const history = db.memberships
    .filter((m) => m.memberId === member.id)
    .sort((a, b) => String(b.expiryDate).localeCompare(String(a.expiryDate)));
  const services = (plan?.services || [])
    .map((id) => db.services.find((s) => s.id === id))
    .filter(Boolean);

  return (
    <MemberShell>
      <PageHead
        eyebrow="Membership"
        title="My membership"
        description="Your current package, validity and payment position."
        actions={
          <Button asChild size="sm">
            <Link to="/member/renew">Renew <ArrowRight className="ml-1.5 h-3.5 w-3.5" /></Link>
          </Button>
        }
      />

      <div className="grid gap-4 lg:grid-cols-[1.05fr_0.95fr]">
        <Panel title={plan?.name || "No active plan"}>
          <div className="flex items-center justify-between">
            <p className="text-[11.5px] text-muted-foreground">
              {plan ? durationLabel(plan.durationMonths) : "Ask your gym to assign a plan"}
            </p>
            <Pill tone={status.tone}>{status.label}</Pill>
          </div>
          <div className="mt-4">
            <Bar
              value={Math.max(0, status.days)}
              max={Math.max(30, status.days + 30)}
              tone={status.tone === "red" ? "red" : status.tone === "amber" ? "primary" : "green"}
            />
            <p className="mt-2 text-[11px] text-muted-foreground">
              {status.key === "expired" ? "This membership has expired." : `${Math.max(0, status.days)} days remaining`}
            </p>
          </div>
          <div className="mt-4 grid gap-x-6 sm:grid-cols-2">
            <KeyValue label="Gym" value={gym?.name} />
            <KeyValue label="Joining date" value={fmtDate(member.joinedAt)} />
            <KeyValue label="Start date" value={membership ? fmtDate(membership.startDate) : "—"} />
            <KeyValue label="Expiry date" value={membership ? fmtDate(membership.expiryDate) : "—"} />
            <KeyValue label="Total amount" value={money(total)} />
            <KeyValue label="Paid amount" value={money(paid)} />
            <KeyValue label="Pending amount" value={pending > 0 ? money(pending) : "Nil"} />
            <KeyValue label="Payment status" value={pending > 0 ? "Partially paid" : total > 0 ? "Fully paid" : "—"} />
          </div>
        </Panel>

        <div className="space-y-4">
          <Panel title="Included services">
            {services.length ? (
              <ul className="space-y-2">
                {services.map((service) => (
                  <li key={service.id} className="text-[12px]">
                    <p className="font-medium">{service.name}</p>
                    <p className="text-[11px] text-muted-foreground">{service.description || "Included in your plan"}</p>
                  </li>
                ))}
              </ul>
            ) : (
              <Empty title="No services linked to this plan" />
            )}
          </Panel>

          <Panel title="Membership history">
            {history.length ? (
              <ul className="space-y-2">
                {history.map((row) => (
                  <li key={row.id} className="flex items-center justify-between rounded-lg border border-border px-3 py-2">
                    <div>
                      <p className="text-[12px] font-medium">{planById(db, row.planId)?.name || "Plan"}</p>
                      <p className="text-[10.5px] text-muted-foreground">
                        {fmtDate(row.startDate)} → {fmtDate(row.expiryDate)}
                      </p>
                    </div>
                    <span className="text-[11.5px]">{money(row.totalAmount)}</span>
                  </li>
                ))}
              </ul>
            ) : (
              <Empty title="No history yet" />
            )}
          </Panel>
        </div>
      </div>
    </MemberShell>
  );
}