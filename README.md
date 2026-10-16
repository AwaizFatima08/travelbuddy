# TravelBuddy

Free, volunteer carpool app for the FFL community — Township ⇄ Plant. No payments.
**v2** = Flutter (Android app + web app) on Firebase (Auth, Firestore, Cloud Functions, Messaging).

- Package: `com.homilabs.travelbuddy` · Firebase project: `travelbuddy-12d76` (Firestore + Functions in asia-south1, Mumbai; Blaze plan)
- Website / privacy policy: https://travelbuddy.homilabs.org · web app: https://travelbuddy.homilabs.org/app/
- Design: `docs/DESIGN-v2.md` (decisions of 15 Oct 2026). v1 (native Android) is kept in `legacy/v1-android/`.
- A HomiLabs app. Acknowledgement: Awaiz Fatima.

## Folder map

| Path | What it is |
| --- | --- |
| `client/` | Flutter app (Android + web). `lib/core` models/repo/clock · `lib/features` screens · `lib/services` push + live location |
| `functions/` | Cloud Functions: matching notifications, ride locking, points, no-shows, reminders, monthly totals, reports |
| `firestore.rules`, `firestore.indexes.json` | Security rules, composite indexes, TTL (auto-delete) policies |
| `firestore-tests/` | Rules tests (`rules.test.js`, 15) · points-system tests (`points.test.mjs`, 12, runs the functions in the emulator) · `e2e.mjs` helper |
| `scripts/` | `build-release.sh` (signed AAB) · `build-web.sh` (zip for the website) · `deploy-firestore.sh` · `test-rules.sh` · `backup.sh` · `gen-firebase-options.py` · `adb_ui.py` |
| `graphics/` | Icon + feature-graphic sources; `graphics/play/` = Play Store assets |
| `release/PLAY_CONSOLE_GUIDE.md` | Play Console steps, Data safety answers, declarations |
| `website/` | Static site (run `python3 build.py` after editing) |
| `docs/` | Design documents |

**Never in git:** the upload keystore, `google-services.json`, `firebase-web-config.json` and the generated
`client/lib/firebase_options.dart`. The secrets live in `/mnt/storage/projects/travelbuddy-secrets/` (next to this
folder). `scripts/gen-firebase-options.py` regenerates `firebase_options.dart` from them.

## Contact / support

- Public contact and Firebase support email: **support@travelbuddy.homilabs.org** (mailbox on the Hostinger domain).
- Firebase public-facing name is set to **TravelBuddy** (Project settings → General), so reset emails say "TravelBuddy".

## Everyday commands

```bash
python3 scripts/gen-firebase-options.py     # once after cloning / when Firebase config changes
cd client && flutter run                     # debug on the connected phone
./scripts/test-rules.sh                      # rules tests in the local emulator (Java 21 in ~/.local/jdk)
./scripts/test-points.sh                     # points-system suite: runs the real Cloud Functions in the emulator (12 cases)
./scripts/deploy-firestore.sh                # rules + indexes + TTL to the real project
firebase deploy --only functions             # server logic
./scripts/build-release.sh                   # signed Play bundle (asks for the upload-key password)
./scripts/build-web.sh                       # web zip → upload to the site's /app folder in Hostinger
./scripts/backup.sh                          # local snapshot → then copy to Google Drive
```

## First-time setup on the real project

1. Register in the app, then in **Firebase console → Firestore → users → your doc** set `accountStatus = ACTIVE`
   and `role = ADMIN` by hand. There is no admin-bootstrap code.
2. Open the app → it offers **Create FFL site** (places + windows). Then **Settings → Admin → Pickup places**:
   stand at each place, *Use my GPS*, SAVE.
3. Authentication → Sign-in method: Email/Password and Google only.

## How it works (short)

- Every member chooses **Driving** or **Riding** per trip. Drivers offer seats; passengers post a request or join a car.
- Matching = same site, direction, window, time ±15 min, same/neighbour pickup place. Matches get a push + in-app notification.
- Locking is a server transaction (no double booking). Points: driver +2 (with ≥1 passenger), passenger +1,
  late cancel −1, no-show −2. Leaderboard and kg CO₂ per month.
- After locking, both sides share position with each other only, until pickup (Android: foreground service;
  web: while open). One "close by" alert.

## Versioning

Bump `version:` in `client/pubspec.yaml` (e.g. `2.0.1+3`) for every Play upload.
