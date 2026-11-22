import { useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { KeyRound, Pencil, Plus, Power } from "lucide-react";
import { AdminShell } from "@/components/grapion/shells";
import { useStore } from "@/lib/grapion/useGrapion";
import { PageHead, Panel, Pill } from "@/components/grapion/ui";
import { DataTable } from "@/components/grapion/DataTable";
import { FormModal } from "@/components/grapion/FormModal";
import { Button } from "@/components/ui/button";
import { useToast } from "@/components/ui/use-toast";
import { fmtDate } from "@/lib/grapion/util";
import { findGym, resetOwnerPassword, saveOwner } from "@/lib/grapion/repo";

export const Route = createFileRoute("/_authed/admin/owners")({
  component: GymOwners,
  head: () => ({ meta: [{ title: "Gym owners · GRAPION GYM" }] }),
});

function GymOwners() {
  const db = useStore();
  const { toast } = useToast();
  const [creating, setCreating] = useState(false);
  const [editing, setEditing] = useState(null);
  const [resetting, setResetting] = useState(null);

  const gymOptions = db.gyms.map((g) => ({ value: g.id, label: g.name }));

  const baseFields = [
    { name: "name", label: "Owner name", required: true },
    { name: "email", label: "Email", type: "email", required: true },
    { name: "phone", label: "Phone" },
    { name: "gymId", label: "Assigned gym", type: "select", options: gymOptions },
  ];

  return (
    <AdminShell>
      <PageHead
        eyebrow="Accounts"
        title="Gym owners"
        description="Owner accounts are created here and bound to a single gym workspace."
        actions={
          <Button size="sm" onClick={() => setCreating(true)} disabled={!db.gyms.length}>
            <Plus className="mr-1.5 h-3.5 w-3.5" /> Create owner
          </Button>
        }
      />

      <Panel title={`${db.gymOwners.length} owner accounts`}>
        <DataTable
          empty="No owner accounts yet"
          emptyHint="Create a gym first — its owner login is generated automatically."
          rows={db.gymOwners}
          columns={[
            {
              key: "name",
              label: "Owner",
              render: (row) => (
                <div>
                  <p className="font-medium">{row.name}</p>
                  <p className="text-[11px] text-muted-foreground">{row.email}</p>
                </div>
              ),
            },
            { key: "phone", label: "Phone" },
            {
              key: "gym",
              label: "Assigned gym",
              render: (row) => findGym(db, row.gymId)?.name || "—",
            },
            { key: "createdAt", label: "Added", render: (row) => fmtDate(row.createdAt) },
            {
              key: "status",
              label: "Status",
              render: (row) => (
                <Pill tone={row.status === "active" ? "green" : "gray"}>{row.status}</Pill>
              ),
            },
            {
              key: "actions",
              label: "",
              align: "right",
              render: (row) => (
                <div className="flex justify-end gap-1">
                  <Button size="icon" variant="ghost" title="Edit" onClick={() => setEditing(row)}>
                    <Pencil className="h-3.5 w-3.5" />
                  </Button>
                  <Button size="icon" variant="ghost" title="Reset access" onClick={() => setResetting(row)}>
                    <KeyRound className="h-3.5 w-3.5" />
                  </Button>
                  <Button
                    size="icon"
                    variant="ghost"
                    title={row.status === "active" ? "Deactivate" : "Activate"}
                    onClick={() => {
                      saveOwner({ ...row, status: row.status === "active" ? "inactive" : "active" });
                      toast({ title: row.status === "active" ? "Owner deactivated" : "Owner activated" });
                    }}
                  >
                    <Power className="h-3.5 w-3.5" />
                  </Button>
                </div>
              ),
            },
          ]}
        />
      </Panel>

      <FormModal
        open={creating}
        onOpenChange={setCreating}
        title="Create gym owner"
        fields={[
          ...baseFields,
          {
            name: "password",
            label: "Initial password",
            type: "password",
            required: true,
            hint: "Share this with the owner for the local demo sign-in.",
          },
        ]}
        submitLabel="Create owner"
        onSubmit={(values) => {
          saveOwner(values);
          toast({ title: "Owner created" });
        }}
      />

      <FormModal
        open={Boolean(editing)}
        onOpenChange={(open) => !open && setEditing(null)}
        title="Edit owner"
        fields={[...baseFields, { name: "password", label: "New password (optional)", type: "password" }]}
        initial={editing || {}}
        onSubmit={(values) => {
          saveOwner({ ...values, id: editing.id });
          toast({ title: "Owner updated" });
        }}
      />

      <FormModal
        open={Boolean(resetting)}
        onOpenChange={(open) => !open && setResetting(null)}
        title="Reset owner access"
        description={`Set a new demo password for ${resetting?.name || ""}.`}
        fields={[{ name: "password", label: "New password", type: "password", required: true }]}
        submitLabel="Reset access"
        onSubmit={(values) => {
          resetOwnerPassword(resetting.id, values.password);
          toast({ title: "Access reset", description: "Share the new password with the owner." });
        }}
      />
    </AdminShell>
  );
}