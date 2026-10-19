// TravelBuddy v2.1 server logic (Cloud Functions, asia-south1).
// Everything that must not be tampered with runs here: matching notifications, locking rides,
// points, no-shows, reminders, completion, monthly totals. See docs/DESIGN-v2.md (§16 for v2.1).
"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated, onDocumentWritten } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { setGlobalOptions } = require("firebase-functions/v2");
const admin = require("firebase-admin");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");

admin.initializeApp();
const db = getFirestore();

setGlobalOptions({ region: "asia-south1", maxInstances: 10, memory: "256MiB" });

// ---------------------------------------------------------------- rules (§8, §16)
const POINTS = { driverLock: 2, passengerLock: 1, lateCancel: -1, noShow: -2 };
const LATE_CANCEL_MIN = 10;
const BOOK_AHEAD_MAX_MIN = 60;      // leaving time may be at most this far ahead
const MATCH_WINDOW_MIN = 15;        // posts within ± this many minutes match
const DAILY_LEG_CAP = 4;
const REMINDER_LEAD_MIN = 10;       // slot reminder goes out this many minutes before the slot starts
const SITE_TZ_OFFSET_MIN = 300;     // Asia/Karachi, no DST

// ---------------------------------------------------------------- helpers

function requireAuth(req) {
  if (!req.auth) throw new HttpsError("unauthenticated", "Please sign in.");
  return req.auth.uid;
}

async function requireActive(uid) {
  const snap = await db.doc(`users/${uid}`).get();
  if (!snap.exists) throw new HttpsError("failed-precondition", "Profile not found.");
  const u = snap.data();
  if (u.accountStatus !== "ACTIVE") throw new HttpsError("permission-denied", "Your account is not approved yet.");
  return { uid, ...u };
}

async function requireAdmin(uid) {
  const u = await requireActive(uid);
  if (u.role !== "ADMIN") throw new HttpsError("permission-denied", "Admins only.");
  return u;
}

function localDate(d = new Date()) {
  return new Date(d.getTime() + SITE_TZ_OFFSET_MIN * 60000);   // wall clock as UTC fields
}
function dateKey(d = new Date()) {
  const l = localDate(d);
  return `${l.getUTCFullYear()}-${String(l.getUTCMonth() + 1).padStart(2, "0")}-${String(l.getUTCDate()).padStart(2, "0")}`;
}
function hhmm(date) {
  const l = localDate(date);
  return `${String(l.getUTCHours()).padStart(2, "0")}:${String(l.getUTCMinutes()).padStart(2, "0")}`;
}
function monthKey(date, siteId) {
  const l = localDate(date);
  const ym = `${l.getUTCFullYear()}-${String(l.getUTCMonth() + 1).padStart(2, "0")}`;
  return { ym, docId: `${siteId}_${ym}` };
}
function minutesUntil(ts) { return (ts.toMillis() - Date.now()) / 60000; }

/** Minutes since local midnight for "HH:mm". */
function hm(s) { const [h, m] = s.split(":").map(Number); return h * 60 + m; }

/** Which decided slot (window) a departure falls in, else "other" (shift / off-slot ride). */
function windowFor(site, departAt) {
  const l = localDate(departAt.toDate ? departAt.toDate() : departAt);
  const mins = l.getUTCHours() * 60 + l.getUTCMinutes();
  for (const w of site.windows || []) {
    if (!w.active) continue;
    if (mins >= hm(w.start) - MATCH_WINDOW_MIN && mins <= hm(w.end) + MATCH_WINDOW_MIN) return w.id;
  }
  return "other";
}

/** Adds a ledger line and updates the user's running total + the monthly doc — inside a transaction. */
function addPoints(tx, { uid, name, department, siteId, delta, reason, rideId, legs }) {
  const ledger = db.collection("points").doc();
  tx.set(ledger, {
    uid, siteId, delta, reason, rideId: rideId || null, at: FieldValue.serverTimestamp(),
    deleteAt: Timestamp.fromMillis(Date.now() + 400 * 86400000),
  });
  tx.set(db.doc(`users/${uid}`), { points: FieldValue.increment(delta) }, { merge: true });
  const { docId, ym } = monthKey(new Date(), siteId);
  const userUpd = { name: name || "", department: department || "", points: FieldValue.increment(delta) };
  const totals = {};
  if (legs) {
    for (const [k, v] of Object.entries(legs)) userUpd[k] = FieldValue.increment(v);
    if (legs.passengerLegs) totals.passengerLegs = FieldValue.increment(legs.passengerLegs);
    if (legs.driverLegs) totals.driverLegs = FieldValue.increment(legs.driverLegs);
    if (legs.kgSaved) totals.kgSaved = FieldValue.increment(legs.kgSaved);
  }
  tx.set(db.doc(`monthly/${docId}`), { siteId, month: ym, users: { [uid]: userUpd }, totals }, { merge: true });
}

/** In-app notification + push to all of a user's devices. Never throws. */
async function notify(uid, { title, body, rideId, postId, type }) {
  try {
    const item = db.collection("notifications").doc(uid).collection("items").doc();
    await item.set({
      title, body, type: type || "info", rideId: rideId || null, postId: postId || null,
      at: FieldValue.serverTimestamp(), read: false,
      deleteAt: Timestamp.fromMillis(Date.now() + 30 * 86400000),
    });
    const u = await db.doc(`users/${uid}`).get();
    const tokens = Object.keys((u.data() || {}).fcmTokens || {});
    if (!tokens.length) return;
    const res = await admin.messaging().sendEachForMulticast({
      tokens,
      notification: { title, body },
      data: { type: type || "info", rideId: rideId || "", postId: postId || "" },
      android: { priority: "high", notification: { channelId: "tb_alerts", sound: "default" } },
      webpush: { notification: { title, body, icon: "/app/icons/Icon-192.png" }, fcmOptions: { link: "/app/" } },
    });
    const dead = {};
    res.responses.forEach((r, i) => {
      const code = r.error && r.error.code;
      if (code === "messaging/registration-token-not-registered" || code === "messaging/invalid-argument") {
        dead[`fcmTokens.${tokens[i]}`] = FieldValue.delete();
      }
    });
    if (Object.keys(dead).length) await db.doc(`users/${uid}`).update(dead);
  } catch (e) {
    console.error("notify failed", uid, e.message);
  }
}

async function getSite(siteId) {
  const s = await db.doc(`sites/${siteId}`).get();
  if (!s.exists) throw new HttpsError("failed-precondition", "Site is not set up yet.");
  return { id: s.id, ...s.data() };
}

function placeName(site, id) {
  const p = (site.places || []).find((x) => x.id === id);
  return p ? p.name : id;
}

/** True when two places are the same or neighbours. */
function placesCompatible(site, a, b) {
  if (a === b) return true;
  const pa = (site.places || []).find((x) => x.id === a);
  const pb = (site.places || []).find((x) => x.id === b);
  if (!pa || !pb) return false;
  return (pa.neighbours || []).includes(b) || (pb.neighbours || []).includes(a);
}

/** Open posts of the other kind that match this post (§6.3, v2.1: by direction + time). */
async function findMatches(site, post) {
  const otherKind = post.kind === "OFFER" ? "REQUEST" : "OFFER";
  const tol = (site.matchMinutes || MATCH_WINDOW_MIN) * 60000;
  const snap = await db.collection("posts")
    .where("siteId", "==", post.siteId).where("direction", "==", post.direction)
    .where("status", "==", "OPEN").where("kind", "==", otherKind)
    .where("departAt", ">=", Timestamp.fromMillis(post.departAt.toMillis() - tol))
    .where("departAt", "<=", Timestamp.fromMillis(post.departAt.toMillis() + tol)).get();
  return snap.docs.map((d) => ({ id: d.id, ...d.data() })).filter((o) =>
    o.userId !== post.userId &&
    placesCompatible(site, o.fromPlaceId, post.fromPlaceId) &&
    placesCompatible(site, o.toPlaceId, post.toPlaceId) &&
    (otherKind !== "OFFER" || (o.seatsLeft || 0) > 0));
}

/** The user's current ride, if any. A ride where they were reported as a no-show no longer holds them. */
async function activeRideOf(uid) {
  const s = await db.collection("rides").where("participantIds", "array-contains", uid)
    .where("status", "in", ["LOCKED", "PICKED_UP"]).limit(3).get();
  const d = s.docs.find((x) => !(x.data().noShowReports || {})[uid]);
  return d ? { id: d.id, ...d.data() } : null;
}

// ---------------------------------------------------------------- triggers

/**
 * New offer/request:
 *  - refused (cancelled + explained) if the poster already has an active ride (§16)
 *  - the poster's other open posts are closed (one open post per person)
 *  - windowId is derived from the leaving time (for reminders/reports)
 *  - matching people on the other side are told (push + in-app)
 */
exports.onPostCreated = onDocumentCreated("posts/{postId}", async (event) => {
  const post = { id: event.params.postId, ...event.data.data() };
  if (post.status !== "OPEN") return;
  const site = await getSite(post.siteId);
  const windowId = windowFor(site, post.departAt);
  await event.data.ref.update({ windowId });

  if (post.joinOf) return; // implicit request created by joinOffer — driver is told by joinOffer itself

  // A ride that was already locked FROM this very post (someone joined before this trigger ran) is fine.
  const active = await activeRideOf(post.userId);
  const ownRide = active && (active.offerPostId === post.id || ((active.passengers || {})[post.userId] || {}).postId === post.id);
  if (active && !ownRide) {
    await event.data.ref.update({ status: "CANCELLED", cancelReason: "Already in a ride" });
    await notify(post.userId, { type: "info", rideId: active.id, title: "You already have a ride",
      body: "Finish or leave your current ride before posting again." });
    return;
  }
  const mine = await db.collection("posts").where("userId", "==", post.userId).where("status", "in", ["OPEN", "FULL"]).get();
  for (const d of mine.docs) {
    if (d.id !== post.id && !d.data().rideId) await d.ref.update({ status: "CANCELLED", replacedBy: post.id });
  }

  const matches = await findMatches(site, post);
  const from = placeName(site, post.fromPlaceId);
  const when = hhmm(post.departAt.toDate());
  const seen = new Set();
  for (const m of matches) {
    if (seen.has(m.userId)) continue;
    seen.add(m.userId);
    if (post.kind === "REQUEST") {
      await notify(m.userId, { type: "request", postId: post.id, title: `${post.userName} needs a ride`,
        body: `From ${from} at ${when}. Tap to accept.` });
    } else {
      await notify(m.userId, { type: "offer", postId: post.id, title: `${post.userName} is driving at ${when}`,
        body: `From ${from}, ${post.seatsLeft} seat(s). Tap to join.` });
    }
  }
});

/** Registration → tell admins. Approval / block → tell the user. */
exports.onUserWritten = onDocumentWritten("users/{uid}", async (event) => {
  const before = event.data.before.exists ? event.data.before.data() : null;
  const after = event.data.after.exists ? event.data.after.data() : null;
  if (!after) return;
  if (!before) {
    const admins = await db.collection("users").where("role", "==", "ADMIN").where("accountStatus", "==", "ACTIVE").get();
    for (const a of admins.docs) {
      await notify(a.id, { type: "admin", title: "New registration",
        body: `${after.name} (${after.employeeId}, ${after.department}) is waiting for approval.` });
    }
    return;
  }
  if (before.accountStatus !== after.accountStatus) {
    const msg = {
      ACTIVE: ["You're approved 🎉", "Welcome to TravelBuddy. Open the app to offer or find a ride."],
      BLOCKED: ["Account blocked", "Your TravelBuddy account was blocked by an admin."],
    }[after.accountStatus];
    if (msg) await notify(event.params.uid, { type: "account", title: msg[0], body: msg[1] });
  }
});

// ---------------------------------------------------------------- locking

async function lockInto(tx, { site, offer, request, offerRef, requestRef, pickupPlaceId, dropPlaceId }) {
  if (offer.status !== "OPEN" || (offer.seatsLeft || 0) < 1) throw new HttpsError("failed-precondition", "That car is full or no longer offered.");
  if (request.status !== "OPEN") throw new HttpsError("failed-precondition", "That request is no longer open.");
  if (offer.userId === request.userId) throw new HttpsError("failed-precondition", "You can't ride with yourself.");
  const passengerUid = request.userId;
  const today = dateKey();

  // No overlapping rides, and at most DAILY_LEG_CAP locked legs per day (reads first).
  for (const uid of [offer.userId, passengerUid]) {
    const active = await tx.get(db.collection("rides").where("participantIds", "array-contains", uid)
      .where("status", "in", ["LOCKED", "PICKED_UP"]).limit(3));
    const other = active.docs.find((d) => d.id !== (offer.rideId || "-") && !(d.data().noShowReports || {})[uid]);
    if (other && uid === passengerUid) throw new HttpsError("failed-precondition", "You already have a ride.");
    if (other && uid === offer.userId) throw new HttpsError("failed-precondition", "Driver already has another ride.");
    const todays = await tx.get(db.collection("rides").where("participantIds", "array-contains", uid)
      .where("date", "==", today).where("status", "in", ["LOCKED", "PICKED_UP", "COMPLETED"]).limit(DAILY_LEG_CAP + 1));
    const count = todays.docs.filter((d) => d.id !== (offer.rideId || "-")).length;
    if (count >= DAILY_LEG_CAP) throw new HttpsError("failed-precondition", `Daily limit of ${DAILY_LEG_CAP} rides reached.`);
  }

  const passenger = (await tx.get(db.doc(`users/${passengerUid}`))).data();
  const driver = (await tx.get(db.doc(`users/${offer.userId}`))).data();
  const rideRef = offer.rideId ? db.doc(`rides/${offer.rideId}`) : db.collection("rides").doc();
  let ride = offer.rideId ? (await tx.get(rideRef)).data() : null;
  const firstPassenger = !ride;
  if (!ride) {
    ride = {
      siteId: offer.siteId, driverId: offer.userId, driverName: offer.userName, driverPhone: offer.userPhone,
      offerPostId: offerRef.id, windowId: offer.windowId || windowFor(site, offer.departAt), direction: offer.direction,
      date: offer.date || dateKey(offer.departAt.toDate()), departAt: offer.departAt,
      fromPlaceId: offer.fromPlaceId, toPlaceId: offer.toPlaceId, status: "LOCKED", passengers: {},
      participantIds: [offer.userId], createdAt: FieldValue.serverTimestamp(), reminded: false,
      deleteAt: Timestamp.fromMillis(offer.departAt.toMillis() + 30 * 86400000), hasOpenDispute: false,
    };
  }
  ride.passengers[passengerUid] = {
    name: request.userName, phone: request.userPhone, pickupPlaceId: pickupPlaceId || request.fromPlaceId,
    dropPlaceId: dropPlaceId || request.toPlaceId, postId: requestRef.id, pickedUp: false, arrived: false,
  };
  ride.participantIds = Array.from(new Set([...ride.participantIds, passengerUid]));
  tx.set(rideRef, ride, { merge: true });

  const seatsLeft = (offer.seatsLeft || 0) - 1;
  tx.update(offerRef, { seatsLeft, status: seatsLeft <= 0 ? "FULL" : "OPEN", rideId: rideRef.id });
  tx.update(requestRef, { status: "CLOSED", rideId: rideRef.id });

  const kg = (site.legKm || 2.5) * (site.co2PerKm || 0.17);
  addPoints(tx, { uid: passengerUid, name: passenger.name, department: passenger.department, siteId: offer.siteId,
    delta: POINTS.passengerLock, reason: "RIDE_LOCKED", rideId: rideRef.id, legs: { passengerLegs: 1, kgSaved: kg } });
  if (firstPassenger) {
    addPoints(tx, { uid: offer.userId, name: driver.name, department: driver.department, siteId: offer.siteId,
      delta: POINTS.driverLock, reason: "RIDE_LOCKED", rideId: rideRef.id, legs: { driverLegs: 1 } });
  }
  return { rideId: rideRef.id, seatsLeft, passengerUid, driverUid: offer.userId };
}

/** Driver accepts a passenger's request into the driver's own offer. */
exports.acceptRequest = onCall(async (req) => {
  const uid = requireAuth(req);
  await requireActive(uid);
  const { offerPostId, requestPostId } = req.data || {};
  if (!offerPostId || !requestPostId) throw new HttpsError("invalid-argument", "Missing post ids.");
  const offerRef = db.doc(`posts/${offerPostId}`);
  const requestRef = db.doc(`posts/${requestPostId}`);
  const pre = await offerRef.get();
  if (!pre.exists) throw new HttpsError("not-found", "Offer not found.");
  const site = await getSite(pre.data().siteId);
  const result = await db.runTransaction(async (tx) => {
    const [o, r] = await Promise.all([tx.get(offerRef), tx.get(requestRef)]);
    if (!o.exists || !r.exists) throw new HttpsError("not-found", "Post not found.");
    const offer = o.data(), request = r.data();
    if (offer.userId !== uid || offer.kind !== "OFFER") throw new HttpsError("permission-denied", "Not your offer.");
    if (request.kind !== "REQUEST") throw new HttpsError("invalid-argument", "Not a request.");
    return lockInto(tx, { site, offer, request, offerRef, requestRef });
  });
  const ride = (await db.doc(`rides/${result.rideId}`).get()).data();
  await notify(result.passengerUid, { type: "locked", rideId: result.rideId, title: "Ride locked ✅",
    body: `${ride.driverName} will pick you up at ${placeName(site, ride.passengers[result.passengerUid].pickupPlaceId)} around ${hhmm(ride.departAt.toDate())}.` });
  return { rideId: result.rideId };
});

/** Passenger joins an offered car. Auto-accept → locked now; otherwise the driver is asked. */
exports.joinOffer = onCall(async (req) => {
  const uid = requireAuth(req);
  const me = await requireActive(uid);
  const { offerPostId, pickupPlaceId, dropPlaceId } = req.data || {};
  if (!offerPostId) throw new HttpsError("invalid-argument", "Missing offer id.");
  const offerRef = db.doc(`posts/${offerPostId}`);
  const o = await offerRef.get();
  if (!o.exists) throw new HttpsError("not-found", "Offer not found.");
  const offer = o.data();
  if (offer.userId === uid) throw new HttpsError("failed-precondition", "That's your own offer.");
  if (await activeRideOf(uid)) throw new HttpsError("failed-precondition", "You already have a ride.");
  const site = await getSite(offer.siteId);

  // Reuse my open request if I have one, else create an implicit one.
  const mine = await db.collection("posts").where("userId", "==", uid).where("status", "==", "OPEN").where("kind", "==", "REQUEST").limit(1).get();
  let requestRef;
  if (mine.empty) {
    requestRef = db.collection("posts").doc();
    await requestRef.set({
      siteId: offer.siteId, kind: "REQUEST", userId: uid, userName: me.name, userPhone: me.phone,
      direction: offer.direction, windowId: offer.windowId || "other", date: offer.date, departAt: offer.departAt,
      fromPlaceId: pickupPlaceId || offer.fromPlaceId, toPlaceId: dropPlaceId || offer.toPlaceId,
      seats: 1, seatsLeft: 1, status: "OPEN", autoAccept: true, note: "", createdAt: FieldValue.serverTimestamp(),
      deleteAt: Timestamp.fromMillis(offer.departAt.toMillis() + 30 * 86400000), joinOf: offerPostId,
    });
  } else {
    requestRef = mine.docs[0].ref;
  }

  if (!offer.autoAccept) {
    await notify(offer.userId, { type: "request", postId: requestRef.id, title: `${me.name} wants to join your ride`,
      body: `Pickup at ${placeName(site, pickupPlaceId || offer.fromPlaceId)}. Tap to accept.` });
    return { locked: false, requestPostId: requestRef.id };
  }

  const result = await db.runTransaction(async (tx) => {
    const [o2, r2] = await Promise.all([tx.get(offerRef), tx.get(requestRef)]);
    return lockInto(tx, { site, offer: o2.data(), request: r2.data(), offerRef, requestRef, pickupPlaceId, dropPlaceId });
  });
  const ride = (await db.doc(`rides/${result.rideId}`).get()).data();
  await notify(offer.userId, { type: "locked", rideId: result.rideId, title: `${me.name} joined your ride`,
    body: `Pickup at ${placeName(site, ride.passengers[uid].pickupPlaceId)}. ${result.seatsLeft} seat(s) left.` });
  return { locked: true, rideId: result.rideId };
});

// ---------------------------------------------------------------- cancelling

/** Cancel an open post (offer or request) that is not yet locked. No penalty. */
exports.cancelPost = onCall(async (req) => {
  const uid = requireAuth(req);
  const { postId, reason } = req.data || {};
  const ref = db.doc(`posts/${postId}`);
  await db.runTransaction(async (tx) => {
    const s = await tx.get(ref);
    if (!s.exists) throw new HttpsError("not-found", "Post not found.");
    const p = s.data();
    if (p.userId !== uid) throw new HttpsError("permission-denied", "Not your post.");
    if (p.rideId && p.kind === "OFFER") throw new HttpsError("failed-precondition", "Passengers are already locked in — cancel the ride instead.");
    if (p.status !== "OPEN" && p.status !== "FULL") throw new HttpsError("failed-precondition", "Already closed.");
    tx.update(ref, { status: "CANCELLED", cancelReason: (reason || "").toString().slice(0, 140) });
  });
  return {};
});

/** Cancel a locked ride (driver) or leave it (passenger), with an optional reason. Points per §8. */
exports.cancelRide = onCall(async (req) => {
  const uid = requireAuth(req);
  const me = await requireActive(uid);
  const { rideId } = req.data || {};
  const reason = ((req.data || {}).reason || "").toString().slice(0, 140);
  const ref = db.doc(`rides/${rideId}`);
  const out = await db.runTransaction(async (tx) => {
    const s = await tx.get(ref);
    if (!s.exists) throw new HttpsError("not-found", "Ride not found.");
    const ride = s.data();
    if (!["LOCKED", "PICKED_UP"].includes(ride.status)) throw new HttpsError("failed-precondition", "This ride is already over.");
    const isDriver = ride.driverId === uid;
    const isPassenger = !!ride.passengers[uid];
    if (!isDriver && !isPassenger) throw new HttpsError("permission-denied", "Not your ride.");
    const late = minutesUntil(ride.departAt) < LATE_CANCEL_MIN;
    const site = await getSite(ride.siteId);
    const kg = (site.legKm || 2.5) * (site.co2PerKm || 0.17);
    const offerRef = db.doc(`posts/${ride.offerPostId}`);
    const offer = (await tx.get(offerRef)).data();   // all reads before writes
    const notifyUids = [];

    if (isDriver) {
      addPoints(tx, { uid, name: me.name, department: me.department, siteId: ride.siteId, delta: -POINTS.driverLock,
        reason: "RIDE_CANCELLED", rideId, legs: { driverLegs: -1 } });
      if (late) addPoints(tx, { uid, name: me.name, department: me.department, siteId: ride.siteId, delta: POINTS.lateCancel, reason: "LATE_CANCEL", rideId });
      for (const [pUid, p] of Object.entries(ride.passengers)) {
        addPoints(tx, { uid: pUid, name: p.name, siteId: ride.siteId, delta: -POINTS.passengerLock, reason: "RIDE_CANCELLED_BY_DRIVER", rideId,
          legs: { passengerLegs: -1, kgSaved: -kg } });
        if (p.postId) tx.update(db.doc(`posts/${p.postId}`), { status: "OPEN", rideId: FieldValue.delete() });
        notifyUids.push(pUid);
      }
      tx.update(ref, { status: "CANCELLED", cancelledBy: uid, cancelReason: reason, cancelledAt: FieldValue.serverTimestamp() });
      if (offer) tx.update(offerRef, { status: "CANCELLED", cancelReason: reason });
    } else {
      const p = ride.passengers[uid];
      addPoints(tx, { uid, name: me.name, department: me.department, siteId: ride.siteId, delta: -POINTS.passengerLock,
        reason: "LEFT_RIDE", rideId, legs: { passengerLegs: -1, kgSaved: -kg } });
      if (late) addPoints(tx, { uid, name: me.name, department: me.department, siteId: ride.siteId, delta: POINTS.lateCancel, reason: "LATE_CANCEL", rideId });
      const passengers = { ...ride.passengers };
      delete passengers[uid];
      const participantIds = ride.participantIds.filter((x) => x !== uid);
      const noneLeft = Object.keys(passengers).length === 0;
      tx.update(ref, noneLeft
        ? { status: "CANCELLED", passengers, participantIds, cancelledBy: uid, cancelReason: reason, cancelledAt: FieldValue.serverTimestamp() }
        : { passengers, participantIds });
      if (p.postId) tx.update(db.doc(`posts/${p.postId}`), { status: "CANCELLED", cancelReason: reason });
      if (offer) tx.update(offerRef, { seatsLeft: (offer.seatsLeft || 0) + 1, status: "OPEN", ...(noneLeft ? { rideId: FieldValue.delete() } : {}) });
      if (noneLeft) addPoints(tx, { uid: ride.driverId, name: ride.driverName, siteId: ride.siteId, delta: -POINTS.driverLock, reason: "RIDE_EMPTIED", rideId, legs: { driverLegs: -1 } });
      notifyUids.push(ride.driverId);
    }
    return { ride, isDriver, notifyUids, late };
  });
  const why = reason ? ` Reason: “${reason}”` : "";
  for (const u of out.notifyUids) {
    await notify(u, { type: "cancelled", rideId,
      title: out.isDriver ? "Ride cancelled" : `${me.name} left the ride`,
      body: (out.isDriver ? `${me.name} cancelled the ${hhmm(out.ride.departAt.toDate())} ride. Your request is open again.` : "The seat is free again.") + why });
  }
  return { late: out.late };
});

// ---------------------------------------------------------------- pickup / arrival / completion (§16)

/** Pickup confirmed (by either side). Location sharing for that passenger ends. */
exports.markPickedUp = onCall(async (req) => {
  const uid = requireAuth(req);
  const { rideId, passengerUid } = req.data || {};
  const ref = db.doc(`rides/${rideId}`);
  await db.runTransaction(async (tx) => {
    const s = await tx.get(ref);
    if (!s.exists) throw new HttpsError("not-found", "Ride not found.");
    const ride = s.data();
    const target = ride.driverId === uid ? passengerUid : uid;
    if (!ride.passengers[target]) throw new HttpsError("permission-denied", "Not in this ride.");
    if (ride.driverId !== uid && uid !== target) throw new HttpsError("permission-denied", "Not your ride.");
    if (!["LOCKED", "PICKED_UP"].includes(ride.status)) throw new HttpsError("failed-precondition", "Already over.");
    tx.update(ref, { [`passengers.${target}.pickedUp`]: true, [`passengers.${target}.pickedUpAt`]: FieldValue.serverTimestamp(), status: "PICKED_UP" });
    tx.delete(db.doc(`rides/${rideId}/live/${target}`));
  });
  return {};
});

async function finishRide(tx, ref, ride, how) {
  tx.update(ref, { status: "COMPLETED", completedAt: FieldValue.serverTimestamp(), completedBy: how });
  tx.update(db.doc(`posts/${ride.offerPostId}`), { status: "CLOSED" });
  // Completed-ride counters for the dashboards (points are already granted at lock).
  const { docId } = monthKey(new Date(), ride.siteId);
  tx.set(db.doc(`users/${ride.driverId}`), { stats: { driverRides: FieldValue.increment(1) } }, { merge: true });
  tx.set(db.doc(`monthly/${docId}`), { users: { [ride.driverId]: { driverRides: FieldValue.increment(1) } }, totals: { completedRides: FieldValue.increment(1) } }, { merge: true });
  for (const pUid of Object.keys(ride.passengers || {})) {
    tx.set(db.doc(`users/${pUid}`), { stats: { passengerRides: FieldValue.increment(1) } }, { merge: true });
    tx.set(db.doc(`monthly/${docId}`), { users: { [pUid]: { passengerRides: FieldValue.increment(1) } } }, { merge: true });
  }
}

/** Passenger: "I've arrived". When every passenger has arrived the ride completes by itself. */
exports.markArrived = onCall(async (req) => {
  const uid = requireAuth(req);
  const { rideId } = req.data || {};
  const ref = db.doc(`rides/${rideId}`);
  const done = await db.runTransaction(async (tx) => {
    const s = await tx.get(ref);
    if (!s.exists) throw new HttpsError("not-found", "Ride not found.");
    const ride = s.data();
    if (!ride.passengers[uid]) throw new HttpsError("permission-denied", "Not a passenger of this ride.");
    if (!["LOCKED", "PICKED_UP"].includes(ride.status)) throw new HttpsError("failed-precondition", "Already over.");
    const passengers = { ...ride.passengers, [uid]: { ...ride.passengers[uid], pickedUp: true, arrived: true } };
    const all = Object.values(passengers).every((p) => p.arrived);
    tx.update(ref, { [`passengers.${uid}.pickedUp`]: true, [`passengers.${uid}.arrived`]: true, [`passengers.${uid}.arrivedAt`]: FieldValue.serverTimestamp() });
    tx.delete(db.doc(`rides/${rideId}/live/${uid}`));
    if (all) await finishRide(tx, ref, ride, "passengers");
    return { all, driverId: ride.driverId, name: ride.passengers[uid].name };
  });
  if (done.all) {
    const live = await db.collection(`rides/${rideId}/live`).get();
    await Promise.all(live.docs.map((d) => d.ref.delete()));
    await notify(done.driverId, { type: "completed", rideId, title: "Ride completed", body: `${done.name} has arrived — everyone is in. Thank you! 🌱` });
  }
  return { completed: done.all };
});

/** Driver closes the ride. */
exports.completeRide = onCall(async (req) => {
  const uid = requireAuth(req);
  const { rideId } = req.data || {};
  const ref = db.doc(`rides/${rideId}`);
  await db.runTransaction(async (tx) => {
    const s = await tx.get(ref);
    if (!s.exists) throw new HttpsError("not-found", "Ride not found.");
    const ride = s.data();
    if (ride.driverId !== uid) throw new HttpsError("permission-denied", "Only the driver completes a ride.");
    if (!["LOCKED", "PICKED_UP"].includes(ride.status)) throw new HttpsError("failed-precondition", "Already over.");
    await finishRide(tx, ref, ride, "driver");
  });
  const live = await db.collection(`rides/${rideId}/live`).get();
  await Promise.all(live.docs.map((d) => d.ref.delete()));
  return {};
});

// ---------------------------------------------------------------- no-shows

exports.reportNoShow = onCall(async (req) => {
  const uid = requireAuth(req);
  const me = await requireActive(uid);
  const { rideId, uid: target } = req.data || {};
  const ref = db.doc(`rides/${rideId}`);
  const out = await db.runTransaction(async (tx) => {
    const s = await tx.get(ref);
    if (!s.exists) throw new HttpsError("not-found", "Ride not found.");
    const ride = s.data();
    if (!ride.participantIds.includes(uid) || !ride.participantIds.includes(target) || uid === target) throw new HttpsError("permission-denied", "Not allowed.");
    if (minutesUntil(ride.departAt) > -5) throw new HttpsError("failed-precondition", "Wait until at least 5 minutes after the planned departure.");
    if (ride.noShowReports && ride.noShowReports[target]) throw new HttpsError("failed-precondition", "Already reported.");
    const targetIsDriver = ride.driverId === target;
    const t = (await tx.get(db.doc(`users/${target}`))).data();
    const site = await getSite(ride.siteId);
    const kg = (site.legKm || 2.5) * (site.co2PerKm || 0.17);
    addPoints(tx, { uid: target, name: t.name, department: t.department, siteId: ride.siteId, delta: POINTS.noShow, reason: "NO_SHOW", rideId });
    addPoints(tx, { uid: target, name: t.name, department: t.department, siteId: ride.siteId,
      delta: targetIsDriver ? -POINTS.driverLock : -POINTS.passengerLock, reason: "NO_SHOW_RIDE_POINTS", rideId,
      legs: targetIsDriver ? { driverLegs: -1 } : { passengerLegs: -1, kgSaved: -kg } });
    tx.update(db.doc(`users/${target}`), { noShows: FieldValue.increment(1) });
    tx.update(ref, {
      [`noShowReports.${target}`]: { by: uid, byName: me.name, at: Timestamp.now(), disputed: false, resolved: false, upheld: true },
      ...(targetIsDriver ? { status: "NO_SHOW" } : {}),
    });
    return { targetName: t.name };
  });
  await notify(target, { type: "noshow", rideId, title: "No-show reported",
    body: `${me.name} reported that you didn't turn up for the ride. −2 points. Open the ride to dispute within 24 h.` });
  return out;
});

exports.disputeNoShow = onCall(async (req) => {
  const uid = requireAuth(req);
  const { rideId } = req.data || {};
  const ref = db.doc(`rides/${rideId}`);
  await db.runTransaction(async (tx) => {
    const s = await tx.get(ref);
    const ride = s.data();
    const rep = ride && ride.noShowReports && ride.noShowReports[uid];
    if (!rep) throw new HttpsError("failed-precondition", "No report against you on this ride.");
    if (rep.disputed) throw new HttpsError("failed-precondition", "Already disputed.");
    if (Date.now() - rep.at.toMillis() > 24 * 3600000) throw new HttpsError("failed-precondition", "The 24-hour dispute window has passed.");
    tx.update(ref, { [`noShowReports.${uid}.disputed`]: true, [`noShowReports.${uid}.resolved`]: false, hasOpenDispute: true });
  });
  const admins = await db.collection("users").where("role", "==", "ADMIN").where("accountStatus", "==", "ACTIVE").get();
  for (const a of admins.docs) await notify(a.id, { type: "admin", rideId, title: "No-show dispute", body: "A member disputes a no-show report. Open Admin → Disputes." });
  return {};
});

exports.resolveNoShow = onCall(async (req) => {
  const uid = requireAuth(req);
  const adminUser = await requireAdmin(uid);
  const { rideId, uid: target, upheld } = req.data || {};
  const ref = db.doc(`rides/${rideId}`);
  await db.runTransaction(async (tx) => {
    const s = await tx.get(ref);
    const ride = s.data();
    const rep = ride && ride.noShowReports && ride.noShowReports[target];
    if (!rep) throw new HttpsError("not-found", "No such report.");
    if (!upheld && rep.upheld) {
      const targetIsDriver = ride.driverId === target;
      const site = await getSite(ride.siteId);
      const kg = (site.legKm || 2.5) * (site.co2PerKm || 0.17);
      const t = (await tx.get(db.doc(`users/${target}`))).data();
      addPoints(tx, { uid: target, name: t.name, department: t.department, siteId: ride.siteId, delta: -POINTS.noShow, reason: "NO_SHOW_REVERSED", rideId });
      addPoints(tx, { uid: target, name: t.name, department: t.department, siteId: ride.siteId,
        delta: targetIsDriver ? POINTS.driverLock : POINTS.passengerLock, reason: "NO_SHOW_REVERSED_RIDE_POINTS", rideId,
        legs: targetIsDriver ? { driverLegs: 1 } : { passengerLegs: 1, kgSaved: kg } });
      tx.update(db.doc(`users/${target}`), { noShows: FieldValue.increment(-1) });
    }
    const others = Object.entries(ride.noShowReports || {}).filter(([k, v]) => k !== target && v.disputed && !v.resolved);
    tx.update(ref, {
      [`noShowReports.${target}.resolved`]: true, [`noShowReports.${target}.upheld`]: !!upheld,
      [`noShowReports.${target}.resolvedBy`]: adminUser.name, hasOpenDispute: others.length > 0,
    });
  });
  await notify(target, { type: "noshow", rideId, title: upheld ? "No-show upheld" : "No-show cancelled", body: upheld ? "The admin upheld the report." : "The admin cancelled the report. Your points are restored." });
  return {};
});

// ---------------------------------------------------------------- notifications (§16)

/** "Send me a test notification" from Settings — proves permission + token + delivery on this device. */
exports.sendTestNotification = onCall(async (req) => {
  const uid = requireAuth(req);
  const u = (await db.doc(`users/${uid}`).get()).data() || {};
  const tokens = Object.keys(u.fcmTokens || {});
  await notify(uid, { type: "test", title: "TravelBuddy test", body: tokens.length ? "Notifications are working on this device 👍" : "No device registered yet — allow notifications in Settings." });
  return { devices: tokens.length };
});

// ---------------------------------------------------------------- admin

exports.createDefaultSite = onCall(async (req) => {
  const uid = requireAuth(req);
  await requireAdmin(uid);
  const ref = db.doc("sites/ffl");
  if ((await ref.get()).exists) throw new HttpsError("already-exists", "The FFL site already exists.");
  const T = "TOWNSHIP", P = "PLANT";
  const p = (id, name, side, order, neighbours = []) => ({ id, name, side, lat: 0, lng: 0, active: true, order, neighbours });
  const w = (id, name, from, to, start, end, order) => ({ id, name, from, to, start, end, active: true, order });
  await ref.set({
    name: "FFL Township ⇄ Plant", timezone: "Asia/Karachi", legKm: 2.5, co2PerKm: 0.17, matchMinutes: 15,
    places: [
      p("d_type_ground", "D-Type Play Ground", T, 0, ["e_type_end"]), p("e_type_end", "E-Type End", T, 1, ["e_mod_parking", "d_type_ground"]),
      p("e_mod_parking", "E-Modified Parking", T, 2, ["e_type_end"]), p("mosque_rbt", "Mosque Roundabout", T, 3, ["boq_parking"]),
      p("boq_parking", "BOQ Parking", T, 4, ["mosque_rbt"]),
      p("admin_bldg", "Admin Building", P, 10, ["ccr_parking"]), p("ccr_parking", "CCR Parking", P, 11, ["admin_bldg", "mcr_parking"]),
      p("mcr_parking", "MCR Parking", P, 12, ["ccr_parking"]), p("ldc", "L&DC", P, 13),
      p("workshop_parking", "Workshop Parking", P, 14, ["warehouse_parking"]), p("warehouse_parking", "Warehouse Parking", P, 15, ["workshop_parking"]),
      p("hse_bldg", "HSE Building", P, 16, ["laboratory"]), p("laboratory", "Laboratory", P, 17, ["hse_bldg"]),
    ],
    windows: [
      w("morning", "Morning", T, P, "07:00", "07:40", 0), w("lunch_out", "Lunch out", P, T, "12:45", "13:15", 1),
      w("lunch_in", "Lunch in", T, P, "14:00", "14:30", 2), w("evening", "Evening", P, T, "17:15", "18:00", 3),
    ],
  });
  return {};
});

/** Admin report for one month (on button press), including the per-user table for CSV export. */
exports.adminReport = onCall(async (req) => {
  const uid = requireAuth(req);
  await requireAdmin(uid);
  const { siteId, month } = req.data || {};
  const m = await db.doc(`monthly/${siteId}_${month}`).get();
  const data = m.data() || { users: {}, totals: {} };
  const [y, mo] = month.split("-").map(Number);
  const from = `${y}-${String(mo).padStart(2, "0")}-01`, to = `${y}-${String(mo).padStart(2, "0")}-31`;
  const rides = await db.collection("rides").where("siteId", "==", siteId).where("date", ">=", from).where("date", "<=", to).get();
  const byStatus = {}, byWindow = {}, byDirection = {};
  let seats = 0;
  rides.forEach((d) => {
    const r = d.data();
    byStatus[r.status] = (byStatus[r.status] || 0) + 1;
    if (r.status === "COMPLETED" || r.status === "PICKED_UP") {
      byWindow[r.windowId || "other"] = (byWindow[r.windowId || "other"] || 0) + 1;
      byDirection[r.direction || "?"] = (byDirection[r.direction || "?"] || 0) + 1;
      seats += Object.keys(r.passengers || {}).length;
    }
  });
  const byDept = {};
  for (const u of Object.values(data.users || {})) {
    const d = u.department || "—";
    byDept[d] = byDept[d] || { points: 0, legs: 0, kgSaved: 0 };
    byDept[d].points += u.points || 0;
    byDept[d].legs += (u.driverLegs || 0) + (u.passengerLegs || 0);
    byDept[d].kgSaved += u.kgSaved || 0;
  }
  const members = {};
  for (const st of ["ACTIVE", "PENDING", "BLOCKED"]) {
    members[st] = (await db.collection("users").where("accountStatus", "==", st).count().get()).data().count;
  }
  return { month, totals: data.totals || {}, byStatus, byWindow, byDirection, byDept, seats, rides: rides.size, members, users: data.users || {} };
});

/** Account deletion (Play requirement): cancel open posts/rides, delete profile + notifications. */
exports.deleteMyAccount = onCall(async (req) => {
  const uid = requireAuth(req);
  const posts = await db.collection("posts").where("userId", "==", uid).where("status", "in", ["OPEN", "FULL"]).get();
  for (const d of posts.docs) await d.ref.update({ status: "CANCELLED" });
  const rides = await db.collection("rides").where("participantIds", "array-contains", uid).where("status", "in", ["LOCKED", "PICKED_UP"]).get();
  for (const d of rides.docs) {
    const r = d.data();
    if (r.driverId === uid) await d.ref.update({ status: "CANCELLED", cancelledBy: uid });
    else {
      const passengers = { ...r.passengers }; delete passengers[uid];
      await d.ref.update({ passengers, participantIds: r.participantIds.filter((x) => x !== uid) });
      if (r.offerPostId) await db.doc(`posts/${r.offerPostId}`).update({ seatsLeft: FieldValue.increment(1), status: "OPEN" }).catch(() => {});
    }
  }
  const items = await db.collection(`notifications/${uid}/items`).get();
  await Promise.all(items.docs.map((d) => d.ref.delete()));
  await db.doc(`notifications/${uid}`).delete().catch(() => {});
  await db.doc(`users/${uid}`).delete();
  return {};
});

// ---------------------------------------------------------------- scheduled

/**
 * Every 5 min:
 *  - ride reminders 10 min before departure
 *  - per-slot commute reminders (Mon–Fri, 10 min before a slot, users who switched that slot on, no active ride)
 *  - close stale posts; auto-complete old rides (safety net)
 */
exports.tick = onSchedule({ schedule: "every 5 minutes", timeZone: "Asia/Karachi" }, async () => {
  const now = Date.now();

  // Ride reminders.
  const soon = await db.collection("rides").where("status", "==", "LOCKED").where("reminded", "==", false)
    .where("departAt", "<=", Timestamp.fromMillis(now + 15 * 60000)).where("departAt", ">=", Timestamp.fromMillis(now - 5 * 60000)).get();
  for (const d of soon.docs) {
    const r = d.data();
    await d.ref.update({ reminded: true });
    for (const u of r.participantIds) {
      await notify(u, { type: "reminder", rideId: d.id, title: "Ride in ~10 minutes",
        body: u === r.driverId ? `Pick up ${Object.values(r.passengers).map((p) => p.name).join(", ")} at ${hhmm(r.departAt.toDate())}.` : `${r.driverName} picks you up at ${hhmm(r.departAt.toDate())}. Tap to share your position.` });
    }
  }

  // Slot reminders (§16): weekdays only, once per slot per day, for users who opted in.
  const l = localDate(new Date(now));
  const weekday = l.getUTCDay();                        // 0 Sun … 6 Sat
  if (weekday >= 1 && weekday <= 5) {
    const mins = l.getUTCHours() * 60 + l.getUTCMinutes();
    const today = dateKey(new Date(now));
    const sites = await db.collection("sites").get();
    for (const s of sites.docs) {
      for (const w of (s.data().windows || [])) {
        if (!w.active) continue;
        const target = hm(w.start) - REMINDER_LEAD_MIN;
        if (mins < target || mins >= target + 5) continue;   // this 5-minute tick owns the slot
        const marker = db.doc(`reminders/${s.id}_${today}_${w.id}`);
        if ((await marker.get()).exists) continue;
        await marker.set({ at: FieldValue.serverTimestamp(), deleteAt: Timestamp.fromMillis(now + 7 * 86400000) });
        const users = await db.collection("users").where("siteId", "==", s.id).where("accountStatus", "==", "ACTIVE")
          .where(`reminders.${w.id}`, "==", true).get();
        for (const u of users.docs) {
          if (await activeRideOf(u.id)) continue;
          await notify(u.id, { type: "slot", title: `${w.name} commute at ${w.start}`,
            body: `${w.from === "TOWNSHIP" ? "Township → Plant" : "Plant → Township"}. Offer seats or find a ride now.` });
        }
      }
    }
  }

  // Close open posts 45 min after their departure time.
  const stale = await db.collection("posts").where("status", "in", ["OPEN", "FULL"]).where("departAt", "<=", Timestamp.fromMillis(now - 45 * 60000)).limit(200).get();
  for (const d of stale.docs) await d.ref.update({ status: "CLOSED" });

  // Safety net: complete rides 90 min after departure (points stay). Clear live positions.
  const old = await db.collection("rides").where("status", "in", ["LOCKED", "PICKED_UP"]).where("departAt", "<=", Timestamp.fromMillis(now - 90 * 60000)).limit(100).get();
  for (const d of old.docs) {
    const r = d.data();
    await db.runTransaction(async (tx) => {
      const cur = (await tx.get(d.ref)).data();
      if (!["LOCKED", "PICKED_UP"].includes(cur.status)) return;
      await finishRide(tx, d.ref, cur, "auto");
    });
    const live = await d.ref.collection("live").get();
    await Promise.all(live.docs.map((x) => x.ref.delete()));
    void r;
  }
});
