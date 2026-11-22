import { useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { Save } from "lucide-react";
import { MemberShell } from "@/components/grapion/shells";
import { useRoleSession, useStore } from "@/lib/grapion/useGrapion";
import { PageHead, Panel, Field, KeyValue, Photo } from "@/components/grapion/ui";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { useToast } from "@/components/ui/use-toast";
import { fmtDate } from "@/lib/grapion/util";
import { memberView, updateMember } from "@/lib/grapion/repo";

export const Route = createFileRoute("/_authed/member/profile")({
  component: MyProfile,
  head: () => ({ meta: [{ title: "My profile · GRAPION GYM" }] }),
});

function MyProfile() {
  const session = useRoleSession();
  const db = useStore();
  const { toast } = useToast();
  const view = memberView(db, session?.memberId);
  const [form, setForm] = useState(() => ({
    phone: view?.member.phone || "",
    email: view?.member.email || "",
    address: view?.member.address || "",
    occupation: view?.member.occupation || "",
    emergencyContact: view?.member.emergencyContact || "",
  }));
  if (!view) return null;
  const { member, gym, plan, batch } = view;
  const set = (key, value) => setForm((prev) => ({ ...prev, [key]: value }));

  return (
    <MemberShell>
      <PageHead
        eyebrow="Profile"
        title="My profile"
        description="Your details as recorded by your gym. Contact info can be updated here."
        actions={
          <Button
            size="sm"
            onClick={() => {
              updateMember(member.id, form);
              toast({ title: "Profile updated" });
            }}
          >
            <Save className="mr-1.5 h-3.5 w-3.5" /> Save
          </Button>
        }
      />

      <div className="grid gap-4 lg:grid-cols-[0.85fr_1.15fr]">
        <Panel title="Member card">
          <div className="flex items-center gap-4">
            <Photo src={member.photo} name={member.name} size={64} rounded="rounded-2xl" />
            <div className="min-w-0">
              <p className="font-heading text-[15px] font-semibold">{member.name}</p>
              <p className="text-[11.5px] text-muted-foreground">{member.code}</p>
            </div>
          </div>
          <div className="mt-4">
            <KeyValue label="Gym" value={gym?.name} />
            <KeyValue label="Plan" value={plan?.name || "No active plan"} />
            <KeyValue label="Batch" value={batch?.name || "Not assigned"} />
            <KeyValue label="Joined" value={fmtDate(member.joinedAt)} />
            <KeyValue label="Account status" value={member.status} />
            <KeyValue label="Occupation" value={member.occupation} />
            <KeyValue label="Date of birth" value={member.dob ? fmtDate(member.dob) : "—"} />
            <KeyValue label="Gender" value={member.gender || "—"} />
          </div>
        </Panel>

        <Panel title="Contact details" subtitle="Kept in sync with the gym's records">
          <div className="grid gap-4 sm:grid-cols-2">
            <Field label="Mobile number">
              <Input value={form.phone} onChange={(e) => set("phone", e.target.value)} />
            </Field>
            <Field label="Email">
              <Input value={form.email} onChange={(e) => set("email", e.target.value)} />
            </Field>
            <Field label="Occupation">
              <Input value={form.occupation} onChange={(e) => set("occupation", e.target.value)} />
            </Field>
            <Field label="Emergency contact">
              <Input value={form.emergencyContact} onChange={(e) => set("emergencyContact", e.target.value)} />
            </Field>
            <Field label="Address" className="sm:col-span-2">
              <Input value={form.address} onChange={(e) => set("address", e.target.value)} />
            </Field>
          </div>
          <p className="mt-4 text-[10.5px] leading-relaxed text-muted-foreground">
            Name, member ID and photo are managed by your gym. Ask the front desk to change those.
          </p>
        </Panel>
      </div>
    </MemberShell>
  );
}