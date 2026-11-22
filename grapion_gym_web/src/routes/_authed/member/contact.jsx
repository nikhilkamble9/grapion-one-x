import { createFileRoute } from "@tanstack/react-router";
import { Mail, MapPin, MessageCircle, Phone } from "lucide-react";
import { MemberShell } from "@/components/grapion/shells";
import { useRoleSession, useStore } from "@/lib/grapion/useGrapion";
import { PageHead, Panel, KeyValue, Photo } from "@/components/grapion/ui";
import { Button } from "@/components/ui/button";
import { waLink } from "@/lib/grapion/util";
import { memberView } from "@/lib/grapion/repo";

export const Route = createFileRoute("/_authed/member/contact")({
  component: ContactGym,
  head: () => ({ meta: [{ title: "Contact gym · GRAPION GYM" }] }),
});

function ContactGym() {
  const session = useRoleSession();
  const db = useStore();
  const view = memberView(db, session?.memberId);
  if (!view) return null;
  const { gym, member } = view;

  const message = `Hi ${gym?.name || "team"}, this is ${member.name} (${member.code}).`;

  return (
    <MemberShell>
      <PageHead eyebrow="Contact" title="Contact gym" description="Reach the front desk or your coach directly." />

      <div className="grid gap-4 lg:grid-cols-2">
        <Panel title={gym?.name || "Your gym"}>
          <div className="flex items-center gap-4">
            <Photo src={gym?.logo} name={gym?.name} size={54} rounded="rounded-xl" />
            <div>
              <p className="text-[12.5px] font-medium">{gym?.name}</p>
              <p className="text-[11px] text-muted-foreground">{gym?.description || "Gym workspace"}</p>
            </div>
          </div>
          <div className="mt-3">
            <KeyValue label="Address" value={[gym?.address, gym?.city].filter(Boolean).join(", ")} />
            <KeyValue label="Opening hours" value={gym?.openingHours} />
            <KeyValue label="UPI ID" value={gym?.upiId} />
          </div>
        </Panel>

        <Panel title="Direct contact">
          <div className="space-y-2">
            {gym?.phone && (
              <a
                href={`tel:${gym.phone}`}
                className="flex items-center gap-3 rounded-xl border border-border px-3 py-3 text-[12.5px] hover:bg-accent"
              >
                <Phone className="h-4 w-4 text-primary" /> {gym.phone}
              </a>
            )}
            {gym?.email && (
              <a
                href={`mailto:${gym.email}`}
                className="flex items-center gap-3 rounded-xl border border-border px-3 py-3 text-[12.5px] hover:bg-accent"
              >
                <Mail className="h-4 w-4 text-primary" /> {gym.email}
              </a>
            )}
            {gym?.phone && (
              <a
                href={waLink(gym.phone, message)}
                target="_blank"
                rel="noreferrer"
                className="flex items-center gap-3 rounded-xl border border-emerald-500/30 bg-emerald-500/10 px-3 py-3 text-[12.5px] text-emerald-300 hover:bg-emerald-500/15"
              >
                <MessageCircle className="h-4 w-4" /> Message the gym on WhatsApp
              </a>
            )}
          </div>
          <p className="mt-4 flex items-start gap-2 text-[10.5px] leading-relaxed text-muted-foreground">
            <MapPin className="mt-0.5 h-3.5 w-3.5 shrink-0" />
            WhatsApp opens with a prefilled message — you still press send yourself. Nothing is sent
            automatically.
          </p>
          <Button asChild variant="outline" className="mt-4 w-full">
            <a href={`tel:${gym?.phone || ""}`}>Call the gym</a>
          </Button>
        </Panel>
      </div>
    </MemberShell>
  );
}