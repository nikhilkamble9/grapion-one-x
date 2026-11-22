import { createFileRoute } from "@tanstack/react-router";
import { MemberShell } from "@/components/grapion/shells";
import { useRoleSession, useStore } from "@/lib/grapion/useGrapion";
import { PageHead, Panel, KeyValue, Empty, Pill } from "@/components/grapion/ui";
import { batchById, memberView } from "@/lib/grapion/repo";

export const Route = createFileRoute("/_authed/member/batch")({
  component: MyBatch,
  head: () => ({ meta: [{ title: "My batch · GRAPION GYM" }] }),
});

function MyBatch() {
  const session = useRoleSession();
  const db = useStore();
  const view = memberView(db, session?.memberId);
  if (!view) return null;
  const batch = view.batch || (view.membership?.batchId ? batchById(db, view.membership.batchId) : null);
  const trainer = batch ? db.trainers.find((t) => t.id === batch.trainerId) : null;
  const service = batch ? db.services.find((s) => s.id === batch.serviceId) : null;
  const rosterSize = batch ? db.gymMembers.filter((m) => m.batchId === batch.id).length : 0;

  return (
    <MemberShell>
      <PageHead eyebrow="Schedule" title="My batch" description="Your training slot, coach and service." />

      {batch ? (
        <div className="grid gap-4 lg:grid-cols-2">
          <Panel title={batch.name} action={<Pill tone={batch.status === "active" ? "green" : "gray"}>{batch.status}</Pill>}>
            <KeyValue label="Time" value={`${batch.startTime} – ${batch.endTime}`} />
            <KeyValue label="Days" value={(batch.days || []).join(" · ") || "—"} />
            <KeyValue label="Service" value={service?.name || "Gym"} />
            <KeyValue label="Batch size" value={`${rosterSize} members`} />
          </Panel>

          <Panel title="Your trainer">
            {trainer ? (
              <>
                <KeyValue label="Name" value={trainer.name} />
                <KeyValue label="Specialisation" value={trainer.specialization} />
                <KeyValue label="Contact" value={trainer.phone} />
              </>
            ) : (
              <Empty title="No trainer assigned" hint="Your gym will assign a coach to this batch." />
            )}
          </Panel>
        </div>
      ) : (
        <Empty title="No batch assigned" hint="Ask the front desk to add you to a training slot." />
      )}
    </MemberShell>
  );
}