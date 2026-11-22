import { useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { Pencil, Plus, Power, Trash2, UserPlus } from "lucide-react";
import { OwnerShell } from "@/components/grapion/shells";
import { useRoleSession, useStore } from "@/lib/grapion/useGrapion";
import { PageHead, Panel, Pill, Empty, Bar } from "@/components/grapion/ui";
import { FormModal } from "@/components/grapion/FormModal";
import { Button } from "@/components/ui/button";
import { useToast } from "@/components/ui/use-toast";
import { assignBatchMembers, deleteBatch, saveBatch, setRowStatus } from "@/lib/grapion/repo";

export const Route = createFileRoute("/_authed/owner/batches")({
  component: BatchesPage,
  head: () => ({ meta: [{ title: "Batches · GRAPION GYM" }] }),
});

function BatchesPage() {
  const session = useRoleSession();
  const db = useStore();
  const { toast } = useToast();
  const gymId = session?.gymId;
  const [creating, setCreating] = useState(false);
  const [editing, setEditing] = useState(null);
  const [assigning, setAssigning] = useState(null);

  const batches = db.batches.filter((b) => b.gymId === gymId);
  const trainers = db.trainers.filter((t) => t.gymId === gymId);
  const services = db.services.filter((s) => s.gymId === gymId);
  const members = db.gymMembers.filter((m) => m.gymId === gymId && m.status === "active");

  const fields = [
    { name: "name", label: "Batch name", required: true, placeholder: "Morning 6–7 AM" },
    { name: "startTime", label: "Start time", type: "time", required: true },
    { name: "endTime", label: "End time", type: "time", required: true },
    {
      name: "days",
      label: "Days",
      placeholder: "Mon,Tue,Wed,Thu,Fri,Sat",
      hint: "Comma separated day names.",
    },
    {
      name: "trainerId",
      label: "Trainer",
      type: "select",
      options: [{ value: "", label: "No trainer" }, ...trainers.map((t) => ({ value: t.id, label: t.name }))],
    },
    {
      name: "serviceId",
      label: "Service",
      type: "select",
      options: services.map((s) => ({ value: s.id, label: s.name })),
    },
    { name: "capacity", label: "Capacity", type: "number" },
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
        eyebrow="Scheduling"
        title="Batches"
        description="Group members into time slots with a trainer and a capacity."
        actions={
          <Button size="sm" onClick={() => setCreating(true)}>
            <Plus className="mr-1.5 h-3.5 w-3.5" /> Create batch
          </Button>
        }
      />

      {batches.length ? (
        <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
          {batches.map((batch) => {
            const roster = members.filter((m) => m.batchId === batch.id);
            const trainer = trainers.find((t) => t.id === batch.trainerId);
            return (
              <div key={batch.id} className="flex flex-col rounded-2xl border border-border bg-card p-5">
                <div className="flex items-start justify-between">
                  <div>
                    <p className="font-heading text-[14px] font-semibold">{batch.name}</p>
                    <p className="mt-1 text-[11px] text-muted-foreground">
                      {batch.startTime} – {batch.endTime}
                    </p>
                  </div>
                  <Pill tone={batch.status === "active" ? "green" : "gray"}>{batch.status}</Pill>
                </div>
                <p className="mt-3 text-[11px] text-muted-foreground">
                  {(batch.days || []).join(" · ") || "No days set"}
                </p>
                <p className="mt-1 text-[11.5px]">
                  {trainer ? trainer.name : "No trainer"} ·{" "}
                  {services.find((s) => s.id === batch.serviceId)?.name || "Gym"}
                </p>
                <div className="mt-3">
                  <div className="flex items-center justify-between text-[10.5px] text-muted-foreground">
                    <span>{roster.length} assigned</span>
                    <span>capacity {batch.capacity || "—"}</span>
                  </div>
                  <div className="mt-1.5">
                    <Bar value={roster.length} max={batch.capacity || roster.length || 1} />
                  </div>
                </div>
                <div className="mt-4 flex flex-wrap gap-1.5">
                  <Button size="sm" variant="outline" onClick={() => setAssigning(batch)}>
                    <UserPlus className="mr-1.5 h-3 w-3" /> Assign
                  </Button>
                  <Button size="sm" variant="ghost" onClick={() => setEditing(batch)}>
                    <Pencil className="h-3.5 w-3.5" />
                  </Button>
                  <Button
                    size="sm"
                    variant="ghost"
                    onClick={() => setRowStatus("batches", batch.id, batch.status === "active" ? "inactive" : "active")}
                  >
                    <Power className="h-3.5 w-3.5" />
                  </Button>
                  <Button
                    size="sm"
                    variant="ghost"
                    onClick={() => {
                      if (!window.confirm(`Delete ${batch.name}? Assigned members stay in the gym.`)) return;
                      deleteBatch(batch.id);
                      toast({ title: "Batch deleted" });
                    }}
                  >
                    <Trash2 className="h-3.5 w-3.5 text-red-400" />
                  </Button>
                </div>
              </div>
            );
          })}
        </div>
      ) : (
        <Empty
          title="No batches yet"
          hint="Create a morning or evening slot to organise your members."
          action={<Button size="sm" onClick={() => setCreating(true)}>Create batch</Button>}
        />
      )}

      <Panel className="mt-4" title="Batch roster" subtitle="Members currently assigned to each batch">
        <div className="space-y-3">
          {batches.map((batch) => {
            const roster = members.filter((m) => m.batchId === batch.id);
            return (
              <div key={batch.id}>
                <p className="text-[12px] font-medium">{batch.name}</p>
                <p className="text-[11px] text-muted-foreground">
                  {roster.length ? roster.map((m) => m.name).join(", ") : "No members assigned"}
                </p>
              </div>
            );
          })}
          {!batches.length && <Empty title="Nothing to show yet" />}
        </div>
      </Panel>

      <FormModal
        open={creating}
        onOpenChange={setCreating}
        title="Create batch"
        fields={fields}
        initial={{ capacity: "30", status: "active", days: "Mon,Tue,Wed,Thu,Fri,Sat" }}
        submitLabel="Create batch"
        onSubmit={(values) => {
          saveBatch({ ...values, gymId });
          toast({ title: "Batch created" });
        }}
      />

      <FormModal
        open={Boolean(editing)}
        onOpenChange={(open) => !open && setEditing(null)}
        title="Edit batch"
        fields={fields}
        initial={editing ? { ...editing, days: (editing.days || []).join(",") } : {}}
        onSubmit={(values) => {
          saveBatch({ ...values, id: editing.id, gymId });
          toast({ title: "Batch updated" });
        }}
      />

      <FormModal
        open={Boolean(assigning)}
        onOpenChange={(open) => !open && setAssigning(null)}
        title={`Assign members to ${assigning?.name || ""}`}
        description="Comma separated member IDs are not needed — pick from the list below and save."
        fields={[
          {
            name: "memberIds",
            label: "Members to add",
            type: "select",
            options: members.map((m) => ({ value: m.id, label: `${m.name} · ${m.code}` })),
            hint: "This assigns one member per save. Repeat for more members.",
          },
        ]}
        submitLabel="Assign member"
        onSubmit={(values) => {
          if (!values.memberIds) throw new Error("Choose a member.");
          assignBatchMembers([values.memberIds], assigning.id);
          toast({ title: "Member assigned to batch" });
        }}
      />
    </OwnerShell>
  );
}