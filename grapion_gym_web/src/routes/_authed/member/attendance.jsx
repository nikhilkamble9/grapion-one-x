import { useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { MemberShell } from "@/components/grapion/shells";
import { useRoleSession, useStore } from "@/lib/grapion/useGrapion";
import { PageHead, Panel, StatGrid, Empty } from "@/components/grapion/ui";
import { DataTable } from "@/components/grapion/DataTable";
import { fmtDate, fmtTime, isoDate, todayISO } from "@/lib/grapion/util";

export const Route = createFileRoute("/_authed/member/attendance")({
  component: MyAttendance,
  head: () => ({ meta: [{ title: "My attendance · GRAPION GYM" }] }),
});

const duration = (record) => {
  if (!record.checkOut) return "In gym";
  const mins = Math.max(
    0,
    Math.round((new Date(record.checkOut).getTime() - new Date(record.checkIn).getTime()) / 60000),
  );
  return `${Math.floor(mins / 60)}h ${mins % 60}m`;
};

function MyAttendance() {
  const session = useRoleSession();
  const db = useStore();
  const memberId = session?.memberId;
  const [range, setRange] = useState("month");
  const today = todayISO();

  const records = db.attendance
    .filter((a) => a.memberId === memberId)
    .filter((a) => {
      if (range === "all") return true;
      if (range === "month") return String(a.date).slice(0, 7) === today.slice(0, 7);
      const start = new Date();
      start.setDate(start.getDate() - 6);
      return a.date >= isoDate(start) && a.date <= today;
    })
    .sort((a, b) => String(b.checkIn).localeCompare(String(a.checkIn)));

  return (
    <MemberShell>
      <PageHead
        eyebrow="Attendance"
        title="My visits"
        description="Every check-in and check-out recorded at your gym."
        actions={
          <select
            value={range}
            onChange={(e) => setRange(e.target.value)}
            className="h-9 rounded-md border border-input bg-transparent px-2 text-[12px]"
          >
            <option value="week">Last 7 days</option>
            <option value="month">This month</option>
            <option value="all">All time</option>
          </select>
        }
      />

      <StatGrid
        cols={3}
        items={[
          { label: "Visits in view", value: records.length },
          { label: "Total visits", value: db.attendance.filter((a) => a.memberId === memberId).length },
          {
            label: "This month",
            value: db.attendance.filter((a) => a.memberId === memberId && String(a.date).slice(0, 7) === today.slice(0, 7)).length,
          },
        ]}
      />

      <Panel className="mt-4" title="Visit history">
        <DataTable
          empty="No visits recorded in this period"
          rows={records}
          columns={[
            { key: "date", label: "Date", render: (row) => fmtDate(row.date) },
            { key: "in", label: "Check-in", render: (row) => fmtTime(row.checkIn) },
            {
              key: "out",
              label: "Check-out",
              render: (row) => (row.checkOut ? fmtTime(row.checkOut) : "inside"),
            },
            { key: "duration", label: "Duration", render: (row) => duration(row) },
          ]}
        />
      </Panel>

      {!records.length && (
        <div className="mt-4">
          <Empty title="No visits yet" hint="Use CHECK IN on your dashboard when you arrive at the gym." />
        </div>
      )}
    </MemberShell>
  );
}