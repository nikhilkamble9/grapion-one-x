import { createFileRoute } from "@tanstack/react-router";
import { CheckCheck } from "lucide-react";
import { MemberShell } from "@/components/grapion/shells";
import { useRoleSession, useStore } from "@/lib/grapion/useGrapion";
import { PageHead, Panel, Pill, Empty } from "@/components/grapion/ui";
import { Button } from "@/components/ui/button";
import { fmtDateTime } from "@/lib/grapion/util";
import { markAllRead, markNotificationRead } from "@/lib/grapion/repo";

export const Route = createFileRoute("/_authed/member/notifications")({
  component: MyNotifications,
  head: () => ({ meta: [{ title: "Notifications · GRAPION GYM" }] }),
});

function MyNotifications() {
  const session = useRoleSession();
  const db = useStore();
  const memberId = session?.memberId;
  const rows = db.notifications.filter((n) => n.audience === "member" && n.memberId === memberId);
  const unread = rows.filter((n) => !n.read).length;

  return (
    <MemberShell>
      <PageHead
        eyebrow="Inbox"
        title="Notifications"
        description="Renewal reminders and payment updates from your gym."
        actions={
          <Button size="sm" variant="outline" disabled={!unread} onClick={() => markAllRead({ audience: "member", memberId })}>
            <CheckCheck className="mr-1.5 h-3.5 w-3.5" /> Mark all read
          </Button>
        }
      />

      <Panel title={unread ? `${unread} unread` : "All caught up"}>
        {rows.length ? (
          <ul className="space-y-2">
            {rows.map((row) => (
              <li
                key={row.id}
                className={`rounded-xl border px-3 py-3 ${row.read ? "border-border/60" : "border-primary/25 bg-primary/5"}`}
              >
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0">
                    <div className="flex flex-wrap items-center gap-2">
                      <p className="text-[12.5px] font-semibold">{row.title}</p>
                      <Pill tone={row.category === "payment" ? "green" : row.category === "membership" ? "amber" : "gray"}>
                        {row.category}
                      </Pill>
                    </div>
                    <p className="mt-1 text-[12px] leading-relaxed text-muted-foreground">{row.message}</p>
                    <p className="mt-1 text-[10.5px] text-muted-foreground/70">{fmtDateTime(row.date)}</p>
                  </div>
                  {!row.read && (
                    <Button size="sm" variant="ghost" onClick={() => markNotificationRead(row.id)}>
                      Read
                    </Button>
                  )}
                </div>
              </li>
            ))}
          </ul>
        ) : (
          <Empty title="No notifications yet" hint="You will see renewal reminders here." />
        )}
      </Panel>
    </MemberShell>
  );
}