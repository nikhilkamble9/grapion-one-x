import { useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { MemberShell } from "@/components/grapion/shells";
import { useRoleSession, useStore } from "@/lib/grapion/useGrapion";
import { PageHead, Panel, Pill, Empty, KeyValue } from "@/components/grapion/ui";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { fmtDate, fmtDateTime, money } from "@/lib/grapion/util";
import { memberView, planById } from "@/lib/grapion/repo";

export const Route = createFileRoute("/_authed/member/receipts")({
  component: ReceiptsPage,
  head: () => ({ meta: [{ title: "Receipts · GRAPION GYM" }] }),
});

function ReceiptsPage() {
  const session = useRoleSession();
  const db = useStore();
  const view = memberView(db, session?.memberId);
  const [selected, setSelected] = useState(null);
  if (!view) return null;

  const receipts = db.payments
    .filter((p) => p.memberId === view.member.id && p.status === "verified")
    .sort((a, b) => String(b.date).localeCompare(String(a.date)));

  return (
    <MemberShell>
      <PageHead
        eyebrow="Receipts"
        title="Payment receipts"
        description="A record of every confirmed payment — open one to see the full detail."
      />

      {receipts.length ? (
        <div className="grid gap-3 sm:grid-cols-2">
          {receipts.map((payment) => (
            <Panel key={payment.id} bodyClass="p-4">
              <div className="flex items-start justify-between">
                <div>
                  <p className="font-heading text-[14px] font-semibold">{money(payment.amount)}</p>
                  <p className="mt-1 text-[11px] text-muted-foreground">
                    {planById(db, payment.planId)?.name || "Membership"} · {fmtDate(payment.date)}
                  </p>
                </div>
                <Pill tone="green">verified</Pill>
              </div>
              <Button size="sm" variant="outline" className="mt-3 w-full" onClick={() => setSelected(payment)}>
                View receipt
              </Button>
            </Panel>
          ))}
        </div>
      ) : (
        <Empty title="No receipts yet" hint="Receipts appear once your gym verifies a payment." />
      )}

      <Dialog open={Boolean(selected)} onOpenChange={(open) => !open && setSelected(null)}>
        <DialogContent className="sm:max-w-[460px]">
          <DialogHeader>
            <DialogTitle className="font-heading">Payment receipt</DialogTitle>
          </DialogHeader>
          {selected && (
            <div>
              <div className="rounded-xl border border-border bg-secondary/40 p-4">
                <p className="gp-eyebrow">{view.gym?.name}</p>
                <p className="mt-2 font-heading text-2xl font-semibold">{money(selected.amount)}</p>
                <p className="text-[11.5px] text-muted-foreground">
                  Receipt {selected.id.slice(-8).toUpperCase()}
                </p>
              </div>
              <div className="mt-2">
                <KeyValue label="Member" value={view.member.name} />
                <KeyValue label="Member ID" value={view.member.code} />
                <KeyValue label="Towards" value={planById(db, selected.planId)?.name || "Membership"} />
                <KeyValue label="Method" value={selected.method.toUpperCase()} />
                <KeyValue label="Payment date" value={fmtDate(selected.date)} />
                <KeyValue label="Status" value="Verified by gym" />
                <KeyValue label="Verified on" value={selected.verifiedAt ? fmtDateTime(selected.verifiedAt) : "—"} />
              </div>
              <p className="mt-3 text-[10.5px] leading-relaxed text-muted-foreground">
                This receipt reflects a payment recorded in your gym's workspace. It is not a tax
                invoice.
              </p>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </MemberShell>
  );
}