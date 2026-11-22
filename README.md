<!-- Added By Nikhil 22Nov26 11:59 For repository overview -->
# G.One.X — Grapion One X

One app, many business verticals. A business owner signs up once, subscribes to the modules they need
(Gym today; Wedding, Medical and Academy in development), and runs each business with its own staff,
branches and roles. Grapion staff (Super Admin / Admin) approve subscriptions and manage the platform.

## What is in this repository

| Folder | What it is | Tech |
|---|---|---|
| [`grapion_one_x_api/`](grapion_one_x_api/README.md) | The backend API — accounts, subscriptions, admin, gym module, notifications | Python 3.11, FastAPI, SQLAlchemy (async), PostgreSQL (Supabase) |
| [`grapion_one_x_app/`](grapion_one_x_app/README.md) | The mobile + web app used by owners, staff, members and admins | Flutter (Android, iOS, web) |
| [`grapion_gym_web/`](grapion_gym_web/README.md) | Stand-alone web prototype of Grapion Gym (browser storage only, not connected to the API) | React 19, TanStack Start, Base44 |
| `docs/reference-ui/` | UI reference screenshots | — |
| `ui_prototype_docspot.html` | Early clickable UI prototype | HTML |

## Quick start (development)

1. **API** — see [`grapion_one_x_api/README.md`](grapion_one_x_api/README.md): create the virtual environment, `pip install -r requirements.txt`, then
   `uvicorn app.main:app --host 127.0.0.1 --port 8000`.
2. **App** — see [`grapion_one_x_app/README.md`](grapion_one_x_app/README.md): `flutter pub get`, then `flutter run -d chrome`.

Business time is **IST (`Asia/Kolkata`)** everywhere.

## Development vs production

This is the **development** repository. It contains development `.env` files and the development Firebase key on purpose,
so a new developer can run everything after cloning. The **production** repository must not contain them:
production secrets live in the server's environment / secret store, and the development database password, JWT secret
and Firebase key are replaced before go-live.
