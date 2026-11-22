import { useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { Search } from "lucide-react";
import { AdminShell } from "@/components/grapion/shells";
import { useStore } from "@/lib/grapion/useGrapion";
import { PageHead, Panel, Pill } from "@/components/grapion/ui";
import { DataTable } from "@/components/grapion/DataTable";
import { Input } from "@/components/ui/input";
import { fmtDateTime } from "@/lib/grapion/util";
import { findGym } from "@/lib/grapion/repo";

export const Route = createFileRoute("/_authed/admin/activity")({
  component: ActivityLogs,
  head: () => ({ meta: [{ title: "Activity logs · GRAPION GYM" }] }),
});

function ActivityLogs() {
  const db = useStore();
  const [search, setSearch] = useState("");
  const rows = db.auditLogs.filter((row) =>
    `${row.action} ${row.detail} ${row.actor}`.toLowerCase().includes(search.toLowerCase()),
  );

  return (
    <AdminShell>
      <PageHead eyebrow="Audit" title="Activity logs" description="Every meaningful action taken across the platform." />

      <Panel
        title={`${rows.length} entries`}
        action={
          <div className="relative">
            <Search className="absolute left-2.5 top-2.5 h-3.5 w-3.5 text-muted-foreground" />
            <Input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search activity"
              className="h-9 w-[190px] pl-8 text-[12px]"
            />
          </div>
        }
      >
        <DataTable
          empty="No activity recorded yet"
          rows={rows}
          columns={[
            { key: "date", label: "When", render: (row) => fmtDateTime(row.date) },
            { key: "action", label: "Action", render: (row) => <span className="font-medium">{row.action}</span> },
            { key: "detail", label: "Detail", render: (row) => row.detail || "—" },
            {
              key: "gym",
              label: "Gym",
              render: (row) => (row.gymId ? findGym(db, row.gymId)?.name || "—" : "Platform"),
            },
            { key: "actor", label: "By" },
            {
              key: "role",
              label: "Role",
              render: (row) => <Pill tone={row.role === "admin" ? "primary" : "gray"}>{row.role}</Pill>,
            },
          ]}
        />
      </Panel>
    </AdminShell>
  );
}