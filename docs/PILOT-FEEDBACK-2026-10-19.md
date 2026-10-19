# Pilot feedback — 19 Oct 2026 (decided 19 Oct 2026 → v2.1.0)

Raw points from Homi after the live run. To be concluded collectively; nothing here is implemented yet.

## Booking / posting
1. **Duplicate requests:** the app accepts multiple requests from the same user in the same window. Must be one per window.
2. **Windows open all day** (keep all movement slots visible), but **booking only in real-time mode, max 1 hour in advance**
   (i.e. no evening-for-tomorrow booking in this version).
3. **Who's around widget:** when booking a ride, show a list of drivers and passengers currently posted for that window.
4. **Locked passenger:** once a passenger is locked with a driver, they cannot raise a new request (for that window).

## Cancelling
5. Driver or passenger may **cancel an accepted request with an optional reason** (reason shown to the other side).

## Completion
6. Define the **ride-completion mechanism**, including rides with **multiple passengers** (who confirms what, when it
   counts as complete). Option: let the **driver close the ride** as well.

## Notifications
7. Notification flow is **failing or not developed** in the live run (to be diagnosed: token saved? permission?
   Oppo/Xiaomi battery restrictions? web has no push yet).
8. A **notification permission control in the Settings panel** for both driver and passenger.

## Dashboards / reporting
9. **Driver dashboard:** completed rides, own score, leaderboard with **top 3**.
10. **Admin:** complete statistics and reporting access.

## Reminders / slots (added later the same day)
11. **Per-slot reminders, per user:** for the 4 decided slots, each user can switch a reminder **on/off per slot**,
    applying daily **Monday–Friday** (5 days). The reminder goes out only during the decided slot windows the user
    has enabled.
12. **Consequence:** booking stays available **all day** (any time), which also covers **rotating shifts** — the
    4 decided windows are only used for the *active reminders/notifications*, not as a gate on when you can post.
    (Relates to point 2: real-time booking, max 1 hour ahead, at any hour of the day.)

## Decisions (19 Oct 2026, Homi + Claude)
- Booking: direction + leaving time (now … +60 min, 5-min steps), any hour of the day. Matching = same direction,
  ±15 min, compatible places. The 4 slots remain for reminders and reports only. Home = direction toggle, leaving-time
  picker, live board for the next hour, slot info strip.
- One open post per person; no new post while a ride is active (server-enforced + client hides the button).
- Cancel (ride or post) with an optional reason, shown to the other side.
- Completion: driver "Complete ride" + passenger "I've arrived"; auto-complete when all arrived; 90-min safety net.
- Reminders: per user, per slot, Mon–Fri, sent 10 min before the slot starts, only if no active ride.
- Settings → Notifications: permission status, device registered, "Send me a test notification", slot toggles.
- Points tab: My stats (rides as driver/passenger month + all-time, points, rank) and top-3 highlight.
- Admin report: per-user monthly table + CSV export.
- Points rules unchanged (granted at lock).
