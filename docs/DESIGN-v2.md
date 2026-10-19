# TravelBuddy v2 — Design Document

15 Oct 2026 · HomiLabs · replaces V1 rev 2 (native Android). Open points settled with Homi on 15 Oct 2026.

## 1. Purpose

Make car sharing between the FFL Township and the Plant site reliable enough that people actually use it,
so fewer cars make the trip and the community can see its green impact.

- ~250 employees, everyone knows everyone. Trips are 2–3 km (5–8 min), mostly in own cars.
- Township homes lie within ~1.5 km; the plant has several parking/arrival points.
- Free, volunteer, no money. Equal-opportunity: no gender or other preference filters.
- Built so the same app can later serve other locations, shift timings and intercity trips without a rewrite.

## 2. Scope

| Version | Contents |
| --- | --- |
| **v2.0 (this build)** | FFL Township ⇄ Plant, general shift (07:30–17:15): morning, lunch out, lunch in, evening. Ride now + book ahead. Live approach for both sides. Green points, no-show penalty, monthly leaderboard and reports. Android app + web app (iPhone users). |
| v2.1 (later) | Round-the-clock shift windows (06:00, 14:00, 22:00) — switched on as data, no redesign |
| v2.2 (later) | Intercity trips (Lahore, Multan, Islamabad, Karachi, Faisalabad), free of cost |
| Later | Other locations (new "site" with its own places and windows) |

**Out of v2.0:** payments, chat, SMS/WhatsApp, maps screen, ratings, gender filters, Urdu, iPhone native app.

## 3. Platform and technology

| Part | Choice |
| --- | --- |
| App | **Flutter** — one codebase builds the Android app and the web app |
| Web app | Hosted on the existing Hostinger site at **`https://travelbuddy.homilabs.org/app/`** (static Flutter web build, uploaded like the website); iPhone users "Add to Home Screen". The landing, privacy and delete-account pages stay where they are. |
| Sign-in | Firebase Auth: **email + password** (any email) and **Google sign-in** |
| Data | Cloud Firestore, existing project `travelbuddy-12d76` (Mumbai, Blaze plan) |
| Server logic | **Cloud Functions** (Blaze): matching notifications, locking a ride, points, no-shows, monthly totals |
| Notifications | Firebase Cloud Messaging: push on Android and web, plus an in-app notification list |
| Kept from V1 | Firebase project, package `com.homilabs.travelbuddy`, upload key, Play listing, website + privacy pages, approval/audit model, account deletion, rules-testing approach |
| Budget guard | Billing budget alert at USD 5/month; design target stays within the free monthly allowance |

**Honest web limits (iPhone users):** everything on screen works; notifications only after "Add to Home Screen"
(iOS 16.4+); location is shared only while the web app is open on screen. Android shares location with the screen off.

## 4. Places and commute windows (admin-managed data)

**Township places:** D-Type Play Ground · E-Type End · E-Modified Parking · Mosque Roundabout · BOQ Parking
**Plant places:** Admin Building · CCR Parking · MCR Parking · L&DC · Workshop Parking · Warehouse Parking · HSE Building · Laboratory

Each place has a name, map point (captured on site by the admin's GPS), side (township/plant) and **neighbours**
(places close enough to share a pickup, e.g. E-Type End ↔ E-Modified Parking).

**Windows (general shift):**

| Window | Direction | Time |
| --- | --- | --- |
| Morning | Township → Plant | 07:00 – 07:40 |
| Lunch out | Plant → Township | 12:45 – 13:15 |
| Lunch in | Township → Plant | 14:00 – 14:30 |
| Evening | Plant → Township | 17:15 – 18:00 |

Windows live in data per site, so shift windows (06:00 / 14:00 / 22:00) are added later without code changes.

## 5. Accounts

- Register with name, email (or Google), employee ID, department, phone, township house/block, and **"I have a car"** (yes/no; can change later).
- Short consent → **Pending** → admin approves people they know → **Active**. Blocked/unblocked with reason, audit trail kept.
- Admin role is set by hand in the Firebase console (no bootstrap code).
- Phone numbers are visible to approved members (tap to call). Account deletion in the app and on the website.

## 6. Core flow — "Today I'm…"

Every time a user opens the app during or before a window, the home screen asks **"Driving or riding?"**
The role is chosen **per trip**, not per account; the last choice is pre-selected. Users without a car only see "riding".

### 6.1 Driver
1. Taps **I'm driving** → seats (1–4), leaving time (now / +5 / +10 / +15 min, or a booked time), starting place (nearest pre-selected), destination place.
2. The app shows passengers already waiting on that route and notifies matching passengers.
3. The driver receives **ride requests** as notifications; each shows name, pickup place and time → **Accept** / **Skip**.
4. Each accept fills a seat; while seats remain, the driver keeps receiving requests (2nd, 3rd…). Full → stops.

### 6.2 Passenger
1. Taps **I need a ride** → pickup place (nearest pre-selected), drop place, time (now or booked).
2. The app shows drivers already offering on that route and notifies matching drivers.
3. The passenger can **Join** an offered car directly, or wait for a driver to accept the request.

### 6.3 Matching rule (who gets notified)
Same site · same direction · overlapping time (±15 min) · pickup place is the same as, or a neighbour of, the driver's start (or on the driver's way, per admin-set neighbours) · driver has a free seat.

### 6.4 Locking
A ride is **locked** the moment one side accepts the other (driver accepts a request, or passenger joins an offer and the driver had "auto-accept" on — default on).
Locking is done by a server function in one transaction, so two drivers can never take the same passenger and a car can never be over-filled.
Both people get a "Ride locked" notification with name, car seat count, place and time.

### 6.5 Book ahead
Same flow, chosen for a future window: in the evening for tomorrow morning, in the morning for lunch, etc.
Reminders 10 min before departure to both sides. Bookings older than the window are closed automatically.

### 6.6 Cancelling
Either side may cancel. Cancelling **≥ 10 min before departure** has no penalty and frees the seat
(the passenger's request goes back to "waiting" and matching drivers are notified again).

## 7. Live approach (after locking)

- From 10 min before departure (or immediately for "ride now") until pickup, **both** phones share location with **each other only**.
- Each sees "Driver ~600 m, ~2 min" / "Passenger is at E-Type End", plus one **approaching alert** (under 300 m or 1 min — distances are short here).
- Pickup is confirmed with one tap (**Picked up**) by either side, or automatically when both phones are within 50 m for 1 min. Sharing then stops; the 5-minute drive itself is not tracked.
- Auto-stop 30 min after the planned departure. Android uses a visible foreground notification; web shares only while open.
- Arrival: the driver taps **Arrived** (or it completes automatically when the driver's phone reaches a plant/township place).

## 8. Green points

| Event | Driver | Passenger |
| --- | --- | --- |
| Ride locked (per leg, at least one passenger) | **+2** | **+1** |
| Solo driving | 0 | — |
| Cancel ≥ 10 min before departure | points from that ride removed | points removed |
| Late cancel (< 10 min) | −1 | −1 |
| **No-show** (didn't turn up) | −2 (and ride points removed) | −2 (and ride points removed) |
| Other side was a no-show | keeps their +2/+1 | keeps their +1 |

- Points are written only by the server (users can't edit them). Every change is a line in a points ledger, so totals can be audited.
- **No-show** is reported by the person who was at the pickup place (the app checks their phone was there); the reported person can dispute once; admin decides disputes.
- Daily cap: one locked leg per window per person (max 4 legs/day).
- **CO₂ saved** shown alongside points: per passenger leg ≈ distance (admin setting, default 2.5 km) × 0.17 kg/km ≈ 0.4 kg.
- **Leaderboard** (monthly, resets on the 1st): top drivers, top passengers, top departments, community total kg CO₂ and cars saved. Personal monthly summary for each user.
- **Recognition:** monthly certificate-style "Green Commuter" badge on the profile/leaderboard; prizes only if management approves (outside the app).

## 9. Notifications (in-app + push; no SMS/WhatsApp)

| To | When |
| --- | --- |
| Drivers on the route | A passenger needs a ride (now or booked) |
| Passengers on the route | A driver offers seats (now or booked) |
| Both | Ride locked · cancelled · reminder 10 min before · approaching alert · picked up |
| User | Approved/blocked, no-show reported against you, monthly summary |
| Admin | New registration, no-show dispute |

Users can mute "new offers/requests near me" outside their usual windows. Every push also appears in an in-app list.

## 10. Admin

Pending approvals · block/unblock with reason · audit trail · places editor (GPS capture, neighbours, enable/disable) ·
windows editor · no-show disputes · reports (rides, seats filled, cars saved, CO₂, points, by department, by window) ·
monthly leaderboard export (CSV).

## 11. Data model (Firestore, multi-site from day one)

```
sites/{siteId}                 name, timezone, places[], windows[], co2PerKm, legKm
users/{uid}                    profile, hasCar, siteId, accountStatus, role, audit[], fcmTokens[]
posts/{postId}                 siteId, kind OFFER|REQUEST, userId, windowId, date, departAt, fromPlace, toPlace,
                               seats, seatsLeft, status OPEN|FULL|CLOSED|CANCELLED, deleteAt (30 d)
rides/{rideId}                 siteId, driverId, passengerIds[], postIds[], departAt, places,
                               status LOCKED|PICKED_UP|COMPLETED|CANCELLED|NO_SHOW, deleteAt (30 d)
rides/{rideId}/live/{uid}      lat, lng, at (participants only; deleted at pickup)
points/{entryId}               uid, siteId, rideId, delta, reason, at          (server-written ledger)
monthly/{siteId_YYYY-MM}       per-user and per-department totals, CO₂, cars saved (server-written)
notifications/{uid}/items/{id} in-app notification list (auto-delete after 30 d)
```
Intercity (v2.2) adds `kind = INTERCITY` posts with city and date — no change to the rest.

## 12. Security

- Only approved members read anything; users write only their own posts and their own location.
- Locking, points, no-shows and monthly totals are server-only (Cloud Functions with admin rights).
- Live location readable only by the other people in the same ride; deleted at pickup.
- Rules tested in the emulator before every deploy (same approach as V1).

## 13. Play Store / policy impact

- Location: foreground service for "approaching pickup" (both roles); no background location. Declaration + demo video again.
- Data safety updated: precise location now for passengers too; Google sign-in.
- Same package and upload key, so v2 ships as an update (versionCode 2) to the existing listing.

## 14. Build order (one step at a time, each tested and approved)

1. Flutter project skeleton (Android + web), Firebase connected, web build served from `travelbuddy.homilabs.org/app/`
2. Sign-in (email + Google), registration, consent, pending, approval, admin basics
3. Site data: places + windows, admin editors
4. "Driving or riding?" home, posts (offer/request), live lists per window
5. Cloud Functions: matching notifications (FCM push + in-app list), locking transaction
6. Book ahead, reminders, cancelling rules
7. Live approach both ways (Android foreground service; web while open), pickup/arrival
8. Points ledger, no-shows + disputes, CO₂
9. Leaderboard, monthly summary, admin reports + CSV
10. Security rules + tests, full device test (Android + iPhone Safari), budget alert
11. Play release (update) + web launch

## 15. Decisions log (15 Oct 2026)

| # | Decision |
| --- | --- |
| 1 | Penalties: no-show −2 (and ride points removed), late cancel (< 10 min) −1 |
| 2 | Points (+2 driver / +1 passenger) granted when a ride locks; removed on cancel or no-show |
| 3 | Lunch windows: out 12:45–13:15, back 14:00–14:30 |
| 4 | Auto-accept on by default when a passenger joins an offered car; driver can switch it off |
| 5 | Web app at `travelbuddy.homilabs.org/app/` on the existing Hostinger site (no new DNS record) |
| — | Platform Flutter (Android + web); Blaze plan already on; solo driving earns 0; no gender filters; intercity later and free; login by any email or Google, no SMS/WhatsApp; English only; v2.0 = general shift 07:30–17:15 |


## 16. v2.1.0 changes (decided 19 Oct 2026 after the pilot)

See `docs/PILOT-FEEDBACK-2026-10-19.md` for the full list. In short: all-day booking (direction + leaving time within the
next hour, matching ±15 min), one open post per person and none while a ride is active, cancel with optional reason,
passenger "I've arrived" + driver close + 90-min safety net, per-slot Mon–Fri reminders 10 min before the slot,
notification controls and test button in Settings, My-stats card with top 3, admin per-user table + CSV export.
§4 windows are now used only for reminders and reports.
