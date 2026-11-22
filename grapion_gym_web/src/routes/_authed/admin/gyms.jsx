import { useState } from "react";
import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { Eye, Pencil, Plus, Power, Search, LogIn } from "lucide-react";
import { AdminShell } from "@/components/grapion/shells";
import { useStore } from "@/lib/grapion/useGrapion";
import { PageHead, Panel, Pill, KeyValue } from "@/components/grapion/ui";
import { DataTable } from "@/components/grapion/DataTable";
import { FormModal } from "@/components/grapion/FormModal";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { useToast } from "@/components/ui/use-toast";
import { fmtDate, money, subscriptionStatus } from "@/lib/grapion/util";
import { createGym, updateGym, setGymStatus, ownerOf, subscriptionOf } from "@/lib/grapion/repo";
import { setSession } from "@/lib/grapion/session";

export const Route = createFileRoute("/_authed/admin/gyms")({
  component: ManageGyms,
  head: () => ({ meta: [{ title: "Manage gyms · GRAPION GYM" }] }),
});

const cycleOptions = [
  { value: "monthly", label: "Monthly" },
  { value: "quarterly", label: "Quarterly" },
  { value: "halfYearly", label: "Half-yearly" },
  { value: "yearly", label: "Yearly" },
];

const createFields = [
  { name: "name", label: "Gym name", required: true, placeholder: "Iron Temple Fitness" },
  { name: "phone", label: "Gym phone", placeholder: "98220 11223" },
  { name: "email", label: "Gym email", type: "email", placeholder: "hello@gym.com" },
  { name: "city", label: "City", placeholder: "Indore" },
  { name: "address", label: "Address", type: "textarea", placeholder: "Street, area, landmark" },
  { name: "ownerName", label: "Owner name", required: true, placeholder: "Full name" },
  { name: "ownerEmail", label: "Owner email", type: "email", required: true, placeholder: "owner@gym.com" },
  {
    name: "ownerPassword",
    label: "Initial owner password",
    type: "password",
    required: true,
    hint: "Given to the owner for their local demo sign-in. They can change it later.",
  },
  { name: "cycle", label: "Subscription plan", type: "select", options: cycleOptions },
  { name: "startDate", label: "Subscription start", type: "date" },
  {
    name: "expiryDate",
    label: "Subscription expiry",
    type: "date",
    value: "",
    hint: "Leave empty to use the selected plan length.",
  },
  {
    name: "status",
    label: "Gym status",
    type: "select",
    options: [
      { value: "active", label: "Active" },
      { value: "inactive", label: "Inactive" },
    ],
  },
];

function ManageGyms() {
  const db = useStore();
  const navigate = useNavigate();
  const { toast } = useToast();
  const [search, setSearch] = useState("");
  const [filter, setFilter] = useState("all");
  const [creating, setCreating] = useState(false);
  const [editing, setEditing] = useState(null);
  const [viewing, setViewing] = useState(null);

  const rows = db.gyms.filter((gym) => {
    const matchSearch = `${gym.name} ${gym.city} ${gym.email}`.toLowerCase().includes(search.toLowerCase());
    const matchFilter = filter === "all" || gym.status === filter;
    return matchSearch && matchFilter;
  });

  const openWorkspace = (gym) => {
    const owner = ownerOf(db, gym.id);
    if (!owner) {
      toast({ title: "No owner account", description: "Create an owner before opening this workspace." });
      return;
    }
    if (!window.confirm(`Open ${gym.name} as its owner? You can return by logging out.`)) return;
    setSession({
      role: "owner",
      ownerId: owner.id,
      gymId: gym.id,
      name: owner.name,
      email: owner.email,
      gymName: gym.name,
      at: new Date().toISOString(),
      viaAdmin: true,
    });
    navigate({ to: "/owner" });
  };

  return (
    <AdminShell>
      <PageHead
        eyebrow="Gyms"
        title="Manage gyms"
        description="Onboard gyms, control their status and inspect each subscription."
        actions={
          <Button size="sm" onClick={() => setCreating(true)}>
            <Plus className="mr-1.5 h-3.5 w-3.5" /> Add gym
          </Button>
        }
      />

      <Panel
        bodyClass="p-5"
        title={`${rows.length} of ${db.gyms.length} gyms`}
        action={
          <div className="flex flex-wrap items-center gap-2">
            <div className="relative">
              <Search className="absolute left-2.5 top-2.5 h-3.5 w-3.5 text-muted-foreground" />
              <Input
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder="Search gyms"
                className="h-9 w-[170px] pl-8 text-[12px]"
              />
            </div>
            <select
              value={filter}
              onChange={(e) => setFilter(e.target.value)}
              className="h-9 rounded-md border border-input bg-transparent px-2 text-[12px]"
            >
              <option value="all">All statuses</option>
              <option value="active">Active</option>
              <option value="suspended">Suspended</option>
              <option value="inactive">Inactive</option>
            </select>
          </div>
        }
      >
        <DataTable
          empty="No gyms match this view"
          rows={rows}
          columns={[
            {
              key: "gym",
              label: "Gym",
              render: (row) => (
                <div>
                  <p className="font-medium">{row.name}</p>
                  <p className="text-[11px] text-muted-foreground">{row.city || "—"}</p>
                </div>
              ),
            },
            {
              key: "owner",
              label: "Owner",
              render: (row) => {
                const owner = ownerOf(db, row.id);
                return (
                  <div>
                    <p>{owner?.name || "—"}</p>
                    <p className="text-[11px] text-muted-foreground">{owner?.email || "no owner"}</p>
                  </div>
                );
              },
            },
            {
              key: "members",
              label: "Members",
              render: (row) => db.gymMembers.filter((m) => m.gymId === row.id).length,
            },
            {
              key: "subscription",
              label: "Subscription",
              render: (row) => {
                const sub = subscriptionOf(db, row.id);
                const st = subscriptionStatus(sub?.expiryDate, row.status);
                return (
                  <div className="space-y-1">
                    <Pill tone={st.tone}>{st.label}</Pill>
                    <p className="text-[10.5px] text-muted-foreground">
                      {sub ? fmtDate(sub.expiryDate) : "not set"}
                    </p>
                  </div>
                );
              },
            },
            { key: "createdAt", label: "Registered", render: (row) => fmtDate(row.createdAt) },
            {
              key: "actions",
              label: "",
              align: "right",
              render: (row) => (
                <div className="flex justify-end gap-1">
                  <Button size="icon" variant="ghost" title="View" onClick={() => setViewing(row)}>
                    <Eye className="h-3.5 w-3.5" />
                  </Button>
                  <Button size="icon" variant="ghost" title="Edit" onClick={() => setEditing(row)}>
                    <Pencil className="h-3.5 w-3.5" />
                  </Button>
                  <Button
                    size="icon"
                    variant="ghost"
                    title={row.status === "active" ? "Suspend" : "Activate"}
                    onClick={() => setGymStatus(row.id, row.status === "active" ? "suspended" : "active")}
                  >
                    <Power className="h-3.5 w-3.5" />
                  </Button>
                  <Button size="icon" variant="ghost" title="Open workspace" onClick={() => openWorkspace(row)}>
                    <LogIn className="h-3.5 w-3.5" />
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
        title="Add a new gym"
        description="Creates the gym, its owner login, default services, membership plans and subscription."
        fields={createFields}
        submitLabel="Create gym"
        onSubmit={(values) => {
          createGym(values);
          toast({ title: "Gym created", description: `${values.name} is ready to use.` });
        }}
      />

      <FormModal
        open={Boolean(editing)}
        onOpenChange={(open) => !open && setEditing(null)}
        title="Edit gym"
        fields={[
          { name: "name", label: "Gym name", required: true },
          { name: "phone", label: "Gym phone" },
          { name: "email", label: "Gym email", type: "email" },
          { name: "city", label: "City" },
          { name: "address", label: "Address", type: "textarea" },
          {
            name: "status",
            label: "Status",
            type: "select",
            options: [
              { value: "active", label: "Active" },
              { value: "suspended", label: "Suspended" },
              { value: "inactive", label: "Inactive" },
            ],
          },
        ]}
        initial={editing || {}}
        onSubmit={(values) => {
          updateGym(editing.id, values);
          toast({ title: "Gym updated" });
        }}
      />

      <Dialog open={Boolean(viewing)} onOpenChange={(open) => !open && setViewing(null)}>
        <DialogContent className="sm:max-w-[520px]">
          <DialogHeader>
            <DialogTitle className="font-heading">{viewing?.name}</DialogTitle>
          </DialogHeader>
          {viewing && (
            <div className="grid gap-x-6 sm:grid-cols-2">
              <KeyValue label="Owner" value={ownerOf(db, viewing.id)?.name} />
              <KeyValue label="Owner email" value={ownerOf(db, viewing.id)?.email} />
              <KeyValue label="Phone" value={viewing.phone} />
              <KeyValue label="Email" value={viewing.email} />
              <KeyValue label="City" value={viewing.city} />
              <KeyValue label="Registered" value={fmtDate(viewing.createdAt)} />
              <KeyValue label="Members" value={String(db.gymMembers.filter((m) => m.gymId === viewing.id).length)} />
              <KeyValue
                label="Subscription expiry"
                value={fmtDate(subscriptionOf(db, viewing.id)?.expiryDate)}
              />
              <KeyValue
                label="Monthly collection"
                value={money(
                  db.payments
                    .filter((p) => p.gymId === viewing.id && p.status === "verified")
                    .reduce((s, p) => s + Number(p.amount || 0), 0),
                )}
              />
              <KeyValue label="Status" value={viewing.status} />
            </div>
          )}
        </DialogContent>
      </Dialog>
    </AdminShell>
  );
}