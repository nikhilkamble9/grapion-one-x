import { useState } from "react";
import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { UserRound } from "lucide-react";
import { AccessLayout } from "@/components/grapion/AccessLayout";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { loginMember } from "@/lib/grapion/repo";
import { useStore } from "@/lib/grapion/useGrapion";
import { DEMO_GYM_ID } from "@/lib/grapion/seed";

export const Route = createFileRoute("/_authed/access/member")({
  component: MemberLoginPage,
  head: () => ({ meta: [{ title: "Member sign in · GRAPION GYM" }] }),
});

function MemberLoginPage() {
  const navigate = useNavigate();
  const db = useStore();
  const [identifier, setIdentifier] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  const demoMember = db.gymMembers.find((m) => m.gymId === DEMO_GYM_ID && m.isDemo);

  const submit = (event) => {
    event.preventDefault();
    setBusy(true);
    setError("");
    const result = loginMember(identifier.trim(), password);
    setBusy(false);
    if (!result.ok) {
      setError(result.error);
      return;
    }
    navigate({ to: "/member", replace: true });
  };

  return (
    <AccessLayout
      icon={UserRound}
      badge="Member access"
      title="Your gym, on your phone"
      description="Check your membership, check in and out, view payments and renew in a few taps."
      footer={
        demoMember ? (
          <div className="flex flex-wrap items-center justify-between gap-2 text-[11px]">
            <p className="text-muted-foreground">
              Demo member: <span className="text-foreground">{demoMember.code}</span> ·{" "}
              <span className="text-foreground">{demoMember.password}</span>
            </p>
            <Button
              type="button"
              size="sm"
              variant="outline"
              onClick={() => {
                setIdentifier(demoMember.code);
                setPassword(demoMember.password);
              }}
            >
              Use demo
            </Button>
          </div>
        ) : (
          <p className="text-[11px] leading-relaxed text-muted-foreground">
            Member logins are created by your gym. Ask the front desk if you do not have your member
            ID yet.
          </p>
        )
      }
    >
      <form onSubmit={submit} className="space-y-4">
        <label className="block">
          <span className="mb-1.5 block text-[11.5px] font-medium text-muted-foreground">
            Email or Member ID
          </span>
          <Input
            autoComplete="username"
            value={identifier}
            onChange={(e) => setIdentifier(e.target.value)}
            placeholder="NIS-0001 or you@email.com"
            required
          />
        </label>
        <label className="block">
          <span className="mb-1.5 block text-[11.5px] font-medium text-muted-foreground">
            Password
          </span>
          <Input
            type="password"
            autoComplete="current-password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            placeholder="••••••••"
            required
          />
        </label>

        {error && (
          <p className="rounded-lg border border-red-500/30 bg-red-500/10 px-3 py-2 text-[12px] text-red-300">
            {error}
          </p>
        )}

        <Button type="submit" className="w-full" disabled={busy}>
          {busy ? "Signing in…" : "CONTINUE AS MEMBER"}
        </Button>
      </form>
    </AccessLayout>
  );
}