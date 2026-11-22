import { useState } from "react";
import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { Dumbbell } from "lucide-react";
import { AccessLayout } from "@/components/grapion/AccessLayout";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { loginOwner } from "@/lib/grapion/repo";
import { useStore } from "@/lib/grapion/useGrapion";
import { DEMO_GYM_ID } from "@/lib/grapion/seed";

export const Route = createFileRoute("/_authed/access/owner")({
  component: OwnerLoginPage,
  head: () => ({ meta: [{ title: "Gym owner sign in · GRAPION GYM" }] }),
});

function OwnerLoginPage() {
  const navigate = useNavigate();
  const db = useStore();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  const demoOwner = db.gymOwners.find((o) => o.gymId === DEMO_GYM_ID && o.isDemo);

  const submit = (event) => {
    event.preventDefault();
    setBusy(true);
    setError("");
    const result = loginOwner(email.trim(), password);
    setBusy(false);
    if (!result.ok) {
      setError(result.error);
      return;
    }
    navigate({ to: "/owner", replace: true });
  };

  return (
    <AccessLayout
      icon={Dumbbell}
      badge="Gym owner access"
      title="Run your gym from one place"
      description="Members, memberships, attendance, batches and collections — one workspace per gym."
      footer={
        demoOwner ? (
          <div className="flex flex-wrap items-center justify-between gap-2 text-[11px]">
            <p className="text-muted-foreground">
              Demo gym owner: <span className="text-foreground">{demoOwner.email}</span> ·{" "}
              <span className="text-foreground">{demoOwner.password}</span>
            </p>
            <Button
              type="button"
              size="sm"
              variant="outline"
              onClick={() => {
                setEmail(demoOwner.email);
                setPassword(demoOwner.password);
              }}
            >
              Use demo
            </Button>
          </div>
        ) : (
          <p className="text-[11px] leading-relaxed text-muted-foreground">
            Owner accounts are created by Grapion Digital from the admin console. There is no public
            owner sign-up.
          </p>
        )
      }
    >
      <form onSubmit={submit} className="space-y-4">
        <label className="block">
          <span className="mb-1.5 block text-[11.5px] font-medium text-muted-foreground">Email</span>
          <Input
            type="email"
            autoComplete="username"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="owner@yourgym.com"
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
          {busy ? "Signing in…" : "CONTINUE AS GYM OWNER"}
        </Button>
      </form>
    </AccessLayout>
  );
}