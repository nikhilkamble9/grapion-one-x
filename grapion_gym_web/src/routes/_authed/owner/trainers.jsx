import { useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { Pencil, Plus, Power } from "lucide-react";
import { OwnerShell } from "@/components/grapion/shells";
import { useRoleSession, useStore } from "@/lib/grapion/useGrapion";
import { PageHead, Panel, Pill, Photo, Empty } from "@/components/grapion/ui";
import { FormModal } from "@/components/grapion/FormModal";
import { Button } from "@/components/ui/button";
import { useToast } from "@/components/ui/use-toast";
import { fmtDate } from "@/lib/grapion/util";
import { saveTrainer, setRowStatus } from "@/lib/grapion/repo";

export const Route = createFileRoute("/_authed/owner/trainers")({
  component: TrainersPage,
  head: () => ({ meta: [{ title: "Trainers · GRAPION GYM" }] }),
});

function TrainersPage() {
  const session = useRoleSession();
  const db = useStore();
  const { toast } = useToast();
  const gymId = session?.gymId;
  const [creating, setCreating] = useState(false);
  const [editing, setEditing] = useState(null);

  const trainers = db.trainers.filter((t) => t.gymId === gymId);
  const batches = db.batches.filter((b) => b.gymId === gymId);

  const fields = [
    { name: "name", label: "Trainer name", required: true },
    { name: "photo", label: "Photo", type: "photo" },
    { name: "phone", label: "Phone" },
    { name: "email", label: "Email", type: "email" },
    { name: "specialization", label: "Specialisation", placeholder: "Strength, Yoga, Zumba…" },
    { name: "joiningDate", label: "Joining date", type: "date" },
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
        eyebrow="Team"
        title="Trainers"
        description="Manage your coaching team and see which batches they run."
        actions={
          <Button size="sm" onClick={() => setCreating(true)}>
            <Plus className="mr-1.5 h-3.5 w-3.5" /> Add trainer
          </Button>
        }
      />

      {trainers.length ? (
        <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
          {trainers.map((trainer) => {
            const assigned = batches.filter((b) => b.trainerId === trainer.id);
            const memberCount = db.gymMembers.filter(
              (m) => m.gymId === gymId && assigned.some((b) => b.id === m.batchId),
            ).length;
            return (
              <div key={trainer.id} className="rounded-2xl border border-border bg-card p-5">
                <div className="flex items-center gap-3">
                  <Photo src={trainer.photo} name={trainer.name} size={44} />
                  <div className="min-w-0 flex-1">
                    <p className="truncate font-heading text-[13.5px] font-semibold">{trainer.name}</p>
                    <p className="truncate text-[11px] text-muted-foreground">{trainer.specialization || "Trainer"}</p>
                  </div>
                  <Pill tone={trainer.status === "active" ? "green" : "gray"}>{trainer.status}</Pill>
                </div>
                <div className="mt-3 space-y-1 text-[11px] text-muted-foreground">
                  <p>{trainer.phone || "No phone"}{trainer.email ? ` · ${trainer.email}` : ""}</p>
                  <p>Joined {fmtDate(trainer.joiningDate)}</p>
                  <p>
                    {assigned.length} batches · {memberCount} members
                  </p>
                  {assigned.length > 0 && <p className="text-foreground/70">{assigned.map((b) => b.name).join(", ")}</p>}
                </div>
                <div className="mt-4 flex gap-1.5">
                  <Button size="sm" variant="outline" className="flex-1" onClick={() => setEditing(trainer)}>
                    <Pencil className="mr-1.5 h-3 w-3" /> Edit
                  </Button>
                  <Button
                    size="sm"
                    variant="ghost"
                    onClick={() => {
                      setRowStatus("trainers", trainer.id, trainer.status === "active" ? "inactive" : "active");
                      toast({ title: trainer.status === "active" ? "Trainer deactivated" : "Trainer activated" });
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
        <Empty title="No trainers yet" hint="Add your coaching staff to assign them to batches." />
      )}

      <Panel className="mt-4" title="Batch assignments">
        <div className="space-y-2">
          {batches.map((batch) => (
            <div key={batch.id} className="flex items-center justify-between text-[12px]">
              <span>{batch.name}</span>
              <span className="text-muted-foreground">
                {trainers.find((t) => t.id === batch.trainerId)?.name || "Unassigned"}
              </span>
            </div>
          ))}
          {!batches.length && <Empty title="No batches created yet" />}
        </div>
      </Panel>

      <FormModal
        open={creating}
        onOpenChange={setCreating}
        title="Add trainer"
        fields={fields}
        initial={{ status: "active" }}
        submitLabel="Add trainer"
        onSubmit={(values) => {
          saveTrainer({ ...values, gymId });
          toast({ title: "Trainer added" });
        }}
      />

      <FormModal
        open={Boolean(editing)}
        onOpenChange={(open) => !open && setEditing(null)}
        title="Edit trainer"
        fields={fields}
        initial={editing || {}}
        onSubmit={(values) => {
          saveTrainer({ ...values, id: editing.id, gymId });
          toast({ title: "Trainer updated" });
        }}
      />
    </OwnerShell>
  );
}