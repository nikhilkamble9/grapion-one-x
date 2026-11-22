import { useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { Check, Info } from "lucide-react";
import { MemberShell } from "@/components/grapion/shells";
import { useRoleSession, useStore } from "@/lib/grapion/useGrapion";
import { PageHead, Panel, Pill, Field } from "@/components/grapion/ui";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { useToast } from "@/components/ui/use-toast";
import { addMonths, durationLabel, fmtDate, money, todayISO } from "@/lib/grapion/util";
import { memberView, submitRenewalRequest } from "@/lib/grapion/repo";

export const Route = createFileRoute("/_authed/member/renew")({
  component: RenewPage,
  head: () => ({ meta: [{ title: "Renew membership · GRAPION GYM" }] }),
});

function RenewPage() {
  const session = useRoleSession();
  const db = useStore();
  const { toast } = useToast();
  const view = memberView(db, session?.memberId);
  const plans = db.membershipPlans.filter((p) => p.gymId === view?.member.gymId && p.status === "active");
  const [planId, setPlanId] = useState(plans[0]?.id || "");
  const [reference, setReference] = useState("");
  const [busy, setBusy] = useState(false);

  if (!view) return null;
  const { member, gym, membership } = view;
  const plan = plans.find((p) => p.id === planId);
  const awaiting = db.payments.find(
    (p) => p.memberId === member.id && p.status === "pending" && p.type === "renewal",
  );

  const submit = () => {
    if (!plan) {
      toast({ title: "Choose a plan first" });
      return;
    }
    setBusy(true);
    try {
      submitRenewalRequest({
        memberId: member.id,
        planId: plan.id,
        amount: plan.price,
        method: "upi",
        notes: reference,
      });
      toast({
        title: "Renewal submitted",
        description: "Your gym will verify the payment and extend your membership.",
      });
      setReference("");
    } catch (err) {
      toast({ title: "Could not submit", description: err.message });
    } finally {
      setBusy(false);
    }
  };

  return (
    <MemberShell>
      <PageHead
        eyebrow="Renewal"
        title="Renew membership"
        description="Pick a plan, pay by UPI, then submit the confirmation for gym verification."
      />

      {awaiting && (
        <div className="mb-4 rounded-xl border border-primary/30 bg-primary/5 px-4 py-3">
          <p className="text-[12.5px] font-semibold">Renewal awaiting verification</p>
          <p className="mt-1 text-[11.5px] text-muted-foreground">
            {money(awaiting.amount)} submitted on {fmtDate(awaiting.date)}. Your membership updates the
            moment the gym verifies it.
          </p>
        </div>
      )}

      <div className="grid gap-4 lg:grid-cols-[1fr_0.85fr]">
        <Panel title="Choose a plan">
          <div className="space-y-2">
            {plans.map((p) => (
              <button
                key={p.id}
                onClick={() => setPlanId(p.id)}
                className={`w-full rounded-xl border px-4 py-3 text-left transition-colors ${
                  planId === p.id ? "border-primary bg-primary/10" : "border-border hover:border-border/80"
                }`}
              >
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-[13px] font-semibold">{p.name}</p>
                    <p className="text-[11px] text-muted-foreground">{durationLabel(p.durationMonths)}</p>
                  </div>
                  <div className="text-right">
                    <p className="font-heading text-[15px] font-semibold">{money(p.price)}</p>
                    {planId === p.id && <Check className="ml-auto mt-1 h-3.5 w-3.5 text-primary" />}
                  </div>
                </div>
              </button>
            ))}
            {!plans.length && <p className="text-[12px] text-muted-foreground">Your gym has no active plans right now.</p>}
          </div>
        </Panel>

        <div className="space-y-4">
          <Panel title="Pay to your gym" subtitle="UPI">
            {gym?.upiQr ? (
              <img src={gym.upiQr} alt="Gym UPI QR" className="mx-auto h-48 w-48 rounded-xl border border-border object-contain p-2" />
            ) : (
              <div className="grid h-40 place-items-center rounded-xl border border-dashed border-border text-[11px] text-muted-foreground">
                The gym has not uploaded a QR yet
              </div>
            )}
            <div className="mt-4 space-y-1 text-center">
              <p className="text-[13px] font-semibold">{gym?.upiName || gym?.name}</p>
              <p className="text-[12px] text-muted-foreground">{gym?.upiId || "Ask the gym for their UPI ID"}</p>
              <p className="mt-2 font-heading text-lg font-semibold">{plan ? money(plan.price) : "—"}</p>
            </div>
          </Panel>

          <Panel title="Submit confirmation">
            <Field label="UPI reference / note (optional)">
              <Input
                value={reference}
                onChange={(e) => setReference(e.target.value)}
                placeholder="Transaction ID"
              />
            </Field>
            <p className="mt-3 flex items-start gap-2 text-[10.5px] leading-relaxed text-muted-foreground">
              <Info className="mt-0.5 h-3.5 w-3.5 shrink-0" />
              Paying by UPI does not mark your membership paid. The gym verifies each submission
              before your new expiry date is applied.
            </p>
            <Button className="mt-4 w-full" disabled={busy || !plan} onClick={submit}>
              {busy ? "Submitting…" : "SUBMIT RENEWAL PAYMENT"}
            </Button>
            {membership && plan && (
              <p className="mt-3 text-center text-[11px] text-muted-foreground">
                New expiry would be {fmtDate(addMonths(membership.expiryDate, plan.durationMonths))}
              </p>
            )}
            <p className="mt-3 text-center text-[10.5px] text-muted-foreground/80">
              Submitted {fmtDate(todayISO())}
            </p>
          </Panel>
        </div>
      </div>
    </MemberShell>
  );
}