import { useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { Eye, MessageCircle, Pencil, Plus, Power, RefreshCw, Search } from "lucide-react";
import { OwnerShell } from "@/components/grapion/shells";
import { useRoleSession, useStore } from "@/lib/grapion/useGrapion";
import { PageHead, Panel, Pill, Photo } from "@/components/grapion/ui";
import { DataTable } from "@/components/grapion/DataTable";
import { FormModal } from "@/components/grapion/FormModal";
import { MemberDetail } from "@/components/grapion/MemberDetail";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { useToast } from "@/components/ui/use-toast";
import { fmtDate, money, waLink } from "@/lib/grapion/util";
import { createMember, memberView, renewMembership, updateMember } from "@/lib/grapion/repo";

export const Route = createFileRoute("/_authed/owner/members")({
  component: MembersPage,
  head: () => ({ meta: [{ title: "Members · GRAPION GYM" }] }),
});

const methodOptions = [
  { value: "cash", label: "Cash" },
  { value: "upi", label: "UPI" },
  { value: "other", label: "Other" },
];

function MembersPage() {
  const session = useRoleSession();
  const db = useStore();
  const { toast } = useToast();
  const gymId = session?.gymId;
  const [search, setSearch] = useState("");
  const [filter, setFilter] = useState("all");
  const [adding, setAdding] = useState(false);
  const [editing, setEditing] = useState(null);
  const [renewing, setRenewing] = useState(null);
  const [viewing, setViewing] = useState(null);

  const plans = db.membershipPlans.filter((p) => p.gymId === gymId && p.status === "active");
  const batches = db.batches.filter((b) => b.gymId === gymId && b.status === "active");

  const rows = db.gymMembers
    .filter((m) => m.gymId === gymId)
    .map((m) => memberView(db, m.id))
    .filter((v) => {
      const match = `${v.member.name} ${v.member.code} ${v.member.phone} ${v.member.email}`
        .toLowerCase()
        .includes(search.toLowerCase());
      const statusMatch =
        filter === "all" ||
        (filter === "inactive" ? v.member.status !== "active" : v.status.key === filter);
      return match && statusMatch;
    });

  const planOptions = plans.map((p) => ({ value: p.id, label: `${p.name} · ${money(p.price)}` }));
  const batchOptions = [{ value: "", label: "No batch" }, ...batches.map((b) => ({ value: b.id, label: b.name }))];

  const personalFields = [
    { name: "name", label: "Full name", required: true },
    { name: "photo", label: "Profile photo", type: "photo" },
    { name: "phone", label: "Mobile number", required: true },
    { name: "email", label: "Email" },
    {
      name: "gender",
      label: "Gender",
      type: "select",
      options: [
        { value: "", label: "Not specified" },
        { value: "Male", label: "Male" },
        { value: "Female", label: "Female" },
        { value: "Other", label: "Other" },
      ],
    },
    { name: "dob", label: "Date of birth", type: "date", value: "" },
    { name: "occupation", label: "Occupation" },
    { name: "address", label: "Address" },
    { name: "emergencyContact", label: "Emergency contact" },
    { name: "notes", label: "Notes", type: "textarea" },
  ];

  return (
    <OwnerShell>
      <PageHead
        eyebrow="Members"
        title="Member management"
        description="Add members, assign plans, renew memberships and keep contact details current."
        actions={
          <Button size="sm" onClick={() => setAdding(true)}>
            <Plus className="mr-1.5 h-3.5 w-3.5" /> Add member
          </Button>
        }
      />

      <Panel
        title={`${rows.length} members`}
        action={
          <div className="flex flex-wrap items-center gap-2">
            <div className="relative">
              <Search className="absolute left-2.5 top-2.5 h-3.5 w-3.5 text-muted-foreground" />
              <Input
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder="Search members"
                className="h-9 w-[180px] pl-8 text-[12px]"
              />
            </div>
            <select
              value={filter}
              onChange={(e) => setFilter(e.target.value)}
              className="h-9 rounded-md border border-input bg-transparent px-2 text-[12px]"
            >
              <option value="all">All</option>
              <option value="active">Active</option>
              <option value="expiring">Expiring</option>
              <option value="expired">Expired</option>
              <option value="none">No plan</option>
              <option value="inactive">Deactivated</option>
            </select>
          </div>
        }
      >
        <DataTable
          empty="No members match this view"
          emptyHint="Add a member to start tracking memberships and attendance."
          rows={rows}
          columns={[
            {
              key: "member",
              label: "Member",
              render: ({ member }) => (
                <div className="flex items-center gap-2.5">
                  <Photo src={member.photo} name={member.name} size={32} />
                  <div className="min-w-0">
                    <p className="truncate font-medium">{member.name}</p>
                    <p className="text-[10.5px] text-muted-foreground">{member.code}</p>
                  </div>
                </div>
              ),
            },
            { key: "phone", label: "Mobile", render: ({ member }) => member.phone || "—" },
            {
              key: "plan",
              label: "Plan",
              render: ({ plan, status }) => (
                <div>
                  <p className="text-[12px]">{plan?.name || "No plan"}</p>
                  <p className="text-[10.5px] text-muted-foreground">
                    {status.key === "none" ? "—" : status.label}
                  </p>
                </div>
              ),
            },
            {
              key: "expiry",
              label: "Expiry",
              render: ({ membership }) => (membership ? fmtDate(membership.expiryDate) : "—"),
            },
            {
              key: "payment",
              label: "Payment",
              render: ({ total, paid, pending }) => (
                <div>
                  <p className="text-[12px]">{money(paid)} / {money(total)}</p>
                  <p className={`text-[10.5px] ${pending > 0 ? "text-amber-400" : "text-muted-foreground"}`}>
                    {pending > 0 ? `${money(pending)} pending` : "Fully paid"}
                  </p>
                </div>
              ),
            },
            {
              key: "status",
              label: "Status",
              render: ({ status, member }) => (
                <div className="space-y-1">
                  <Pill tone={status.tone}>{status.label}</Pill>
                  {member.status !== "active" && <p className="text-[10px] text-muted-foreground">deactivated</p>}
                </div>
              ),
            },
            {
              key: "actions",
              label: "",
              align: "right",
              render: ({ member }) => {
                const gym = db.gyms.find((g) => g.id === gymId);
                return (
                  <div className="flex justify-end gap-1">
                    <Button size="icon" variant="ghost" title="View" onClick={() => setViewing(member.id)}>
                      <Eye className="h-3.5 w-3.5" />
                    </Button>
                    <Button size="icon" variant="ghost" title="Edit" onClick={() => setEditing(member)}>
                      <Pencil className="h-3.5 w-3.5" />
                    </Button>
                    <Button size="icon" variant="ghost" title="Renew" onClick={() => setRenewing(member)}>
                      <RefreshCw className="h-3.5 w-3.5" />
                    </Button>
                    {member.phone && (
                      <Button asChild size="icon" variant="ghost" title="WhatsApp">
                        <a
                          href={waLink(
                            member.phone,
                            `Hi ${member.name.split(" ")[0]}, this is ${gym?.name || "your gym"}.`,
                          )}
                          target="_blank"
                          rel="noreferrer"
                        >
                          <MessageCircle className="h-3.5 w-3.5" />
                        </a>
                      </Button>
                    )}
                    <Button
                      size="icon"
                      variant="ghost"
                      title={member.status === "active" ? "Deactivate" : "Activate"}
                      onClick={() => {
                        updateMember(member.id, { status: member.status === "active" ? "inactive" : "active" });
                        toast({ title: member.status === "active" ? "Member deactivated" : "Member activated" });
                      }}
                    >
                      <Power className="h-3.5 w-3.5" />
                    </Button>
                  </div>
                );
              },
            },
          ]}
        />
      </Panel>

      <FormModal
        open={adding}
        onOpenChange={setAdding}
        title="Add member"
        description="Creates the member, their login and (optionally) their first membership."
        fields={[
          ...personalFields,
          { name: "password", label: "Login password", hint: "Member signs in with this password." },
          { name: "planId", label: "Membership plan", type: "select", options: planOptions },
          { name: "batchId", label: "Batch", type: "select", options: batchOptions },
          { name: "startDate", label: "Membership start", type: "date" },
          { name: "paidAmount", label: "Amount paid now", type: "number" },
          { name: "method", label: "Payment method", type: "select", options: methodOptions },
        ]}
        submitLabel="Add member"
        onSubmit={(values) => {
          createMember({ ...values, gymId, by: session.name });
          toast({ title: "Member added", description: `${values.name} can now sign in.` });
        }}
      />

      <FormModal
        open={Boolean(editing)}
        onOpenChange={(open) => !open && setEditing(null)}
        title="Edit member"
        fields={[
          ...personalFields,
          { name: "batchId", label: "Batch", type: "select", options: batchOptions },
          {
            name: "status",
            label: "Account status",
            type: "select",
            options: [
              { value: "active", label: "Active" },
              { value: "inactive", label: "Deactivated" },
            ],
          },
        ]}
        initial={editing || {}}
        onSubmit={(values) => {
          updateMember(editing.id, values);
          toast({ title: "Member updated" });
        }}
      />

      <FormModal
        open={Boolean(renewing)}
        onOpenChange={(open) => !open && setRenewing(null)}
        title={`Renew membership — ${renewing?.name || ""}`}
        description="Creates a new membership period and records the payment."
        fields={[
          { name: "planId", label: "Plan", type: "select", options: planOptions },
          { name: "amount", label: "Amount collected", type: "number" },
          { name: "method", label: "Payment method", type: "select", options: methodOptions },
          { name: "notes", label: "Notes", placeholder: "Receipt reference…" },
        ]}
        submitLabel="Renew membership"
        onSubmit={(values) => {
          const ms = renewMembership({
            memberId: renewing.id,
            planId: values.planId,
            amount: values.amount,
            method: values.method,
            notes: values.notes,
            by: session.name,
          });
          toast({ title: "Membership renewed", description: `Valid until ${fmtDate(ms.expiryDate)}` });
        }}
      />

      <MemberDetail memberId={viewing} open={Boolean(viewing)} onClose={() => setViewing(null)} />
    </OwnerShell>
  );
}