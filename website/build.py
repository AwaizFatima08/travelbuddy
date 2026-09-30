#!/usr/bin/env python3
"""Builds the static TravelBuddy website pages (run from this folder: python3 build.py)."""
EMAIL = "homilabs.smc@gmail.com"
NAV = [("index.html", "Home"), ("privacy.html", "Privacy"), ("delete-account.html", "Delete account"), ("support.html", "Support")]
CUR = ' aria-current="page"'


def page(fname, title, desc, body):
    links = "".join(f'<a href="{h}"{CUR if h == fname else ""}>{t}</a>' for h, t in NAV)
    html = f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<meta name="description" content="{desc}">
<link rel="icon" href="favicon.png">
<link rel="apple-touch-icon" href="apple-touch-icon.png">
<link rel="stylesheet" href="style.css">
</head>
<body>
<header><div class="wrap"><img src="icon-512.png" alt=""><a class="brand" href="index.html">TravelBuddy</a><nav>{links}</nav></div></header>
<main class="wrap">
{body}
</main>
<footer><div class="wrap">TravelBuddy · a HomiLabs app · free volunteer carpool for the FFL community · <a href="mailto:{EMAIL}">{EMAIL}</a></div></footer>
</body>
</html>
'''
    open(fname, "w").write(html)


page("index.html", "TravelBuddy — Township ⇄ Plant carpool",
     "Free, volunteer carpool app for the FFL community: share rides between the Township and the Plant.", '''
<h1>TravelBuddy</h1>
<p><b>Township ⇄ Plant carpool for the FFL community.</b> Free, volunteer, no money involved.</p>
<img class="hero" src="banner.png" alt="TravelBuddy — Township to Plant carpool" width="1024" height="500">
<div class="cards">
  <div class="card"><h3>🚗 Offer seats</h3>Driving to the Plant or back? Post your seats for one of the four commute slots.</div>
  <div class="card"><h3>🙋 Ask for a seat</h3>Ask a driver for a seat, or post a request that any driver can take.</div>
  <div class="card"><h3>📍 Know when to leave</h3>During a started ride, passengers see how far away the driver is and get one alert at about 2 minutes.</div>
  <div class="card"><h3>🔒 Members only</h3>Every member is approved by the admin. Phone numbers are shared only with approved colleagues.</div>
</div>
<h2>Commute slots (Pakistan time)</h2>
<table>
<tr><th>Slot</th><th>Time</th></tr>
<tr><td>Morning</td><td>07:15 – 08:00</td></tr>
<tr><td>Lunch out</td><td>12:45 – 13:15</td></tr>
<tr><td>Lunch in</td><td>13:45 – 14:30</td></tr>
<tr><td>Evening</td><td>17:00 – 18:30</td></tr>
</table>
<h2>How to join</h2>
<ol>
  <li>Ask the TravelBuddy admin to add your Google account to the testers group.</li>
  <li>Install TravelBuddy from the Google Play link you receive.</li>
  <li>Register with your name, employee ID, department and phone number, then wait for approval.</li>
</ol>
<p class="note">TravelBuddy is a private arrangement between colleagues. It does not handle payments and is not a taxi or transport service.</p>
''')

page("delete-account.html", "Delete your TravelBuddy account", "How to delete your TravelBuddy account and data.", f'''
<h1>Delete your TravelBuddy account</h1>
<p>You can delete your account at any time. Deleting is permanent.</p>
<h2>In the app (fastest)</h2>
<ol>
  <li>Open TravelBuddy and go to <b>Settings</b>. (If your account is still waiting for approval or is blocked, the option is on that screen.)</li>
  <li>Tap <b>Delete my account</b>.</li>
  <li>Enter your password and tap <b>Delete forever</b>.</li>
</ol>
<h2>Without the app</h2>
<p>Email <a href="mailto:{EMAIL}?subject=TravelBuddy%20account%20deletion">{EMAIL}</a> from the email address you registered with,
with the subject “TravelBuddy account deletion”. The admin deletes the account within 30 days and replies to confirm.</p>
<h2>What is deleted</h2>
<table>
<tr><th>Data</th><th>When it is deleted</th></tr>
<tr><td>Your profile (name, email, phone, employee ID, department, township location) and your sign-in</td><td>Immediately</td></tr>
<tr><td>Your open ride posts</td><td>Cancelled or removed immediately</td></tr>
<tr><td>Past rides that show your name (ride history)</td><td>Automatically, 30 days after the ride date</td></tr>
<tr><td>Driver live location</td><td>Already removed when each ride ends (at most 24 hours)</td></tr>
</table>
<p class="muted">Nothing is kept after these periods. TravelBuddy keeps no backups of deleted accounts.</p>
''')

page("support.html", "TravelBuddy support", "Help and contact for TravelBuddy.", f'''
<h1>Support</h1>
<p>Questions, problems, or want to join? Email <a href="mailto:{EMAIL}">{EMAIL}</a>.</p>
<h2>Common questions</h2>
<p><b>My account says “Waiting for approval”.</b><br>The admin approves people they recognise. The screen updates by itself once you are approved.</p>
<p><b>I forgot my password.</b><br>On the login screen tap <i>Forgot password?</i>. Check your spam folder for the reset email.</p>
<p><b>I don't get the “driver is 2 minutes away” alert.</b><br>Tap <i>I'm waiting</i> on your ride, allow notifications, and set TravelBuddy to “Unrestricted” in your phone's battery settings (Settings → Battery optimisation settings in the app).</p>
<p><b>Why does the app want location?</b><br>To sort pickup stops nearest-first, and — for drivers only — to share their position with their confirmed passengers while a ride is started. TravelBuddy never uses location in the background.</p>
<p><b>How do I delete my account?</b><br>See <a href="delete-account.html">Delete your account</a>.</p>
''')

page("privacy.html", "TravelBuddy — Privacy Policy", "What TravelBuddy collects, why, and who can see it.", f'''
<h1>Privacy Policy</h1>
<p class="muted">Effective 30 September 2026 · App: TravelBuddy (com.homilabs.travelbuddy) · Publisher: HomiLabs</p>

<p>TravelBuddy is a free, volunteer carpool app that helps members of the FFL (Fatima Fertilizer) community share rides
between the Township and the Plant site. There are no payments, no ads and no tracking for marketing.
This page explains what the app collects, why, and who can see it.</p>

<h2>What we collect</h2>
<table>
<tr><th>Data</th><th>Why</th><th>Who can see it</th></tr>
<tr><td>Name, email, phone number, employee ID, department, township location (house/block)</td>
    <td>Create your account, let the admin recognise and approve you, and let members arrange rides and call each other.</td>
    <td>You and the app admins. Your name and phone number are also shown to approved members on rides you post or join.</td></tr>
<tr><td>Rides you post or join (date, slot, direction, pickup stop, seats, notes)</td>
    <td>Run the ride board and your ride history.</td>
    <td>Approved members.</td></tr>
<tr><td>Precise location of the <b>driver</b>, only while a ride is started</td>
    <td>Show the ride's passengers how far away the driver is and alert them when the driver is about 2 minutes away.</td>
    <td>Only that ride's driver and confirmed passengers. Sharing stops when the ride is completed or cancelled, or automatically after 45 minutes, with a visible notification the whole time.</td></tr>
<tr><td>Your approximate location, on your phone only</td>
    <td>Sort pickup stops nearest-first. Admins may also capture a stop's map point with their GPS.</td>
    <td>Not uploaded (except a stop's point saved by an admin).</td></tr>
<tr><td>Admin actions (approve / block / unblock, reason, time)</td>
    <td>Keep an audit trail of account decisions.</td>
    <td>Admins, and you (on your own account).</td></tr>
</table>
<p>TravelBuddy does <b>not</b> use background location, does not read your contacts, and does not store your password
(sign-in is handled by Google Firebase Authentication). Fingerprint/face unlock happens entirely on your phone; no
biometric data ever leaves it.</p>

<h2>Where data is stored</h2>
<p>Data is stored in Google Firebase (Cloud Firestore and Firebase Authentication), in the asia-south1 (Mumbai) region,
and is encrypted in transit (HTTPS/TLS). Google processes this data on our behalf under the
<a href="https://firebase.google.com/terms/data-processing-terms">Firebase data processing terms</a>.</p>

<h2>How long we keep it</h2>
<ul>
  <li>Rides and ride history are deleted automatically 30 days after the ride date.</li>
  <li>The driver's live location is deleted when the ride ends (and in any case within 24 hours).</li>
  <li>Your account details are kept while you are a member. You can delete your account at any time in the app
      (Settings → Delete my account) or by email — see <a href="delete-account.html">Delete your account</a>.</li>
</ul>

<h2>Sharing</h2>
<p>We do not sell or share your data with anyone outside the app, and we do not use it for advertising.
Data is only visible to other approved TravelBuddy members as described above.</p>

<h2>Your choices</h2>
<ul>
  <li>You can refuse the location permission; the app still works, but stops won't be sorted by distance and drivers
      can't share live location.</li>
  <li>You can turn notifications off in your phone settings.</li>
  <li>To correct your data, contact the admin (below). To delete it, see <a href="delete-account.html">Delete your account</a>.</li>
</ul>

<h2>Children</h2>
<p>TravelBuddy is for adult employees and community members only (18+).</p>

<h2>Contact</h2>
<p>HomiLabs — TravelBuddy admin: <a href="mailto:{EMAIL}">{EMAIL}</a></p>

<p class="muted">We will update this page if the app changes how it uses data; the effective date above will change too.</p>
''')
print("built")
