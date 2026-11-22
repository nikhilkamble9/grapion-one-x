import { createFileRoute } from "@tanstack/react-router";
import { Check, Minus } from "lucide-react";
import { MemberShell } from "@/components/grapion/shells";
import { useRoleSession, useStore } from "@/lib/grapion/useGrapion";
import { PageHead, Panel, Empty, Pill } from "@/components/grapion/ui";
import { memberView } from "@/lib/grapion/repo";

export const Route = createFileRoute("/_authed/member/services")({
  component: MyServices,
  head: () => ({ meta: [{ title: "My services · GRAPION GYM" }] }),
});

function MyServices() {
  const session = useRoleSession();
  const db = useStore();
  const view = memberView(db, session?.memberId);
  if (!view) return null;
  const all = db.services.filter((s) => s.gymId === view.member.gymId);
  const included = new Set(view.plan?.services || []);

  return (
    <MemberShell>
      <PageHead
        eyebrow="Services"
        title="My services"
        description="What your gym offers and which services your current plan includes."
      />

      <Panel title="Gym services">
        {all.length ? (
          <ul className="space-y-3">
            {all.map((service) => {
              const active = included.has(service.id);
              return (
                <li key={service.id} className="flex items-start justify-between gap-3 border-b border-border/60 pb-3 last:border-0 last:pb-0">
                  <div className="min-w-0">
                    <div className="flex items-center gap-2">
                      <p className="text-[12.5px] font-medium">{service.name}</p>
                      {service.status !== "active" && <Pill tone="gray">unavailable</Pill>}
                    </div>
                    <p className="text-[11px] text-muted-foreground">{service.description || "Gym service"}</p>
                  </div>
                  <span
                    className={`mt-0.5 inline-flex items-center gap-1 text-[10.5px] font-semibold uppercase tracking-wider ${
                      active ? "text-emerald-400" : "text-muted-foreground"
                    }`}
                  >
                    {active ? <Check className="h-3.5 w-3.5" /> : <Minus className="h-3.5 w-3.5" />}
                    {active ? "in your plan" : "not included"}
                  </span>
                </li>
              );
            })}
          </ul>
        ) : (
          <Empty title="No services listed yet" />
        )}
      </Panel>
    </MemberShell>
  );
}