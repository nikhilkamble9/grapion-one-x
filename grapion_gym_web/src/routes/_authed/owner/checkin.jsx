import { useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { LogIn, LogOut, Search } from "lucide-react";
import { OwnerShell } from "@/components/grapion/shells";
import { useRoleSession, useStore } from "@/lib/grapion/useGrapion";
import { PageHead, Panel, StatGrid, Pill, Photo, Empty } from "@/components/grapion/ui";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { useToast } from "@/components/ui/use-toast";
import { fmtDate, fmtTime, money, todayISO } from "@/lib/grapion/util";
import { checkIn, checkOut, memberById, memberView, planById } from "@/lib/grapion/repo";

export const Route = createFileRoute("/_authed/owner/checkin")({
  component: CheckInDesk,
  head: () => ({ meta: [{ title: "Check-in desk · GRAPION GYM" }] }),
});

function CheckInDesk() {
  const session = useRoleSession();
  const db = useStore();
  const { toast } = useToast();
  const gymId = session?.gymId;
  const today = todayISO();
  const [search, setSearch] = useState("");

  const todayRecords = db.attendance.filter((a) => a.gymId === gymId && a.date === today);
  const openRecords = db.attendance.filter((a) => a.gymId === gymId && !a.checkOut);
  const members = db.gymMembers
    .filter(
      (m) =>
        m.gymId === gymId &&
        m.status === "active" &&
        `${m.name} ${m.code} ${m.phone}`.toLowerCase().includes(search.toLowerCase()),
    )
    .map((m) => memberView(db, m.id));

  const act = (fn, memberId, label) => {
    try {
      fn(memberId, session.name);
      toast({ title: label });
    } catch (err) {
      toast({ title: "Action not possible", description: err.message });
    }
  };

  return (
    <OwnerShell>
      <PageHead
        eyebrow="Attendance"
        title="Check-in / Check-out"
        description="One tap in, one tap out — timestamps are captured from this device's clock."
      />

      <StatGrid
        cols={4}
        items={[
          { label: "Members inside", value: openRecords.length, tone: "green" },
          { label: "Check-ins today", value: todayRecords.length },
          { label: "Check-outs today", value: todayRecords.filter((r) => r.checkOut).length },
          {
            label: "Members on desk",
            value: db.gymMembers.filter((m) => m.gymId === gymId && m.status === "active").length,
          },
        ]}
      />

      <Panel className="mt-4" title="Inside the gym right now">
        {openRecords.length ? (
          <ul className="space-y-3">
            {openRecords.map((record) => {
              const member = memberById(db, record.memberId);
              return (
                <li key={record.id} className="flex items-center gap-3">
                  <Photo src={member?.photo} name={member?.name} size={32} />
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-[12.5px] font-medium">{member?.name}</p>
                    <p className="text-[10.5px] text-muted-foreground">
                      In at {fmtTime(record.checkIn)} · {fmtDate(record.date)}
                    </p>
                  </div>
                  <Button
                    size="sm"
                    variant="outline"
                    onClick={() => act(checkOut, record.memberId, "Member checked out")}
                  >
                    <LogOut className="mr-1.5 h-3.5 w-3.5" /> Check out
                  </Button>
                </li>
              );
            })}
          </ul>
        ) : (
          <Empty title="Nobody is checked in" hint="Members appear here as soon as they check in." />
        )}
      </Panel>

      <Panel
        className="mt-4"
        title="Attendance desk"
        action={
          <div className="relative">
            <Search className="absolute left-2.5 top-2.5 h-3.5 w-3.5 text-muted-foreground" />
            <Input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search member"
              className="h-9 w-[190px] pl-8 text-[12px]"
            />
          </div>
        }
      >
        {members.length ? (
          <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
            {members.map(({ member, plan, status }) => {
              const open = openRecords.find((r) => r.memberId === member.id);
              const done = todayRecords.find((r) => r.memberId === member.id && r.checkOut);
              return (
                <div key={member.id} className="rounded-xl border border-border p-3">
                  <div className="flex items-center gap-2.5">
                    <Photo src={member.photo} name={member.name} size={40} />
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-[12.5px] font-semibold">{member.name}</p>
                      <p className="text-[10.5px] text-muted-foreground">{member.code}</p>
                    </div>
                    <Pill tone={status.tone}>{status.label}</Pill>
                  </div>
                  <p className="mt-2 truncate text-[11px] text-muted-foreground">
                    {plan?.name || "No active plan"}
                    {status.key === "expired" ? " · renew needed" : ""}
                  </p>
                  <div className="mt-3 grid grid-cols-2 gap-2">
                    <Button
                      size="sm"
                      disabled={Boolean(open)}
                      onClick={() => act(checkIn, member.id, `${member.name} checked in`)}
                    >
                      <LogIn className="mr-1.5 h-3.5 w-3.5" /> CHECK IN
                    </Button>
                    <Button
                      size="sm"
                      variant="outline"
                      disabled={!open}
                      onClick={() => act(checkOut, member.id, `${member.name} checked out`)}
                    >
                      <LogOut className="mr-1.5 h-3.5 w-3.5" /> CHECK OUT
                    </Button>
                  </div>
                  {open && (
                    <p className="mt-2 text-[10.5px] text-emerald-400">Inside since {fmtTime(open.checkIn)}</p>
                  )}
                  {!open && done && (
                    <p className="mt-2 text-[10.5px] text-muted-foreground">
                      Visited today · {fmtTime(done.checkIn)} → {fmtTime(done.checkOut)}
                    </p>
                  )}
                </div>
              );
            })}
          </div>
        ) : (
          <Empty title="No members found" hint="Try another name, member ID or phone number." />
        )}
      </Panel>
    </OwnerShell>
  );
}