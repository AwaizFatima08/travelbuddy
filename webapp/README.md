# TravelBuddy web (FFL community carpool)

Flutter web app for https://travelbuddy.homilabs.org/app/ that shares its data with the
TravelBuddy Android app published by the other developer (`com.aistudio.carpool.kjqxcv`,
Firebase project **gen-lang-client-0717949368**, display name "FFL Travel Buddy").
A member can start a ride on the phone and finish it on the web, and the other way round.

The Kotlin source it mirrors lives outside this repo in
`/mnt/storage/projects/travelbuddy-handover/carpool-src-files/` (fetched from
https://github.com/uzairashraf1544-a11y/Carpool). `lib/core/models.dart` is a field-by-field copy of
the Kotlin data classes; `lib/core/repo.dart` mirrors RideRepository / AuthRepository /
UserRepository / AdminRepository, including the Firestore transactions, so both clients pass the same
security rules.

## Layout
- `lib/main.dart` – Firebase init, auth gate (login → complete profile → pending → blocked → shell), navigation.
- `lib/core/models.dart` – users, rides, passengerNeeds, rideRequests, leaderboard, management report, audit log, master data.
- `lib/core/repo.dart` – every Firestore/Auth call. One ride per driver per day, one active ride per passenger,
  one-tap join / drive-and-accept in transactions, driver master close, passenger self close, CO₂ records +
  user totals + top-3 leaderboard, admin actions with audit log.
- `lib/features/` – auth, home (Passenger / Driver), activity, profile, admin (approvals, members, today, reports, audit).
- `lib/firebase_options.dart` – **generated, not committed**: `python3 scripts/gen-ffl-web-options.py`
  reads `../travelbuddy-secrets/ffl-web-config.json` (the Web app's config from `firebase apps:sdkconfig WEB`).

## Build and deploy
```bash
jobq run --name tb-ffl-web -- scripts/build-ffl-web.sh     # → ~/Downloads/travelbuddy-ffl-webapp-<ver>.zip
```
Homi uploads the zip into Hostinger `public_html/app/` (empty the folder first) and extracts it.
Then `bash /mnt/storage/shared/Skills/web-deploy/scripts/live-check.sh https://travelbuddy.homilabs.org /app/`.

## Testing against the emulators (their rules, no production data)
```bash
cd webapp/emulator && JAVA_HOME=$HOME/.local/jdk/jdk-21.0.12.1+1 PATH=$JAVA_HOME/bin:$PATH \
  firebase emulators:start --only auth,firestore --project gen-lang-client-0717949368
bash webapp/emulator/seed.sh                      # admin@, dan@, pam@ test.local
jobq run --name tb-web-emu-build -- flutter build web --release --dart-define=EMULATOR=1 -o build/emu
python3 -m http.server 8099 -d webapp/build/emu   # or the "webapp-emulator-build" launch config
```
`emulator/firestore.rules` is a copy of the Android project's rules (25 Nov 2026); refresh it when they change.

## Things the phone does that the web does not
Local commute reminders (WorkManager alarms), biometric unlock, the admin "global reset" and per-user purge tools.

## Known limits inherited from the Android design
No server logic: approvals, CO₂ totals and the leaderboard are written by whichever client acts. Nothing
pushes a notification when a match appears; members see it when they open the app.
