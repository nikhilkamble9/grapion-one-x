import { useState } from "react";
import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { Shield } from "lucide-react";
import { AccessLayout } from "@/components/grapion/AccessLayout";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { loginAdmin } from "@/lib/grapion/repo";

export const Route = createFileRoute("/_authed/access/admin")({
  component: AdminLoginPage,
  head: () => ({ meta: [{ title: "Admin sign in · GRAPION GYM" }] }),
});

function AdminLoginPage() {
  const navigate = useNavigate();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  const submit = (event) => {
    event.preventDefault();
    setBusy(true);
    setError("");
    const result = loginAdmin(email.trim(), password);
    setBusy(false);
    if (!result.ok) {
      setError(result.error);
      return;
    }
    navigate({ to: "/admin", replace: true });
  };

  return (
    <AccessLayout
      icon={Shield}
      badge="Admin access"
      title="Grapion Admin Console"
      description="Platform-wide control of every gym, owner and subscription across Grapion Gym."
      footer={
        <p className="text-[11px] leading-relaxed text-muted-foreground">
          Admin access is restricted to Grapion Digital. Credentials are validated locally for this
          demo build and must be replaced with server-side authentication before production.
        </p>
      }
    >
      <form onSubmit={submit} className="space-y-4">
        <label className="block">
          <span className="mb-1.5 block text-[11.5px] font-medium text-muted-foreground">
            Admin email
          </span>
          <Input
            type="email"
            autoComplete="username"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="you@grapiondigital.com"
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
          {busy ? "Signing in…" : "CONTINUE AS ADMIN"}
        </Button>
      </form>
    </AccessLayout>
  );
}