<!-- Modified By Nikhil 22Nov26 11:59 For real web app description. Old: Base44 TanStack starter README (copy: AI Agents Temp\grapion-one-x\GymModuleSetup\22Nov26\backup\repo_cleanup_1159\web_README.md) -->
# Grapion Gym — Web prototype

A browser-only prototype of Grapion Gym, used to try out screens and flows quickly.
**It is not connected to the Grapion One X API or database** — all data lives in the browser's
`localStorage` and starts from a demo gym (`src/lib/grapion/seed.js`). Clearing site data resets it.
The real product is the Flutter app in [`../grapion_one_x_app`](../grapion_one_x_app/README.md) with the API in
[`../grapion_one_x_api`](../grapion_one_x_api/README.md).

## Screens

| Route | For |
|---|---|
| `/login`, `/register`, `/forgot-password`, `/reset-password`, `/mfa` | Sign-in flows |
| `/_authed/owner/*` | Gym owner: members, plans, batches, payments, dashboard |
| `/_authed/member/*` | Member: own membership and visits |
| `/_authed/admin/*` | Grapion admin: gyms and their subscriptions |
| `/_authed/access` | Access / role landing |

Data layer: `src/lib/grapion/` — `store.js` (localStorage), `repo.js` (business rules: memberships, payments, expiry),
`seed.js` (demo data), `session.js`, `useGrapion.js`.

## Tech

React 19 (plain JavaScript), TanStack Start (file-based routes, server rendering), Tailwind + shadcn/ui components,
hosted on Base44. Platform details and coding rules for this project are in `AGENTS.md`.

## Run

Requires Node.js 20+ and the Base44 CLI.

```bash
npm ci
base44 login   # once per machine
base44 link    # once per clone
base44 dev     # local app
```

```bash
npm run build  # production build
npm run lint
base44 deploy  # publish
```
