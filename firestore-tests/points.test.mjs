// Points-system test suite against the LOCAL emulators (auth + firestore + functions).
// Run:  ./scripts/test-points.sh
// It calls the real Cloud Functions code (functions/index.js) in the functions emulator with
// synthetic sign-in tokens, and checks the ledger, user totals and monthly doc after each event.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, collection, getDocs, query, where, Timestamp, deleteDoc } from 'firebase/firestore';

const PROJECT = 'travelbuddy-12d76';
const REGION = 'asia-south1';
const FN = `http://127.0.0.1:5101/${PROJECT}/${REGION}`;
let env;

// Unsigned JWT: the Auth emulator / Admin SDK accept these in emulator mode.
function token(uid, email) {
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  return `${b64({ alg: 'none', typ: 'JWT' })}.${b64({
    iss: `https://securetoken.google.com/${PROJECT}`, aud: PROJECT, sub: uid, user_id: uid, email,
    auth_time: now, iat: now, exp: now + 3600, firebase: { identities: {}, sign_in_provider: 'password' },
  })}.`;
}

async function call(uid, name, data = {}) {
  const r = await fetch(`${FN}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token(uid, `${uid}@x.test`)}` },
    body: JSON.stringify({ data }),
  });
  const j = await r.json();
  if (j.error) throw new Error(`${name}: ${j.error.status} ${j.error.message}`);
  return j.result ?? {};
}

// withSecurityRulesDisabled resolves to void, so capture the callback's result ourselves.
async function seed(fn) {
  let out;
  await env.withSecurityRulesDisabled(async (c) => { out = await fn(c.firestore()); });
  return out;
}

const user = (uid, extra = {}) => ({
  name: uid.toUpperCase(), email: `${uid}@x.test`, phone: '0300', employeeId: `E-${uid}`, department: uid === 'dan' ? 'Ops' : 'HSE',
  townshipLocation: 'A', hasCar: true, siteId: 'ffl', accountStatus: 'ACTIVE', role: uid === 'admin' ? 'ADMIN' : 'USER',
  points: 0, noShows: 0, ...extra,
});

const T = { TOWNSHIP: 'TOWNSHIP', PLANT: 'PLANT' };
let counter = 0;
async function post(uid, kind, { minutes = 30, windowId = 'morning', seats = 3, date = '2026-10-20' } = {}) {
  const id = `${kind.toLowerCase()}_${uid}_${++counter}`;
  await seed((f) => setDoc(doc(f, 'posts', id), {
    siteId: 'ffl', kind, userId: uid, userName: uid.toUpperCase(), userPhone: '0300', windowId, date, direction: 'TO_PLANT',
    departAt: Timestamp.fromMillis(Date.now() + minutes * 60000), fromPlaceId: 'e_type_end', toPlaceId: 'ccr_parking',
    seats: kind === 'OFFER' ? seats : 1, seatsLeft: kind === 'OFFER' ? seats : 1, status: 'OPEN', autoAccept: true, note: '',
    createdAt: Timestamp.now(), deleteAt: Timestamp.fromMillis(Date.now() + 30 * 864e5),
  }));
  return id;
}

async function points(uid) { return seed(async (f) => (await getDoc(doc(f, 'users', uid))).data().points ?? 0); }
async function ledger(uid) {
  return seed(async (f) => {
    const s = await getDocs(query(collection(f, 'points'), where('uid', '==', uid)));
    return s.docs.map((d) => d.data()).sort((a, b) => a.at.toMillis() - b.at.toMillis()).map((d) => `${d.reason}:${d.delta}`);
  });
}
async function ride(id) { return seed(async (f) => (await getDoc(doc(f, 'rides', id))).data()); }
async function postDoc(id) { return seed(async (f) => (await getDoc(doc(f, 'posts', id))).data()); }
async function monthly() { return seed(async (f) => (await getDoc(doc(f, 'monthly', `ffl_${new Date().toISOString().slice(0, 7)}`))).data()); }
async function userExists(uid) { return seed(async (f) => (await getDoc(doc(f, 'users', uid))).exists()); }

before(async () => {
  env = await initializeTestEnvironment({
    projectId: PROJECT,
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'), host: '127.0.0.1', port: 8185 },
  });
  await env.clearFirestore();
  await seed(async (f) => {
    for (const u of ['admin', 'dan', 'pam', 'eve', 'sam']) await setDoc(doc(f, 'users', u), user(u, u === 'sam' ? { hasCar: false } : {}));
  });
  await call('admin', 'createDefaultSite');
});
after(async () => env.cleanup());

test('lock: driver +2 once, each passenger +1; monthly nested totals', async () => {
  const offer = await post('dan', 'OFFER', { seats: 2 });
  const r1 = await call('pam', 'joinOffer', { offerPostId: offer, pickupPlaceId: 'e_type_end', dropPlaceId: 'ccr_parking' });
  assert.equal(r1.locked, true);
  const r2 = await call('eve', 'joinOffer', { offerPostId: offer, pickupPlaceId: 'e_mod_parking', dropPlaceId: 'ccr_parking' });
  assert.equal(r2.locked, true);
  assert.equal(r1.rideId, r2.rideId);
  assert.equal(await points('dan'), 2);
  assert.equal(await points('pam'), 1);
  assert.equal(await points('eve'), 1);
  assert.deepEqual(await ledger('dan'), ['RIDE_LOCKED:2']);
  const p = await postDoc(offer);
  assert.equal(p.status, 'FULL'); assert.equal(p.seatsLeft, 0);
  const m = await monthly();
  assert.equal(m.users.dan.driverLegs, 1); assert.equal(m.users.pam.passengerLegs, 1); assert.equal(m.totals.passengerLegs, 2);
  assert.ok(Math.abs(m.totals.kgSaved - 2 * 2.5 * 0.17) < 1e-6);
  globalThis.rideA = r1.rideId; globalThis.offerA = offer;
});

test('cap: one locked leg per window per person', async () => {
  const other = await post('sam', 'OFFER', { seats: 2 });
  // sam has no car flag but the server does not care; pam already rides in this window → refused
  await assert.rejects(call('pam', 'joinOffer', { offerPostId: other, pickupPlaceId: 'e_type_end', dropPlaceId: 'ccr_parking' }), /already have a ride/);
  // a 3rd seat on the FULL car is refused
  await assert.rejects(call('sam', 'joinOffer', { offerPostId: globalThis.offerA, pickupPlaceId: 'e_type_end', dropPlaceId: 'ccr_parking' }), /full/);
  // own offer
  await assert.rejects(call('dan', 'joinOffer', { offerPostId: globalThis.offerA }), /own offer/);
});

test('leave early with others remaining: −1 only, seat back, driver keeps +2', async () => {
  await call('eve', 'cancelRide', { rideId: globalThis.rideA });
  assert.equal(await points('eve'), 0);
  assert.equal(await points('dan'), 2);
  assert.deepEqual(await ledger('eve'), ['RIDE_LOCKED:1', 'LEFT_RIDE:-1']);
  const p = await postDoc(globalThis.offerA);
  assert.equal(p.seatsLeft, 1); assert.equal(p.status, 'OPEN');
  const r = await ride(globalThis.rideA);
  assert.equal(r.status, 'LOCKED'); assert.deepEqual(r.participantIds, ['dan', 'pam']);
});

test('complete: points stay; completed ride counts in monthly', async () => {
  await call('dan', 'markPickedUp', { rideId: globalThis.rideA, passengerUid: 'pam' });
  await call('dan', 'completeRide', { rideId: globalThis.rideA });
  assert.equal((await ride(globalThis.rideA)).status, 'COMPLETED');
  assert.equal(await points('dan'), 2); assert.equal(await points('pam'), 1);
  await assert.rejects(call('dan', 'completeRide', { rideId: globalThis.rideA }), /Already over/);
});

test('late cancel by driver: everyone loses ride points, driver −1 extra, requests reopen', async () => {
  const offer = await post('dan', 'OFFER', { minutes: 5, windowId: 'lunch_out', seats: 2 });
  const req = await post('pam', 'REQUEST', { minutes: 5, windowId: 'lunch_out' });
  const { rideId } = await call('dan', 'acceptRequest', { offerPostId: offer, requestPostId: req });
  assert.equal(await points('dan'), 4); assert.equal(await points('pam'), 2);
  const r = await call('dan', 'cancelRide', { rideId });
  assert.equal(r.late, true);
  assert.equal(await points('dan'), 1);   // 4 − 2 − 1
  assert.equal(await points('pam'), 1);   // 2 − 1
  assert.equal((await postDoc(req)).status, 'OPEN');
  assert.equal((await postDoc(offer)).status, 'CANCELLED');
  assert.ok((await ledger('dan')).includes('LATE_CANCEL:-1'));
});

test('late leave by passenger: −1 ride points −1 penalty; car empties → driver −2', async () => {
  const offer = await post('dan', 'OFFER', { minutes: 5, windowId: 'lunch_in', seats: 1 });
  const { rideId } = await call('pam', 'joinOffer', { offerPostId: offer, pickupPlaceId: 'e_type_end', dropPlaceId: 'ccr_parking' });
  const before = { dan: await points('dan'), pam: await points('pam') };
  await call('pam', 'cancelRide', { rideId });
  assert.equal(await points('pam'), before.pam - 1 - 1);
  assert.equal(await points('dan'), before.dan - 2);
  assert.equal((await ride(rideId)).status, 'CANCELLED');
  assert.equal((await postDoc(offer)).status, 'OPEN'); assert.equal((await postDoc(offer)).seatsLeft, 1);
});

test('no-show: passenger reported (−2 and ride +1 removed); dispute; admin upholds → unchanged; cancels → restored', async () => {
  const offer = await post('dan', 'OFFER', { minutes: -10, windowId: 'evening', seats: 2, date: '2026-10-21' });
  const { rideId } = await call('pam', 'joinOffer', { offerPostId: offer, pickupPlaceId: 'e_type_end', dropPlaceId: 'ccr_parking' });
  const before = await points('pam');
  await assert.rejects(call('eve', 'reportNoShow', { rideId, uid: 'pam' }), /Not allowed/);     // not in ride
  await call('dan', 'reportNoShow', { rideId, uid: 'pam' });
  assert.equal(await points('pam'), before - 2 - 1);
  await assert.rejects(call('dan', 'reportNoShow', { rideId, uid: 'pam' }), /Already reported/);
  await call('pam', 'disputeNoShow', { rideId });
  assert.equal((await ride(rideId)).hasOpenDispute, true);
  await assert.rejects(call('dan', 'resolveNoShow', { rideId, uid: 'pam', upheld: false }), /Admins only/);
  await call('admin', 'resolveNoShow', { rideId, uid: 'pam', upheld: true });
  assert.equal(await points('pam'), before - 3);
  await call('dan', 'completeRide', { rideId });   // v2.1: one active ride per person — free dan for the next one
  // a second report cannot be disputed twice; a cancelled report restores everything
  const offer2 = await post('dan', 'OFFER', { minutes: -10, windowId: 'morning', seats: 2, date: '2026-10-22' });
  const { rideId: ride2 } = await call('pam', 'joinOffer', { offerPostId: offer2, pickupPlaceId: 'e_type_end', dropPlaceId: 'ccr_parking' });
  const b2 = await points('pam');
  await call('dan', 'reportNoShow', { rideId: ride2, uid: 'pam' });
  await call('pam', 'disputeNoShow', { rideId: ride2 });
  await call('admin', 'resolveNoShow', { rideId: ride2, uid: 'pam', upheld: false });
  assert.equal(await points('pam'), b2);
  assert.equal((await ride(ride2)).hasOpenDispute, false);
  await call('dan', 'completeRide', { rideId: ride2 });
});

test('no-show: driver reported → ride NO_SHOW, driver −2 −2, passenger keeps +1', async () => {
  const offer = await post('eve', 'OFFER', { minutes: -10, windowId: 'lunch_out', seats: 2, date: '2026-10-22' });
  const { rideId } = await call('pam', 'joinOffer', { offerPostId: offer, pickupPlaceId: 'e_type_end', dropPlaceId: 'ccr_parking' });
  const before = { eve: await points('eve'), pam: await points('pam') };
  await assert.rejects(call('pam', 'reportNoShow', { rideId, uid: 'pam' }), /Not allowed/);          // self
  await call('pam', 'reportNoShow', { rideId, uid: 'eve' });
  assert.equal(await points('eve'), before.eve - 4);
  assert.equal(await points('pam'), before.pam);
  assert.equal((await ride(rideId)).status, 'NO_SHOW');
});

test('no-show report too early is refused', async () => {
  const offer = await post('dan', 'OFFER', { minutes: 20, windowId: 'lunch_in', seats: 2, date: '2026-10-23' });
  const { rideId } = await call('pam', 'joinOffer', { offerPostId: offer, pickupPlaceId: 'e_type_end', dropPlaceId: 'ccr_parking' });
  await assert.rejects(call('dan', 'reportNoShow', { rideId, uid: 'pam' }), /Wait until/);
  globalThis.rideB = rideId;
});

test('v2.1: one open post per person, none while a ride is active; arrived → auto-complete; reasons kept', async () => {
  // dan is driving rideB (LOCKED) → a new offer by dan is refused by the server (cancelled with a reason)
  const blocked = await post('dan', 'OFFER', { minutes: 30, date: '2026-10-23' });
  await new Promise((r) => setTimeout(r, 1500));
  assert.equal((await postDoc(blocked)).status, 'CANCELLED');
  assert.equal((await postDoc(blocked)).cancelReason, 'Already in a ride');
  // sam posts two requests: the older one is cancelled automatically
  const s1 = await post('sam', 'REQUEST', { minutes: 30, date: '2026-10-23' });
  await new Promise((r) => setTimeout(r, 800));
  const s2 = await post('sam', 'REQUEST', { minutes: 40, date: '2026-10-23' });
  await new Promise((r) => setTimeout(r, 1500));
  assert.equal((await postDoc(s1)).status, 'CANCELLED'); assert.equal((await postDoc(s1)).replacedBy, s2);
  assert.equal((await postDoc(s2)).status, 'OPEN');
  assert.ok(['lunch_in', 'other'].includes((await postDoc(s2)).windowId));
  // passenger arrives → the only passenger → ride completes by itself; completed counters updated
  const before = { dan: await points('dan'), pam: await points('pam') };
  const r = await call('pam', 'markArrived', { rideId: globalThis.rideB });
  assert.equal(r.completed, true);
  const rb = await ride(globalThis.rideB);
  assert.equal(rb.status, 'COMPLETED'); assert.equal(rb.completedBy, 'passengers'); assert.equal(rb.passengers.pam.arrived, true);
  assert.equal(await points('dan'), before.dan); assert.equal(await points('pam'), before.pam);
  const m = await monthly();
  assert.ok(m.users.pam.passengerRides >= 1); assert.ok(m.users.dan.driverRides >= 1);
  const danUser = await seed(async (f) => (await getDoc(doc(f, 'users', 'dan'))).data());
  assert.ok(danUser.stats.driverRides >= 1);
  // cancel with reason: stored on the ride and the offer; passenger told
  const offer = await post('dan', 'OFFER', { minutes: 30, date: '2026-10-23', seats: 2 });
  const { rideId } = await call('pam', 'joinOffer', { offerPostId: offer, pickupPlaceId: 'e_type_end', dropPlaceId: 'ccr_parking' });
  await call('dan', 'cancelRide', { rideId, reason: 'Car trouble' });
  assert.equal((await ride(rideId)).cancelReason, 'Car trouble');
  assert.equal((await postDoc(offer)).cancelReason, 'Car trouble');
  const n = await seed(async (f) => (await getDocs(collection(f, 'notifications/pam/items'))).docs.map((d) => d.data().body));
  assert.ok(n.some((b) => b.includes('Car trouble')));
  // test notification: no devices → 0
  assert.equal((await call('pam', 'sendTestNotification')).devices, 0);
  await call('sam', 'cancelPost', { postId: s2, reason: 'found a lift' });
  assert.equal((await postDoc(s2)).cancelReason, 'found a lift');
});

test('cancelPost: open post cancelled; a locked offer must cancel the ride instead', async () => {
  const req = await post('sam', 'REQUEST', { windowId: 'evening', date: '2026-10-23' });
  await call('sam', 'cancelPost', { postId: req });
  assert.equal((await postDoc(req)).status, 'CANCELLED');
  await assert.rejects(call('dan', 'cancelPost', { postId: globalThis.offerA }), /cancel the ride instead|Already closed/);
  await assert.rejects(call('pam', 'cancelPost', { postId: req }), /Not your post/);
});

test('blocked / pending users cannot act', async () => {
  await seed((f) => setDoc(doc(f, 'users', 'zed'), user('zed', { accountStatus: 'PENDING' })));
  const offer = await post('dan', 'OFFER', { windowId: 'morning', date: '2026-10-24' });
  await assert.rejects(call('zed', 'joinOffer', { offerPostId: offer }), /not approved/);
  await assert.rejects(call('nobody', 'joinOffer', { offerPostId: offer }), /Profile not found/);
});

test('account deletion cancels open posts and leaves rides (seat restored)', async () => {
  const offer = await post('dan', 'OFFER', { windowId: 'lunch_out', date: '2026-10-24', seats: 2 });
  const { rideId } = await call('eve', 'joinOffer', { offerPostId: offer, pickupPlaceId: 'e_type_end', dropPlaceId: 'ccr_parking' });
  await call('eve', 'deleteMyAccount');
  assert.equal(await userExists('eve'), false);
  const r = await ride(rideId);
  assert.deepEqual(r.participantIds, ['dan']);
  assert.equal((await postDoc(offer)).seatsLeft, 2);
});
