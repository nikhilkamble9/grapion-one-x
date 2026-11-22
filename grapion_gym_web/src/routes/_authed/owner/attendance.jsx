import { useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { OwnerShell } from "@/components/grapion/shells";
import { useRoleSession, useStore } from "@/lib/grapion/useGrapion";
import { PageHead, Panel, StatGrid, Empty } from "@/components/grapion/ui";
import { DataTable } from "@/components/grapion/DataTable";
import { Input } from "@/components/ui/input";
import { fmtDate, fmtTime, isoDate, todayISO } from "@/lib/grapion/util";
import { batchById, memberById } from "@/lib/grapion/repo";

export const Route = createFileRoute("/_authed/owner/attendance")({
  component: AttendancePage,
  head: () => ({ meta: [{ title: "Attendance · GRAPION GYM" }] }),
});

const ranges = [
  { value: "today", label: "Today" },
  { value: "yesterday", label: "Yesterday" },
  { value: "week", label: "This week" },
  { value: "month", label: "This month" },
  { value: "custom", label: "Custom date" },
  { value: "all", label: "All time" },
];

const duration = (record) => {
  if (!record.checkOut) return "In gym";
  const mins = Math.max(
    0,
    Math.round((new Date(record.checkOut).getTime() - new Date(record.checkIn).getTime()) / 60000),
  );
  return `${Math.floor(mins / 60)}h ${mins % 60}m`;
};

function AttendancePage() {
  const session = useRoleSession();
  const db = useStore();
  const gymId = session?.gymId;
  const today = todayISO();
  const [range, setRange] = useState("today");
  const [memberId, setMemberId] = useState("all");
  const [batchId, setBatchId] = useState("all");
  const [customDate, setCustomDate] = useState(today);

  const yesterday = (() => {
    const d = new Date();
    d.setDate(d.getDate() - 1);
    return isoDate(d);
  })();

  const matchesRange = (date) => {
    if (range === "today") return date === today;
    if (range === "yesterday") return date === yesterday;
    if (range === "week") {
      const start = new Date();
      start.setDate(start.getDate() - 6);
      return date >= isoDate(start) && date <= today;
    }
    if (range === "month") return date.slice(0, 7) === today.slice(0, 7);
    if (range === "custom") return date === customDate;
    return true;
  };

  const members = db.gymMembers.filter((m) => m.gymId === gymId);
  const batches = db.batches.filter((b) => b.gymId === gymId);

  const rows = db.attendance
    .filter((a) => a.gymId === gymId && matchesRange(a.date))
    .filter((a) => memberId === "all" || a.memberId === memberId)
    .filter((a) => {
      if (batchId === "all") return true;
      return memberById(db, a.memberId)?.batchId === batchId;
    })
    .sort((a, b) => String(b.checkIn).localeCompare(String(a.checkIn)));

  return (
    <OwnerShell>
      <PageHead
        eyebrow="Attendance"
        title="Attendance records"
        description="Filter visits by date, member or batch. Check-ins and check-outs are timestamped."
      />

      <StatGrid
        cols={4}
        items={[
          { label: "Records shown", value: rows.length },
          { label: "Still inside", value: rows.filter((r) => !r.checkOut).length, tone: "green" },
          { label: "Members today", value: db.attendance.filter((a) => a.gymId === gymId && a.date === today).length },
          {
            label: "Visits this month",
            value: db.attendance.filter((a) => a.gymId === gymId && String(a.date).slice(0, 7) === today.slice(0, 7)).length,
          },
        ]}
      />

      <Panel
        className="mt-4"
        title="Filters"
        action={
          <div className="flex flex-wrap items-center gap-2">
            <select
              value={range}
              onChange={(e) => setRange(e.target.value)}
              className="h-9 rounded-md border border-input bg-transparent px-2 text-[12px]"
            >
              {ranges.map((r) => (
                <option key={r.value} value={r.value}>{r.label}</option>
              ))}
            </select>
            {range === "custom" && (
              <Input
                type="date"
                value={customDate}
                onChange={(e) => setCustomDate(e.target.value)}
                className="h-9 w-[145px] text-[12px]"
              />
            )}
            <select
              value={memberId}
              onChange={(e) => setMemberId(e.target.value)}
              className="h-9 max-w-[170px] rounded-md border border-input bg-transparent px-2 text-[12px]"
            >
              <option value="all">All members</option>
              {members.map((m) => (
                <option key={m.id} value={m.id}>{m.name}</option>
              ))}
            </select>
            <select
              value={batchId}
              onChange={(e) => setBatchId(e.target.value)}
              className="h-9 max-w-[170px] rounded-md border border-input bg-transparent px-2 text-[12px]"
            >
              <option value="all">All batches</option>
              {batches.map((b) => (
                <option key={b.id} value={b.id}>{b.name}</option>
              ))}
            </select>
          </div>
        }
        bodyClass="p-5 pt-4"
      >
        <DataTable
          empty="No visits in this range"
          rows={rows}
          columns={[
            {
              key: "member",
              label: "Member",
              render: (row) => {
                const member = memberById(db, row.memberId);
                return (
                  <div>
                    <p className="font-medium">{member?.name || "—"}</p>
                    <p className="text-[10.5px] text-muted-foreground">{member?.code}</p>
                  </div>
                );
              },
            },
            { key: "date", label: "Date", render: (row) => fmtDate(row.date) },
            {
              key: "batch",
              label: "Batch",
              render: (row) => batchById(db, memberById(db, row.memberId)?.batchId)?.name || "—",
            },
            { key: "checkIn", label: "Check-in", render: (row) => fmtTime(row.checkIn) },
            {
              key: "checkOut",
              label: "Check-out",
              render: (row) =>
                row.checkOut ? fmtTime(row.checkOut) : <span className="text-emerald-400">still inside</span>,
            },
            { key: "duration", label: "Duration", render: (row) => duration(row) },
          ]}
        />
      </Panel>

      {!rows.length && (
        <div className="mt-4">
          <Empty title="Nothing recorded for these filters" hint="Try a wider date range or a different member." />
        </div>
      )}
    </OwnerShell>
  );
}