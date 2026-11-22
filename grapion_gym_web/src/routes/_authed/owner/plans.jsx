import { useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { Pencil, Plus, Power } from "lucide-react";
import { OwnerShell } from "@/components/grapion/shells";
import { useRoleSession, useStore } from "@/lib/grapion/useGrapion";
import { PageHead, Panel, Pill, Empty } from "@/components/grapion/ui";
import { FormModal } from "@/components/grapion/FormModal";
import { Button } from "@/components/ui/button";
import { useToast } from "@/components/ui/use-toast";
import { durationLabel, money } from "@/lib/grapion/util";
import { savePlan, setRowStatus } from "@/lib/grapion/repo";

export const Route = createFileRoute("/_authed/owner/plans")({
  component: PlansPage,
  head: () => ({ meta: [{ title: "Membership plans · GRAPION GYM" }] }),
});

function PlansPage() {
  const session = useRoleSession();
  const db = useStore();
  const { toast } = useToast();
  const gymId = session?.gymId;
  const [creating, setCreating] = useState(false);
  const [editing, setEditing] = useState(null);

  const plans = db.membershipPlans.filter((p) => p.gymId === gymId);

  const fields = [
    { name: "name", label: "Package name", required: true, placeholder: "Monthly Gym Package" },
    {
      name: "durationMonths",
      label: "Duration (months)",
      type: "number",
      required: true,
      hint: "1, 3, 6 or 12 — any custom length also works.",
    },
    { name: "price", label: "Price (₹)", type: "number", required: true },
    { name: "description", label: "Description", type: "textarea" },
    {
      name: "status",
      label: "Status",
      type: "select",
      options: [
        { value: "active", label: "Active" },
        { value: "inactive", label: "Inactive" },
      ],
    },
  ];

  return (
    <OwnerShell>
      <PageHead
        eyebrow="Packages"
        title="Membership plans"
        description="Create the packages your members buy. Durations use real calendar months."
        actions={
          <Button size="sm" onClick={() => setCreating(true)}>
            <Plus className="mr-1.5 h-3.5 w-3.5" /> New plan
          </Button>
        }
      />

      {plans.length ? (
        <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
          {plans.map((plan) => {
            const activeCount = db.memberships.filter(
              (m) => m.planId === plan.id && m.status !== "cancelled",
            ).length;
            return (
              <div key={plan.id} className="flex flex-col rounded-2xl border border-border bg-card p-5">
                <div className="flex items-start justify-between gap-2">
                  <div>
                    <p className="font-heading text-[14px] font-semibold">{plan.name}</p>
                    <p className="mt-1 text-[11px] text-muted-foreground">
                      {durationLabel(plan.durationMonths)} · {activeCount} sold
                    </p>
                  </div>
                  <Pill tone={plan.status === "active" ? "green" : "gray"}>{plan.status}</Pill>
                </div>
                <p className="gp-num mt-4 font-heading text-2xl font-semibold">{money(plan.price)}</p>
                <p className="mt-2 flex-1 text-[11.5px] leading-relaxed text-muted-foreground">
                  {plan.description || "No description"}
                </p>
                <div className="mt-4 flex gap-2">
                  <Button size="sm" variant="outline" className="flex-1" onClick={() => setEditing(plan)}>
                    <Pencil className="mr-1.5 h-3 w-3" /> Edit
                  </Button>
                  <Button
                    size="sm"
                    variant="ghost"
                    onClick={() => {
                      setRowStatus("membershipPlans", plan.id, plan.status === "active" ? "inactive" : "active");
                      toast({ title: plan.status === "active" ? "Plan deactivated" : "Plan activated" });
                    }}
                  >
                    <Power className="h-3.5 w-3.5" />
                  </Button>
                </div>
              </div>
            );
          })}
        </div>
      ) : (
        <Empty
          title="No membership plans yet"
          hint="Create a monthly, quarterly or yearly package to start selling memberships."
          action={<Button size="sm" onClick={() => setCreating(true)}>Create plan</Button>}
        />
      )}

      <Panel className="mt-4" title="Pricing guidance">
        <p className="text-[12px] leading-relaxed text-muted-foreground">
          Sample market pricing: monthly ₹999, quarterly ₹2,499, half-yearly ₹4,499, yearly ₹7,999.
          These are only examples — set whatever your gym charges.
        </p>
      </Panel>

      <FormModal
        open={creating}
        onOpenChange={setCreating}
        title="Create membership plan"
        fields={fields}
        initial={{ durationMonths: "1", status: "active" }}
        submitLabel="Create plan"
        onSubmit={(values) => {
          savePlan({ ...values, gymId });
          toast({ title: "Plan created" });
        }}
      />

      <FormModal
        open={Boolean(editing)}
        onOpenChange={(open) => !open && setEditing(null)}
        title="Edit plan"
        fields={fields}
        initial={editing || {}}
        onSubmit={(values) => {
          savePlan({ ...values, id: editing.id, gymId });
          toast({ title: "Plan updated" });
        }}
      />
    </OwnerShell>
  );
}