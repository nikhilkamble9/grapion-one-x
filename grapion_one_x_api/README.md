<!-- Added By Nikhil 22Nov26 11:59 For API setup and overview -->
# Grapion One X — API

The backend for G.One.X: a REST API (FastAPI) on PostgreSQL (Supabase, schema `grapion_one_x`).
All routes are under `/api/v1`. Interactive docs: `http://127.0.0.1:8000/docs` when running locally.

## What it does

| Area | Folder | Summary |
|---|---|---|
| Auth | `app/modules/auth` | Register, login (username / email / mobile), JWT access + refresh tokens, change password, forced password change for owner-created logins |
| Subscriptions | `app/modules/subscriptions` | Module catalog and prices, discounts, subscription requests (weekly / monthly / quarterly / yearly), renewals that extend the end date, cancellations with pro-rated refunds |
| Admin | `app/modules/admin` | Approve / reject requests and cancellations, record payments |
| Super Admin | `app/modules/superadmin` | Admins, module pricing, sales, platform settings, announcements, audit log |
| Businesses | `app/modules/workspaces` | A user's businesses, branches, roles and invites (owner, manager, receptionist, trainer, member) |
| Gym | `app/modules/gym` | Dashboard, branches & timings, holidays, plans, batches, shifts, staff, members, memberships, check-in, payments |
| Notifications | `app/modules/notifications` | In-app bell + Firebase push |
| Meta | `app/modules/meta` | Public support contact, live announcements |

Every request is authorised on the server (role + branch scope + ownership); queries are parameterised; business
times use `APP_TIMEZONE` (IST).

## Requirements

- Python **3.11**
- Access to the PostgreSQL database in `.env`

## Setup

```bash
cd grapion_one_x_api
python -m venv venv
# Windows
venv\Scripts\activate
# macOS / Linux
source venv/bin/activate

pip install -r requirements.txt
```

Settings are read from `.env` in this folder (see `.env.example` for every key). Real environment variables
override `.env`, which is how a server should supply production values.

| Key | Meaning |
|---|---|
| `DATABASE_URL` | Async PostgreSQL URL (`postgresql+asyncpg://…`) |
| `DATABASE_SYNC_URL` | Same database, sync driver (`postgresql+psycopg2://…`) for scripts |
| `DB_SCHEMA` | `grapion_one_x` |
| `JWT_SECRET` | Long random secret for signing tokens — different in production |
| `APP_TIMEZONE` | `Asia/Kolkata` |
| `FIREBASE_CREDENTIALS_PATH` | Firebase service-account file (default `firebase-service-account.json` in this folder) |

<!-- Added By Nikhil 22Nov26 11:59 For Firebase key kept out of Git START -->
**Firebase key (optional for development).** `firebase-service-account.json` is **not in Git** (GitHub blocks
service-account keys). Without it the API runs normally: login, subscriptions, gym, and the in-app 🔔 bell all work.
Only phone/browser **push** notifications are switched off, and the log shows `Firebase disabled: FileNotFoundError`.
To enable push, get the file from the project owner privately (or Firebase console → Project settings →
Service accounts → Generate new private key) and place it in this folder.
<!-- Added By Nikhil 22Nov26 11:59 For Firebase key kept out of Git END -->

## Run

```bash
uvicorn app.main:app --host 127.0.0.1 --port 8000          # local
uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 2 # server (behind HTTPS reverse proxy)
```

## Deploying to a server — checklist

- Set all keys as server environment variables (do not copy the development `.env` / Firebase key).
- New `JWT_SECRET`, rotated database password, new Firebase key.
- `APP_ENV=production`, `DEBUG=False`.
- Restrict CORS `allow_origins` in `app/main.py` to the real app/web domains (it is `*` for development).
- Serve over HTTPS only.

## Folder layout

```
app/
  main.py            app + routers + CORS
  core/              config, security (JWT, argon2), push, platform settings
  db/                models, async session
  modules/<area>/    router (+ schemas) per area
requirements.txt     pinned dependencies
.env.example         every setting, with placeholders
```
