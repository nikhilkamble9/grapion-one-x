import { createFileRoute, Link } from "@tanstack/react-router";
import { MemberShell } from "@/components/grapion/shells";
import { useRoleSession, useStore } from "@/lib/grapion/useGrapion";
import { PageHead, Panel, StatGrid, Pill } from "@/components/grapion/ui";
import { DataTable } from "@/components/grapion/DataTable";
import { Button } from "@/components/ui/button";
import { fmtDate, money } from "@/lib/grapion/util";
import { memberView, planById } from "@/lib/grapion/repo";

export const Route = createFileRoute("/_authed/member/payments")({
  component: MyPayments,
  head: () => ({ meta: [{ title: "My payments · GRAPION GYM" }] }),
});

function MyPayments() {
  const session = useRoleSession();
  const db = useStore();
  const view = memberView(db, session?.memberId);
  if (!view) return null;
  const { member, paid, pending, total } = view;

  const rows = db.payments
    .filter((p) => p.memberId === member.id)
    .sort((a, b) => String(b.date).localeCompare(String(a.date)));

  return (
    <MemberShell>
      <PageHead
        eyebrow="Payments"
        title="My payments"
        description="What you have paid your gym and what is still due."
        actions={
          <Button asChild size="sm" variant="outline">
            <Link to="/member/renew">Renew membership</Link>
          </Button>
        }
      />

      <StatGrid
        cols={3}
        items={[
          { label: "Total paid", value: money(paid), tone: "green" },
          { label: "Pending", value: money(pending), tone: pending > 0 ? "amber" : "gray" },
          { label: "Membership value", value: money(total) },
        ]}
      />

      <Panel className="mt-4" title={`${rows.length} payment records`}>
        <DataTable
          empty="No payments recorded yet"
          rows={rows}
          columns={[
            { key: "date", label: "Date", render: (row) => fmtDate(row.date) },
            { key: "plan", label: "For", render: (row) => planById(db, row.planId)?.name || "Membership" },
            { key: "method", label: "Method", render: (row) => <span className="uppercase">{row.method}</span> },
            {
              key: "amount",
              label: "Amount",
              align: "right",
              render: (row) => <span className="font-medium">{money(row.amount)}</span>,
            },
            {
              key: "status",
              label: "Status",
              render: (row) => (
                <Pill tone={row.status === "verified" ? "green" : row.status === "pending" ? "amber" : "red"}>
                  {row.status}
                </Pill>
              ),
            },
          ]}
        />
      </Panel>

      <p className="mt-4 text-[11px] text-muted-foreground">
        Payments move to <span className="text-emerald-400">verified</span> only after your gym confirms
        the money was received.
      </p>
    </MemberShell>
  );
}