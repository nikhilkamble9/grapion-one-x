import { createFileRoute } from "@tanstack/react-router";
import { CheckCheck } from "lucide-react";
import { AdminShell } from "@/components/grapion/shells";
import { useStore } from "@/lib/grapion/useGrapion";
import { PageHead, Panel, Pill, Empty } from "@/components/grapion/ui";
import { Button } from "@/components/ui/button";
import { fmtDateTime } from "@/lib/grapion/util";
import { findGym, markAllRead, markNotificationRead } from "@/lib/grapion/repo";

export const Route = createFileRoute("/_authed/admin/notifications")({
  component: AdminNotifications,
  head: () => ({ meta: [{ title: "Notifications · GRAPION GYM" }] }),
});

const toneFor = (category) =>
  ({ subscription: "amber", payment: "green", membership: "blue", attendance: "gray" }[category] || "gray");

function AdminNotifications() {
  const db = useStore();
  const rows = db.notifications.filter((n) => n.audience === "owner");
  const unread = rows.filter((n) => !n.read).length;

  return (
    <AdminShell>
      <PageHead
        eyebrow="Inbox"
        title="Platform notifications"
        description="Subscription and account alerts raised by gym activity."
        actions={
          <Button
            size="sm"
            variant="outline"
            disabled={!unread}
            onClick={() => markAllRead({ audience: "owner" })}
          >
            <CheckCheck className="mr-1.5 h-3.5 w-3.5" /> Mark all read
          </Button>
        }
      />

      <Panel title={unread ? `${unread} unread` : "All caught up"}>
        {rows.length ? (
          <ul className="space-y-3">
            {rows.slice(0, 60).map((row) => (
              <li
                key={row.id}
                className={`flex items-start justify-between gap-3 rounded-xl border px-3 py-3 ${
                  row.read ? "border-border/60 bg-transparent" : "border-primary/25 bg-primary/5"
                }`}
              >
                <div className="min-w-0">
                  <div className="flex flex-wrap items-center gap-2">
                    <p className="text-[12.5px] font-semibold">{row.title}</p>
                    <Pill tone={toneFor(row.category)}>{row.category}</Pill>
                    {row.gymId && (
                      <span className="text-[10.5px] text-muted-foreground">
                        {findGym(db, row.gymId)?.name || ""}
                      </span>
                    )}
                  </div>
                  <p className="mt-1 text-[12px] leading-relaxed text-muted-foreground">{row.message}</p>
                  <p className="mt-1 text-[10.5px] text-muted-foreground/70">{fmtDateTime(row.date)}</p>
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
          <Empty title="No notifications yet" hint="Gym activity and subscription alerts appear here." />
        )}
      </Panel>
    </AdminShell>
  );
}