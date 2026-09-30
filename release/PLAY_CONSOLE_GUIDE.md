# TravelBuddy — Play Console guide (internal testing → closed testing)

Everything you need to paste into Google Play Console, in order. Files are in `graphics/play/`.

## 1. Build the upload file

```bash
./scripts/build-release.sh
```
It asks for the upload-key password and produces `app/build/outputs/bundle/release/app-release.aab`.

## 2. Create the app

Play Console → **Create app**
- App name: `TravelBuddy`
- Default language: English (United Kingdom) or (United States)
- App or game: **App** · Free or paid: **Free**
- Tick the declarations → **Create app**

## 3. Store listing (Grow → Store presence → Main store listing)

**Short description (≤ 80 chars)**
```
Free Township ⇄ Plant carpool for the FFL community. Offer or find a seat.
```

**Full description**
```
TravelBuddy is a free, volunteer carpool app for the FFL (Fatima Fertilizer) community. It helps colleagues share rides between the Township and the Plant site — no money involved.

• Offer seats: drivers post a ride for one of four commute slots (Morning, Lunch out, Lunch in, Evening).
• Find a seat: ask a driver for a seat, or post a request that any driver can take.
• Pickup stops: choose from the admin's list of stops, sorted nearest-first.
• Tap to call: approved members can call each other to coordinate.
• Know when to leave: once the driver starts the ride, confirmed passengers see how far away the driver is and get one alert when the driver is about 2 minutes away.
• Private: every member is approved by the admin. The driver's location is shared only with that ride's confirmed passengers, only while the ride is in progress, with a visible notification.
• Ride history for the last 30 days; older rides are deleted automatically.
• Optional fingerprint/face unlock.

TravelBuddy is a private arrangement between colleagues. It does not handle payments and is not a taxi or transport service.
```

**Graphics**
| Field | File |
| --- | --- |
| App icon (512×512) | `graphics/play/play_icon_512.png` |
| Feature graphic (1024×500) | `graphics/play/feature_graphic_1024x500.png` |
| Phone screenshots (2–8) | `graphics/play/screenshot_1_board.png` … `screenshot_4_settings.png` |

Category: **Maps & Navigation** (or Travel & Local) · Contact email: `homilabs.smc@gmail.com` ·
Website: `https://travelbuddy.homilabs.org`

## 4. App content (Policy → App content)

| Section | Answer |
| --- | --- |
| Privacy policy | `https://travelbuddy.homilabs.org/privacy.html` |
| App access | **All or some functionality is restricted** → add instructions + a reviewer test account (see §7) |
| Ads | No, my app does not contain ads |
| Content rating | Questionnaire: category *Utility, productivity, communication or other*; answer **No** to violence, sexual content, gambling, etc. Users **can** interact/exchange info (phone numbers between approved members) → Yes; shares location with other users → Yes |
| Target audience | **18 and over** only |
| News app | No |
| Data safety | See §5 |
| Government app | No |
| Financial features | My app doesn't provide any financial features |
| Health | No health features |
| Foreground service permissions | See §6 |
| Location permission (foreground only) | See §6 |

## 5. Data safety form

**Does your app collect or share any of the required user data types?** Yes
**Is all of the user data encrypted in transit?** Yes
**Do you provide a way for users to request that their data is deleted?** Yes —
in-app (Settings → Delete my account) and `https://travelbuddy.homilabs.org/delete-account.html`

**Account creation:** "My app allows users to create an account" → username + password (email) →
Delete-account URL: `https://travelbuddy.homilabs.org/delete-account.html`

| Data type | Collected | Shared* | Optional? | Purposes |
| --- | --- | --- | --- | --- |
| Personal info → Name | Yes | No | Required | App functionality, Account management |
| Personal info → Email address | Yes | No | Required | App functionality, Account management |
| Personal info → Phone number | Yes | No | Required | App functionality |
| Personal info → Address (township house/block) | Yes | No | Required | App functionality, Account management |
| Personal info → Other info (employee ID, department) | Yes | No | Required | Account management |
| Location → Precise location | Yes | No | Optional (drivers who start a ride) | App functionality |
| App activity → Other user-generated content (ride posts, notes) | Yes | No | Required | App functionality |

*"Shared" in Google's sense means sent to a third party. Showing data to other members inside the app after a
user's own action (posting a ride, starting a ride) is not "sharing" under the Data safety definitions.
Approximate location is used only on the phone to sort stops (not collected). No data is processed ephemerally for ads,
analytics or crash reporting — none of those SDKs are included.

## 6. Permission declarations

### Location (foreground only — no background location)
If asked "Why does your app need location?":
```
Drivers share their live location with the confirmed passengers of their own ride, only between tapping "Start ride" and "Complete"/"Cancel" (auto-stops after 45 minutes), so passengers know when to walk to the pickup stop. Location is also used on the phone to sort pickup stops nearest-first. Location is never accessed in the background: sharing runs only inside a foreground service with a visible notification.
```
Demo video: upload `graphics/play/location_demo_video.mp4` to YouTube as **Unlisted** and paste the link.
(It shows the in-app explanation → Android permission prompt → Start ride → "Sharing your location" → Complete.)

### Foreground service types (Policy → App content → Foreground service permissions)
**FOREGROUND_SERVICE_LOCATION** (DriverLocationService)
```
Task: Navigation / location sharing during a user-started carpool ride. The driver taps "Start ride"; the app shares the driver's location with that ride's confirmed passengers until the driver taps Complete or Cancel (max 45 minutes). The user can stop it from the notification. Impact if deferred or interrupted: passengers can't see how far the driver is and miss their pickup.
```
**FOREGROUND_SERVICE_SPECIAL_USE** (PassengerWaitService) — subtype declared in the manifest
```
Carpool pickup alert. When a passenger taps "I'm waiting" (or opens the app within 10 minutes of their ride), the app keeps listening to that one confirmed ride so it can show the driver's distance and alert the passenger once when the driver is about 2 minutes away — including with the screen off. It ends when the passenger taps "Picked up", the ride ends, or after 90 minutes. No other foreground service type fits: it does not use the passenger's location, sync data, or play media.
```
Use the same demo video, or record a short second clip of "I'm waiting" → alert.

## 7. Reviewer access (App access)

Google's reviewers need an approved account. In the real app:
1. Register a reviewer account (e.g. a Gmail you create for this), then approve it from your Admin tab.
2. Paste into *App access*: the email, the password, and:
```
TravelBuddy is for approved members of the FFL community. This test account is already approved. Log in with the details above. To see a ride: tap Post → "I'm driving" → Post; then open it from the board. "Start ride" demonstrates location sharing.
```

## 8. Internal testing → closed testing

1. **Testing → Internal testing → Create new release** → upload the `.aab` → release notes → **Save → Review → Start rollout**.
2. **Testers** tab → add the pilot testers' emails (up to 100) → copy the opt-in link and send it to them.
3. After the 2-week pilot: **Testing → Closed testing → Create track**, add your Google Group as testers, then
   **Promote release** from internal testing.

## 9. After the first upload (important)

1. **Setup → App integrity → App signing** → copy the **App signing key certificate SHA-256**.
2. Firebase console → Project settings → Your apps → TravelBuddy → **Add fingerprint** → paste it.
   (Your upload key SHA-256 is already there.)
3. Recommended: Google Cloud console → APIs & Services → Credentials → the "Android key (auto created by Firebase)" →
   **Application restrictions: Android apps** → add package `com.homilabs.travelbuddy` with the **SHA-1** fingerprints
   (upload key + Play signing key). Save.
