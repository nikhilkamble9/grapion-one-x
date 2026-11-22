<!-- Modified By Nikhil 22Nov26 11:59 For real app description. Old: default Flutter "A new Flutter project" README -->
# Grapion One X — App

The Flutter app for G.One.X (Android, iOS and web). One login, many businesses: users subscribe to modules,
then work inside each business with the role they were given.

## Who sees what

| User | Sees |
|---|---|
| New user | Intro → register / login → choose modules and period → request sent for approval |
| Subscribed owner | Their businesses; Gym: dashboard, members, payments, plans, batches, staff, shifts, holidays & timings, branches & settings |
| Manager / receptionist / trainer | The same business, limited to their branch and permissions |
| Member | Their gym page (in development) |
| Admin | Approval queue, cancellations, all modules |
| Super Admin | Everything an admin sees + admins, pricing, sales, platform settings, announcements, audit log |

Users with several businesses or roles get a picker after login; one entry opens directly.

## Modules

| Module | Status |
|---|---|
| Grapion Gym | Live (staff attendance, member page and reports in progress) |
| Grapion Wedding | In development |
| Grapion Medical | In development |
| Grapion Academy | In development |

## Requirements

- Flutter **3.47** (Dart 3.13+)
- The API running (see [`../grapion_one_x_api/README.md`](../grapion_one_x_api/README.md))

## Run

```bash
flutter pub get
flutter run -d chrome                                   # web, debug
flutter run -d web-server --web-port 3000               # web, open http://localhost:3000
flutter run -d <device-id>                              # Android / iOS
```

The API address is in `lib/services/api_client.dart` (`http://127.0.0.1:8000/api/v1` for local development).
On a phone, `127.0.0.1` is the phone itself — use the PC's LAN IP or the live API address.

## Checks

```bash
flutter analyze
flutter test
```

## Folder layout

```
lib/
  main.dart            start-up, theme, Firebase
  services/            API client, secure token storage, push
  theme/               colours, spacing, motion tokens
  widgets/             shared UI pieces
  screens/             auth, home/entry routing, subscription, profile, admin
  modules/gym/         Grapion Gym screens
  modules/module_registry.dart
```
