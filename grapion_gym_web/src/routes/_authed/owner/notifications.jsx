import { createFileRoute } from "@tanstack/react-router";
import { CheckCheck } from "lucide-react";
import { OwnerShell } from "@/components/grapion/shells";
import { useRoleSession, useStore } from "@/lib/grapion/useGrapion";
import { PageHead, Panel, Pill, Empty } from "@/components/grapion/ui";
import { Button } from "@/components/ui/button";
import { fmtDateTime } from "@/lib/grapion/util";
import { memberById, markAllRead, markNotificationRead } from "@/lib/grapion/repo";

export const Route = createFileRoute("/_authed/owner/notifications")({
  component: OwnerNotifications,
  head: () => ({ meta: [{ title: "Notifications · GRAPION GYM" }] }),
});

const toneFor = (category) =>
  ({ payment: "green", membership: "amber", attendance: "blue", subscription: "red" }[category] || "gray");

function OwnerNotifications() {
  const session = useRoleSession();
  const db = useStore();
  const gymId = session?.gymId;
  const rows = db.notifications.filter((n) => n.gymId === gymId && n.audience === "owner");
  const unread = rows.filter((n) => !n.read).length;

  return (
    <OwnerShell>
      <PageHead
        eyebrow="Inbox"
        title="Notifications"
        description="Expiry reminders, check-ins and payment alerts generated from your records."
        actions={
          <Button size="sm" variant="outline" disabled={!unread} onClick={() => markAllRead({ gymId, audience: "owner" })}>
            <CheckCheck className="mr-1.5 h-3.5 w-3.5" /> Mark all read
          </Button>
        }
      />

      <Panel title={unread ? `${unread} unread` : "All caught up"}>
        {rows.length ? (
          <ul className="space-y-2">
            {rows.slice(0, 80).map((row) => (
              <li
                key={row.id}
                className={`flex items-start justify-between gap-3 rounded-xl border px-3 py-3 ${
                  row.read ? "border-border/60" : "border-primary/25 bg-primary/5"
                }`}
              >
                <div className="min-w-0">
                  <div className="flex flex-wrap items-center gap-2">
                    <p className="text-[12.5px] font-semibold">{row.title}</p>
                    <Pill tone={toneFor(row.category)}>{row.category}</Pill>
                  </div>
                  <p className="mt-1 text-[12px] leading-relaxed text-muted-foreground">{row.message}</p>
                  {row.email?.to ? (
                    <p
                      className={`mt-1 text-[10.5px] ${
                        row.emailSent ? "text-emerald-400" : row.emailError ? "text-red-300" : "text-muted-foreground/70"
                      }`}
                    >
                      {row.emailSent
                        ? `Emailed to ${row.email.to}`
                        : row.emailError || `Email queued for ${row.email.to}`}
                    </p>
                  ) : null}
                  <p className="mt-1 text-[10.5px] text-muted-foreground/70">
                    {fmtDateTime(row.date)}
                    {row.memberId ? ` · ${memberById(db, row.memberId)?.name || ""}` : ""}
                  </p>
                </div>
                {!row.read && (
                  <Button size="sm" variant="ghost" onClick={() => markNotificationRead(row.id)}>
                    Mark read
                  </Button>
                )}
              </li>
            ))}
          </ul>
        ) : (
          <Empty
            title="No notifications yet"
            hint="Expiry reminders and activity alerts will appear here as your gym runs."
          />
        )}
      </Panel>
    </OwnerShell>
  );
}