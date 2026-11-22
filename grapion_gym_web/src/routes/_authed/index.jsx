import { createFileRoute, Link } from "@tanstack/react-router";
import { ArrowRight, Dumbbell, Shield, User } from "lucide-react";

export const Route = createFileRoute("/_authed/")({
  component: RoleSelectionPage,
  head: () => ({
    meta: [
      { title: "Welcome to GRAPION GYM" },
      {
        name: "description",
        content: "Grapion Gym — premium gym management software by Grapion Digital.",
      },
    ],
  }),
});

const options = [
  {
    to: "/access/admin",
    icon: Shield,
    label: "Admin",
    kicker: "Platform control",
    blurb: "Gyms, owners, subscriptions, revenue and platform-wide analytics.",
    cta: "CONTINUE AS ADMIN",
  },
  {
    to: "/access/owner",
    icon: Dumbbell,
    label: "Gym Owner",
    kicker: "Gym operations",
    blurb: "Members, memberships, attendance, batches and daily collections.",
    cta: "CONTINUE AS GYM OWNER",
  },
  {
    to: "/access/member",
    icon: User,
    label: "Gym Member",
    kicker: "Personal workspace",
    blurb: "Your membership, visits, payments, batch and renewals.",
    cta: "CONTINUE AS MEMBER",
  },
];

function RoleSelectionPage() {
  return (
    <main className="relative min-h-screen overflow-hidden bg-background">
      <div className="gp-glow" />
      <div className="gp-grid-lines" />

      <div className="relative mx-auto flex min-h-screen w-full max-w-6xl flex-col px-5 py-7 sm:px-8 sm:py-10">
        <header className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="grid h-11 w-11 place-items-center rounded-xl bg-primary text-[15px] font-extrabold tracking-tight text-primary-foreground">
              GP
            </div>
            <div>
              <p className="font-heading text-[15px] font-semibold leading-none tracking-tight">
                GRAPION GYM
              </p>
              <p className="mt-1 text-[11px] leading-none text-muted-foreground">
                by Grapion Digital
              </p>
            </div>
          </div>
          <span className="hidden rounded-full border border-border px-3 py-1.5 text-[10px] font-semibold uppercase tracking-[0.2em] text-muted-foreground sm:block">
            Manage Smarter · Train Better
          </span>
        </header>

        <section className="flex flex-1 flex-col justify-center py-12 sm:py-16">
          <div className="max-w-2xl gp-rise">
            <p className="gp-eyebrow">Gym Management Suite</p>
            <h1 className="mt-5 font-heading text-[34px] font-semibold leading-[1.06] tracking-[-0.03em] sm:text-6xl">
              Welcome to
              <br />
              <span className="text-primary">GRAPION GYM</span>
            </h1>
            <p className="mt-5 max-w-md text-[15px] leading-relaxed text-muted-foreground">
              Please select your account type to continue.
            </p>
          </div>

          <div className="mt-10 grid gap-4 sm:mt-12 sm:grid-cols-3">
            {options.map((option, index) => (
              <Link
                key={option.to}
                to={option.to}
                className="gp-rise group relative flex flex-col overflow-hidden rounded-2xl border border-border bg-card/80 p-6 transition-all duration-300 hover:-translate-y-1 hover:border-primary/50 hover:bg-card focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                style={{ animationDelay: `${120 + index * 90}ms` }}
              >
                <span className="pointer-events-none absolute -right-10 -top-10 h-28 w-28 rounded-full bg-primary/10 opacity-0 blur-2xl transition-opacity duration-300 group-hover:opacity-100" />
                <div className="flex items-start justify-between">
                  <div className="grid h-12 w-12 place-items-center rounded-xl border border-border bg-secondary text-primary transition-colors duration-300 group-hover:border-primary/40">
                    <option.icon className="h-[22px] w-[22px]" strokeWidth={1.6} />
                  </div>
                  <span className="gp-eyebrow pt-1">{option.kicker}</span>
                </div>

                <h2 className="mt-7 font-heading text-xl font-semibold tracking-tight">
                  {option.label}
                </h2>
                <p className="mt-2 text-[13px] leading-relaxed text-muted-foreground">
                  {option.blurb}
                </p>

                <span className="mt-7 inline-flex items-center gap-2 border-t border-border pt-4 text-[10.5px] font-bold uppercase tracking-[0.16em] text-foreground transition-colors group-hover:text-primary">
                  {option.cta}
                  <ArrowRight className="h-3.5 w-3.5 transition-transform duration-300 group-hover:translate-x-1" />
                </span>
              </Link>
            ))}
          </div>
        </section>

        <footer className="flex flex-col gap-2 border-t border-border pt-5 text-[11px] text-muted-foreground sm:flex-row sm:items-center sm:justify-between">
          <p>Powered by Grapion Digital</p>
          <p>Local demo environment · data stays in this browser</p>
        </footer>
      </div>
    </main>
  );
}