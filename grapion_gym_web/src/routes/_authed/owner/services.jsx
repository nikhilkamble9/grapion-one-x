import { useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { Pencil, Plus, Power } from "lucide-react";
import { OwnerShell } from "@/components/grapion/shells";
import { useRoleSession, useStore } from "@/lib/grapion/useGrapion";
import { PageHead, Panel, Pill, Empty } from "@/components/grapion/ui";
import { FormModal } from "@/components/grapion/FormModal";
import { Button } from "@/components/ui/button";
import { useToast } from "@/components/ui/use-toast";
import { saveService, setRowStatus } from "@/lib/grapion/repo";

export const Route = createFileRoute("/_authed/owner/services")({
  component: ServicesPage,
  head: () => ({ meta: [{ title: "Services · GRAPION GYM" }] }),
});

function ServicesPage() {
  const session = useRoleSession();
  const db = useStore();
  const { toast } = useToast();
  const gymId = session?.gymId;
  const [creating, setCreating] = useState(false);
  const [editing, setEditing] = useState(null);

  const services = db.services.filter((s) => s.gymId === gymId);
  const plans = db.membershipPlans.filter((p) => p.gymId === gymId);

  const fields = [
    { name: "name", label: "Service name", required: true, placeholder: "Steam Bath" },
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
        eyebrow="Offerings"
        title="Gym services"
        description="What your gym offers. Services can be attached to membership plans."
        actions={
          <Button size="sm" onClick={() => setCreating(true)}>
            <Plus className="mr-1.5 h-3.5 w-3.5" /> Add service
          </Button>
        }
      />

      <div className="grid gap-4 lg:grid-cols-[1.1fr_0.9fr]">
        <Panel title={`${services.length} services`}>
          {services.length ? (
            <ul className="space-y-3">
              {services.map((service) => {
                const usedIn = plans.filter((p) => (p.services || []).includes(service.id));
                return (
                  <li key={service.id} className="flex items-start justify-between gap-3 border-b border-border/60 pb-3 last:border-0 last:pb-0">
                    <div className="min-w-0">
                      <p className="text-[12.5px] font-medium">{service.name}</p>
                      <p className="text-[11px] text-muted-foreground">
                        {service.description || "No description"}
                      </p>
                      <p className="mt-1 text-[10.5px] text-muted-foreground/80">
                        {usedIn.length ? `In ${usedIn.map((p) => p.name).join(", ")}` : "Not linked to a plan"}
                      </p>
                    </div>
                    <div className="flex shrink-0 items-center gap-1">
                      <Pill tone={service.status === "active" ? "green" : "gray"}>{service.status}</Pill>
                      <Button size="icon" variant="ghost" onClick={() => setEditing(service)}>
                        <Pencil className="h-3.5 w-3.5" />
                      </Button>
                      <Button
                        size="icon"
                        variant="ghost"
                        onClick={() => {
                          setRowStatus("services", service.id, service.status === "active" ? "inactive" : "active");
                          toast({ title: "Service updated" });
                        }}
                      >
                        <Power className="h-3.5 w-3.5" />
                      </Button>
                    </div>
                  </li>
                );
              })}
            </ul>
          ) : (
            <Empty title="No services yet" hint="Gym, cardio, yoga, zumba and steam bath are good defaults." />
          )}
        </Panel>

        <Panel title="Services in plans" subtitle="Which packages include which service">
          <div className="space-y-3">
            {plans.map((plan) => (
              <div key={plan.id}>
                <p className="text-[12px] font-medium">{plan.name}</p>
                <p className="text-[11px] text-muted-foreground">
                  {(plan.services || []).length
                    ? plan.services
                        .map((id) => services.find((s) => s.id === id)?.name)
                        .filter(Boolean)
                        .join(", ")
                    : "No services linked"}
                </p>
              </div>
            ))}
            {!plans.length && <Empty title="No plans yet" />}
          </div>
        </Panel>
      </div>

      <FormModal
        open={creating}
        onOpenChange={setCreating}
        title="Add service"
        fields={fields}
        initial={{ status: "active" }}
        submitLabel="Add service"
        onSubmit={(values) => {
          saveService({ ...values, gymId });
          toast({ title: "Service added" });
        }}
      />

      <FormModal
        open={Boolean(editing)}
        onOpenChange={(open) => !open && setEditing(null)}
        title="Edit service"
        fields={fields}
        initial={editing || {}}
        onSubmit={(values) => {
          saveService({ ...values, id: editing.id, gymId });
          toast({ title: "Service updated" });
        }}
      />
    </OwnerShell>
  );
}