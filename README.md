# TravelBuddy

Free, volunteer, peer-to-peer carpool app for the FFL community — Township ⇄ Plant only, no payments.
Android (Kotlin + Jetpack Compose), Firebase Auth (email/password) + Cloud Firestore (free Spark plan).

- Package: `com.homilabs.travelbuddy` · Firebase project: `travelbuddy-12d76` (Firestore in asia-south1, Mumbai)
- Website / privacy policy: https://travelbuddy.homilabs.org (source in `website/`)
- Design: *TravelBuddy — Design Document (V1, rev 2)*, plus decisions agreed on 2026-09-30 (below)

## Folder map

| Path | What it is |
| --- | --- |
| `app/` | The Android app |
| `firestore.rules`, `firestore.indexes.json` | Security rules, composite indexes and the 30-day TTL (auto-delete) policies |
| `firestore-tests/` | Security-rules tests (`rules.test.js`) and the emulator test helper (`e2e.mjs`) |
| `scripts/` | `build-release.sh`, `deploy-firestore.sh`, `test-rules.sh`, `backup.sh`, `adb_ui.py` |
| `graphics/` | Icon and feature-graphic sources; `graphics/play/` = Play Store assets |
| `release/PLAY_CONSOLE_GUIDE.md` | Step-by-step Play Console setup, Data safety answers, declarations |
| `website/` | Static website (run `python3 build.py` after editing it) |

**Never in git:** the upload keystore and `google-services.json`. They live in
`/mnt/storage/projects/travelbuddy-secrets/` (next to this folder, not inside it). The keystore password lives only in
your password manager.

## Decisions agreed after the design doc (2026-09-30)

1. **Passenger "I'm waiting" service** needs `FOREGROUND_SERVICE_SPECIAL_USE` (one extra permission). It starts when
   the passenger taps *I'm waiting*, or automatically 10 min before the slot **if the app is open** (Android doesn't
   allow starting it from the background without exact alarms).
2. **Driver live location** lives in `rides/{rideId}/live/loc` (not `driverLoc` in the ride doc) so the rules can limit
   reading it to the ride's driver and confirmed passengers.
3. **Security rules tightened:** passengers can only ask/withdraw (never accept themselves); "take this passenger" can
   change only the driver fields; ride details are frozen after posting; users can't create themselves with extra fields.
4. **Account deletion** in the app (Google Play requirement): Settings → Delete my account.
5. **Leaving time** is picked with −/+ buttons (5-minute steps) — Samsung's number keypad has no ":" key.
6. Contact email: homilabs.smc@gmail.com. Privacy policy hosted on travelbuddy.homilabs.org.

## Everyday commands

```bash
# Build and install the debug app on the connected phone (talks to the REAL Firebase project)
./gradlew installDebug

# Security-rules tests (starts a local emulator; needs Java 21 in ~/.local/jdk)
./scripts/test-rules.sh

# Deploy rules + indexes + TTL policies to the real project
./scripts/deploy-firestore.sh

# Signed release bundle for Google Play (asks for the upload-key password; nothing is saved)
./scripts/build-release.sh

# Local backup snapshot (then copy it to Google Drive)
./scripts/backup.sh
```

### Testing against the local emulator (no real accounts touched)

```bash
# 1. start emulators (ports: firestore 8185, auth 9199)
firebase emulators:start --only auth,firestore --project travelbuddy-12d76
# 2. seed test people + stops around a point, and connect the phone to this computer
node firestore-tests/e2e.mjs seed 28.2687 70.0474
adb reverse tcp:8185 tcp:8185 && adb reverse tcp:9199 tcp:9199
# 3. install a build that uses the emulator
./gradlew installDebug -PtbEmulator      # or: ./gradlew assembleQa  (R8-shrunk, like release)
# 4. play the other people, e.g. Dan posts an offer:
node firestore-tests/e2e.mjs as u_dan postOffer MORNING TO_PLANT 07:25 3
```
Test accounts (emulator only): admin@tb.test, dan@tb.test, pam@tb.test, nadia@tb.test — password in `e2e.mjs`.

## First-time setup on the real project

1. Install the app, register yourself, then in **Firebase console → Firestore → users → your document** set
   `accountStatus` = `ACTIVE` and `role` = `ADMIN` by hand. There is no admin-bootstrap code.
2. In the app's **Admin → Pickup stops**, add the real stops (stand at each stop and tap *Use my GPS*), then **SAVE**.
3. Firebase console → Authentication → Sign-in method: keep only **Email/Password** enabled.
4. Recommended: Firebase console → Authentication → Settings → keep *Email enumeration protection* on.

## Budget (free Spark plan)

One listener each for: own user doc, the ride board (date+slot+direction+OPEN), an open ride, its live location,
and (admins) the pending list. Everything else is a one-time read. Target: < 20,000 reads/day for 200 users.

## Versioning

Bump `versionCode` (+1) and `versionName` in `app/build.gradle.kts` for every upload to Play.
