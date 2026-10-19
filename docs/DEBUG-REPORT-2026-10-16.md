# TravelBuddy v2 — Device debug report (15–16 Oct 2026)

Test build: Flutter client 2.0.0+2 (debug and release-shrunk variants), Cloud Functions as deployed, real Firebase
project `travelbuddy-12d76`. All flows below were run against the **live** project (no emulated backend) with
throw-away test accounts (deleted afterwards through the app's own "Delete my account").

**Devices**

| Label | Device | Android | Role in tests |
| --- | --- | --- | --- |
| S9 | Samsung Galaxy Tab S9 FE (SM-X510), Wi-Fi | 16 | Admin tester, then passenger "Pam" |
| Oppo | Oppo CPH2743 | 16 | Driver "Dan" (first run), passenger "Pam" (second run) |
| EMU | Android emulator pixel6_api35 on homi-nas (2 GB, 2 cores, headless) | 15 | Second person for two-device flows; GPS simulation |
| WEB | Web app (built-in browser; later the hosted https://travelbuddy.homilabs.org/app/) | — | Second person; Google sign-in by Homi |

Legend: ✅ passed · 🔧 bug found and fixed, then re-run ✅ · ⏳ time-gated, run later the same day ✅.

## 1. Sign-up, sign-in, password

| # | Flow | Device | Result |
| --- | --- | --- | --- |
| 1.1 | App launch, logo/branding, "A HomiLabs app · for the FFL community only" | S9, Oppo, EMU | ✅ (dark-mode text bug from v1 not present) |
| 1.2 | Register (8 fields, validation, "I have a car" toggle) → Next | S9, Oppo, EMU | ✅ |
| 1.3 | FFL-only disclaimer card on Register | S9, WEB | ✅ |
| 1.4 | Consent screen → "Agree & register" | S9, Oppo, EMU | ✅ |
| 1.5 | Flash of the Register form between account creation and profile save | — | 🔧 spinner shown while registering |
| 1.6 | "Waiting for approval" screen, details shown, Log out / Delete my account links | S9, Oppo, EMU | ✅ |
| 1.7 | Pending screen flips to Home **by itself** when approved | S9 (console promotion), EMU (admin approval) | ✅ |
| 1.8 | Email login, wrong-password message | S9, EMU, WEB (hosted) | ✅ "Wrong email or password." |
| 1.9 | Forgot password → reset email received (project name later set to "TravelBuddy") | S9 → Homi's inbox | ✅ |
| 1.10 | "Continue with Google" opens the account picker; cancel handled ("Sign-in cancelled.") | S9 | ✅ |
| 1.11 | Google sign-in, existing approved email → straight to Home | WEB (Homi, homi55.home@gmail.com) | ✅ |
| 1.12 | Google sign-in, **new** account → pre-filled Register (email locked, no password) → consent → pending → approval → Home | WEB (Homi, homilabs.smc@gmail.com) | ✅ |
| 1.13 | Log out | S9, Oppo, EMU | ✅ |
| 1.14 | Delete my account (password re-entry; Google users re-confirm) → profile + sign-in removed, rides left, seat restored | S9, Oppo, EMU | 🔧 "Delete forever" stayed disabled while typing — fixed; then ✅ ×4 |

## 2. Admin

| # | Flow | Device | Result |
| --- | --- | --- | --- |
| 2.1 | First admin: role set by hand in Firebase console (no bootstrap code) | S9 | ✅ |
| 2.2 | "Create FFL site" (13 places, 4 windows) from the app | S9 | 🔧 three server-side setup blockers (Compute API, build-account role, Cloud Run invoker, runtime roles) — fixed; then ✅ |
| 2.3 | Settings badge with pending count; Admin tile badge | S9 | ✅ |
| 2.4 | "New registration" alert to every admin (in-app + push) | S9, Homi's admin accounts | ✅ |
| 2.5 | Approve with optional reason → audit entry "APPROVED by …" | S9 (test admin), Homi's real admin | ✅ |
| 2.6 | Block with reason → BLOCKED screen shows reason; Unblock | S9 (v1-equivalent flow) | ✅ in v1 session; not re-run by a real admin in v2 |
| 2.7 | Members & audit: find by email/employee ID, last 30 admin actions | S9 | ✅ |
| 2.8 | Pickup places editor: add, GPS capture ("Use my GPS", ±accuracy), neighbours, reorder, enable/disable, SAVE | S9 (v1) / code path identical in v2 | ✅ |
| 2.9 | Commute windows editor | — | not exercised (data-only screen) |
| 2.10 | No-show disputes list → Uphold / Cancel report | S9 | ✅ (cancel) |
| 2.11 | Reports (month, rides, seats, CO₂, by window, by department, members, top 20) | S9 | ✅ |

## 3. Driver flows

| # | Flow | Device | Result |
| --- | --- | --- | --- |
| 3.1 | "Today I am… Driving / Riding" (per trip; last choice remembered) | S9, Oppo, EMU | ✅ |
| 3.2 | Window chips (Now/Next, Today/Tomorrow), direction label, board moves on when a window ends | S9, EMU | ✅ |
| 3.3 | Offer seats sheet: −/+ leaving time (5-min steps), places nearest-first, seats 1–4, auto-accept toggle, note | S9, EMU | ✅ |
| 3.4 | Offer appears on passengers' boards instantly (real-time) | S9 → WEB, EMU → S9/Oppo | ✅ |
| 3.5 | Matching push to waiting passengers ("… is driving at 17:00, 3 seat(s)") | EMU → S9 | ✅ (after FCM token fix 🔧) |
| 3.6 | Accept a waiting passenger's request → ride locks | WEB, EMU | ✅ |
| 3.7 | Auto-accept join by passenger → "… joined your ride" alert, seats count down | S9, EMU | ✅ |
| 3.8 | Duplicate "needs a ride" alert on direct joins | — | 🔧 suppressed |
| 3.9 | FULL car still shown on Home ("Your car is full (1 seats)") | EMU | 🔧 then ✅ |
| 3.10 | Start sharing position (location permission prompt → foreground notification "TravelBuddy ride") | S9, EMU | ✅ |
| 3.11 | Live distance to passenger (3.0 km → 1.2 km → 250 m) and **"… is close by"** alert, once | EMU with simulated GPS | ✅ |
| 3.12 | Sharing stops automatically when every passenger is picked up | EMU | 🔧 then ✅ (notification gone within 4 s) |
| 3.13 | Mark passenger "Picked up" | EMU | ✅ |
| 3.14 | Complete ride → COMPLETED, points kept, live docs cleared | S9, EMU | ✅ |
| 3.15 | Cancel ride (≥10 min before): passengers told (push), requests reopen, points reversed | S9, WEB | ✅ |
| 3.16 | Cancel own open post | S9 | ✅ |
| 3.17 | One role per window (new offer closes own open request) | server | 🔧 added; covered by the points suite |

## 4. Passenger flows

| # | Flow | Device | Result |
| --- | --- | --- | --- |
| 4.1 | No car → "Driving" disabled, "Riding" forced, hint shown | S9 (Pam) | 🔧 then ✅ |
| 4.2 | "I need a ride" sheet → request posted; drivers on the route get a push | S9 | ✅ |
| 4.3 | Join a car (pickup/drop pickers, auto-accept) → "Ride locked ✅" alert, +1 point | WEB, S9, Oppo | ✅ |
| 4.4 | Join refused when already in a ride for that window / car full | server + suite | ✅ |
| 4.5 | "I'm on my way / waiting" → shares position; **"Your ride is ~1 min away"** alert, once | S9 with EMU driver approaching | ✅ |
| 4.6 | "I've been picked up" | WEB, Oppo | ✅ |
| 4.7 | Leave this ride (≥10 min before): −1, seat back, driver notified | S9 (Pam) | 🔧 server transaction bug — fixed; then ✅ |
| 4.8 | Ride cancelled by driver → push "Ride cancelled", request reopened | S9 | ✅ |
| 4.9 | 10-minute reminder push ("Ride in ~10 minutes") | S9 | ⏳ ✅ at 13:35 |
| 4.10 | Report driver as no-show → driver −2 and ride points removed, ride NO_SHOW; push to the driver | S9 → EMU | ⏳ ✅ |
| 4.11 | Dispute within 24 h → admins alerted → admin cancels report → points restored | EMU → S9 | ✅ |
| 4.12 | Notifications tab: list, unread badge, tap opens the ride | S9, WEB | ✅ |
| 4.13 | Points tab: all-time, monthly leaderboard, departments, personal history | WEB, S9 | 🔧 two bugs (nested totals; screen crash on web) — fixed; then ✅ |
| 4.14 | My rides / History list | S9, WEB | ✅ |
| 4.15 | Settings: profile, car toggle, edit phone/department/township, notifications, battery note, privacy link, About/acknowledgement | S9 | ✅ |

## 5. Web app (hosted)

| # | Flow | Result |
| --- | --- | --- |
| 5.1 | https://travelbuddy.homilabs.org/app/ loads, no console errors, base path correct | ✅ |
| 5.2 | Email + Google sign-in from the real domain | ✅ |
| 5.3 | Board, join, ride screen, alerts, points, admin | ✅ (tested on the local build; hosted build is the same code) |
| 5.4 | Browser push, browser location sharing | not wired yet (web phase) |

## 6. Server-side suites (local emulator, real code)

- Security rules: 15 tests ✅ (`scripts/test-rules.sh`).
- Points system: 12 cases ✅ (`scripts/test-points.sh`) — lock, caps, early/late cancel and leave, both no-show
  directions, dispute outcomes, cancel post, blocked/pending users, account deletion.

## 7. Bugs found and fixed during the device runs (all re-verified)

1. Registration form flashed between account creation and profile save.
2. Monthly totals written as flat dotted keys → leaderboard empty.
3. Points and Disputes screens crashed on web (inherited widget read in `initState`).
4. Wrong FCM API → no push tokens saved → no OS notifications.
5. Duplicate "needs a ride" alert on direct joins.
6. Delete-account dialog button never enabled while typing.
7. Passenger "Leave this ride" always failed (transaction read after write).
8. Driver kept sharing location after all pickups.
9. FULL car disappeared from the driver's Home.
10. "Driving" stayed selected after turning off "I have a car".
11. Logout didn't remove the device's push token.
12. Account deletion mid-ride didn't restore the driver's seat.
13. Admin SDK import differed between production and emulator (fixed to the modular import).

Infrastructure fixes on the Google side (first deploy of a new project): Compute Engine API, Cloud Build role for the
build account, public invoker on the callable services, Firestore/FCM roles for the runtime account, Kotlin plugin
version, core-library desugaring, Firebase public-facing name and support email, authorized domain for Google sign-in.

## 8. Not exercised on devices (covered by suites or pending)

- Block → Unblock by a real admin account in v2 (same code as v1; suite covers server rules).
- Commute windows editor.
- Late cancel (<10 min) and multi-passenger +2-once — covered by the points suite only.
- Auto-complete 90 min after departure (scheduled `tick`) — reminder part verified; auto-complete not observed.
- Web push and web location sharing — web phase.
