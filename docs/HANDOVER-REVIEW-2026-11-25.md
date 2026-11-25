# Review of the Play Store build by the other developer (25 Nov 2026)

Source: https://github.com/uzairashraf1544-a11y/Carpool (public, pushed 24 Nov 2026, built in Google AI Studio)
Binaries reviewed: "Carpool Package (2)" v6.0 (versionCode 6). The repo's build.gradle.kts still says 5.1 / versionCode 5,
so the source on GitHub is one release behind the uploaded binary.

## What it is
- Native Android, Kotlin + Jetpack Compose, package `com.aistudio.carpool.kjqxcv`, minSdk 24, targetSdk 36.
- Firebase project `gen-lang-client-0717949368`: Auth (email/password + Google) and Firestore only.
  No Cloud Functions, no FCM push, no GPS. Reminders are local alarms on the phone.
- Collections: users, employeeRegistry, rides, passengerNeeds, rideRequests, systemConfig/{sustainability,leaderboard,
  managementReport}, auditLogs, co2Records, adminAnalytics, activePassengerRides.
- Flows: register → PENDING_APPROVAL → admin approves → Home with Driver/Passenger mode switch. Driver publishes
  today's availability (pickup side/zone, seats 1–8, note). Passenger posts a need for today. One tap join or
  "Drive & accept" in a Firestore transaction. Closure: driver "ride happened / didn't happen", passenger
  "I completed / didn't take". CO2 credit per completed passenger leg, totals kept on the user document and
  aggregated into systemConfig/leaderboard and systemConfig/managementReport by the client.
- Design goal: stay inside the Spark free tier for ~300 users (persistent cache, single-document reports).

## Findings that must go to the developer / project owner
1. **Upload keystore and its credentials are in the public repo** (`Abb/my-upload-key.jks`, `Abb/KEYSTORE_CREDENTIALS.txt`,
   and the store/key password hard-coded as a fallback in `app/build.gradle.kts`). Anyone can sign builds as this app.
   Action: make the repo private, remove the files from history, and request an upload key reset in Play Console
   (the app is on Play App Signing, so this is possible). `app/google-services.json` is also committed.
2. **Firestore rules let any user make themselves admin.** `users` create accepts `role` = ADMIN and
   `accountStatus` = ACTIVE from the client, and self-update may move PENDING_APPROVAL → ACTIVE. The approval
   gate and admin-only screens are therefore enforced only by the app UI, not by the server.
3. **Scores are client-trusted.** `totalCo2SavedKg` / `totalCompletedRides` on the user document,
   `systemConfig/leaderboard` (writable by any active user) and `co2Records` (read/create/update by any signed-in
   user) can all be edited by a modified client. `employeeRegistry` documents can be read without signing in.
4. No server logic means no push when a match appears and no late-cancel / no-show handling; users learn of a
   match only when they open the app.
5. Minify is off (readable code in the APK, larger download). Manifest is clean (INTERNET, POST_NOTIFICATIONS,
   RECEIVE_BOOT_COMPLETED) in the repo; the v6.0 APK manifest additionally declares FOREGROUND_SERVICE, WAKE_LOCK,
   USE_BIOMETRIC, ACCESS_NETWORK_STATE, so the Play declarations must follow the binary, not the notes.

## Can the HomiLabs web app be brought in line with it?
Yes, now that the source is available. It is a rebuild of our Flutter web client against their schema, not an edit
of the current one (ours talks to travelbuddy-12d76 with a different model and Cloud Functions).

Needed from the project owner (about 10 minutes in Firebase console):
- Add a **Web app** to project gen-lang-client-0717949368 and send us its config (apiKey, appId, etc. — these are
  not secrets but we still keep them out of git in `client/web-config/`).
- Authentication → Settings → Authorized domains: add `travelbuddy.homilabs.org`.
- Enable Google sign-in for the web client (same provider, no new key).
- If App Check is enforced in the console, register the web app with reCAPTCHA v3/Enterprise.
No rule change is required for a web client (rules are per user, not per platform).

Suggested phases:
1. Member web app: login/register/Google, pending-approval screen, Home (mode switch, publish availability /
   post need, discovery lists, join, drive & accept), active ride card with close options, Activity, Profile,
   Leaderboard. Reads/writes exactly the fields the Android app uses so both clients see the same data.
2. Admin web: approvals, members (block/unblock/remove), reports from systemConfig/managementReport, CSV.
   Data-management (global reset) only if Homi wants it on the web at all.
Reminders stay phone-only (web has no background alarms without push).

Risk: the two clients are kept consistent only by discipline, because there is no server layer. Any field or status
change in a future Android release must be mirrored in the web app. We should propose fixing the rules (item 2–3)
to the owner first; we have the emulator rules test harness to prove a corrected rules file.

## Done the same day
- Registered a Web app in their Firebase project (Homi's account owns it): `1:462593078430:web:dacce55e830b232c09f78f`,
  display name "FFL Travel Buddy Web"; config saved to `../travelbuddy-secrets/ffl-web-config.json`.
- Built `webapp/` (Flutter web) against their data model and rules, tested on the Firestore/Auth emulators with a
  copy of their rules: register/login, publish availability, post request, join, drive & accept, passenger close,
  driver close, CO₂ + leaderboard, admin approvals/members/today/report/audit. No rule denials.
- Still Homi's: upload the zip to Hostinger `/app/`, and in Firebase console → Authentication → Settings →
  Authorized domains add `travelbuddy.homilabs.org` (needed only for "Continue with Google" on the web).
