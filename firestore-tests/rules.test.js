// Security-rules tests for TravelBuddy v2 (firestore.rules). Run with scripts/test-rules.sh
import { test, before, after, beforeEach } from 'node:test';
import { readFileSync } from 'node:fs';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import {
  doc, getDoc, setDoc, updateDoc, deleteDoc, collection, query, where, getDocs, Timestamp, serverTimestamp,
} from 'firebase/firestore';

let env;
const ts = (minsFromNow) => Timestamp.fromMillis(Date.now() + minsFromNow * 60000);

const user = (uid, status = 'ACTIVE', role = 'USER') => ({
  name: uid.toUpperCase(), email: `${uid}@x.com`, phone: '03001234567', employeeId: `E-${uid}`,
  department: 'Ops', townshipLocation: 'Block A', hasCar: true, siteId: 'ffl', accountStatus: status, role,
});

const post = (uid, kind = 'OFFER', extra = {}) => ({
  siteId: 'ffl', kind, userId: uid, userName: uid, userPhone: '0300', windowId: 'morning', date: '2026-10-16',
  departAt: ts(60), fromPlaceId: 'e_type_end', toPlaceId: 'ccr_parking', seats: kind === 'OFFER' ? 3 : 1,
  seatsLeft: kind === 'OFFER' ? 3 : 1, status: 'OPEN', autoAccept: true, note: '', createdAt: serverTimestamp(),
  deleteAt: ts(60 * 24 * 30), ...extra,
});

const ride = (extra = {}) => ({
  siteId: 'ffl', driverId: 'dan', driverName: 'DAN', driverPhone: '0300', offerPostId: 'o1', windowId: 'morning',
  date: '2026-10-16', departAt: ts(60), fromPlaceId: 'e_type_end', toPlaceId: 'ccr_parking', status: 'LOCKED',
  passengers: { pam: { name: 'PAM', phone: '0300', pickupPlaceId: 'e_type_end', postId: 'r1', pickedUp: false } },
  participantIds: ['dan', 'pam'], reminded: false, hasOpenDispute: false, deleteAt: ts(60 * 24 * 30), ...extra,
});

const db = (uid) => (uid ? env.authenticatedContext(uid) : env.unauthenticatedContext()).firestore();
const seed = (fn) => env.withSecurityRulesDisabled(async (ctx) => fn(ctx.firestore()));

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'travelbuddy-rules-test',
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'), host: '127.0.0.1', port: 8185 },
  });
});
after(async () => env.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  await seed(async (f) => {
    await setDoc(doc(f, 'users/admin'), user('admin', 'ACTIVE', 'ADMIN'));
    await setDoc(doc(f, 'users/dan'), user('dan'));
    await setDoc(doc(f, 'users/pam'), user('pam'));
    await setDoc(doc(f, 'users/eve'), user('eve'));
    await setDoc(doc(f, 'users/newbie'), user('newbie', 'PENDING'));
    await setDoc(doc(f, 'users/bad'), user('bad', 'BLOCKED'));
    await setDoc(doc(f, 'sites/ffl'), { name: 'FFL', places: [], windows: [] });
    await setDoc(doc(f, 'posts/o1'), post('dan', 'OFFER'));
    await setDoc(doc(f, 'posts/r1'), post('pam', 'REQUEST'));
    await setDoc(doc(f, 'rides/x1'), ride());
    await setDoc(doc(f, 'points/p1'), { uid: 'pam', siteId: 'ffl', delta: 1, reason: 'RIDE_LOCKED', at: Timestamp.now() });
    await setDoc(doc(f, 'monthly/ffl_2026-10'), { users: {}, totals: {} });
    await setDoc(doc(f, 'notifications/pam/items/n1'), { title: 'Hi', body: 'x', read: false, at: Timestamp.now() });
  });
});

// ------------------------------------------------------------------ users
test('register: own PENDING/USER profile allowed; nothing else at create', async () => {
  const { accountStatus, role, ...rest } = user('fresh');
  await assertSucceeds(setDoc(doc(db('fresh'), 'users/fresh'), { ...rest, accountStatus: 'PENDING', role: 'USER', createdAt: serverTimestamp() }));
  await assertFails(setDoc(doc(db('fresh2'), 'users/fresh2'), user('fresh2', 'ACTIVE')));
  await assertFails(setDoc(doc(db('fresh3'), 'users/fresh3'), user('fresh3', 'PENDING', 'ADMIN')));
  await assertFails(setDoc(doc(db('fresh4'), 'users/fresh4'), { ...user('fresh4', 'PENDING'), points: 500 }));
  await assertFails(setDoc(doc(db('fresh5'), 'users/other'), user('other', 'PENDING')));
  await assertFails(setDoc(doc(db(null), 'users/x'), user('x', 'PENDING')));
});
test('users: self edits only profile fields; never status/role/points/noShows', async () => {
  await assertSucceeds(updateDoc(doc(db('pam'), 'users/pam'), { phone: '0311', hasCar: false, lastRole: 'passenger', fcmTokens: { tok: serverTimestamp() } }));
  await assertFails(updateDoc(doc(db('newbie'), 'users/newbie'), { accountStatus: 'ACTIVE' }));
  await assertFails(updateDoc(doc(db('dan'), 'users/dan'), { role: 'ADMIN' }));
  await assertFails(updateDoc(doc(db('dan'), 'users/dan'), { points: 999 }));
  await assertFails(updateDoc(doc(db('dan'), 'users/dan'), { noShows: 0 }));
  await assertFails(updateDoc(doc(db('dan'), 'users/dan'), { email: 'new@x.com' }));
  await assertFails(updateDoc(doc(db('dan'), 'users/dan'), { siteId: 'other' }));
});
test('users: read own; admin reads all and lists pending; others cannot', async () => {
  await assertSucceeds(getDoc(doc(db('newbie'), 'users/newbie')));
  await assertFails(getDoc(doc(db('dan'), 'users/pam')));
  await assertSucceeds(getDoc(doc(db('admin'), 'users/pam')));
  await assertSucceeds(getDocs(query(collection(db('admin'), 'users'), where('accountStatus', '==', 'PENDING'))));
  await assertFails(getDocs(query(collection(db('dan'), 'users'), where('accountStatus', '==', 'PENDING'))));
});
test('admin: approve/block with audit; cannot change role, points, or own status', async () => {
  const a = db('admin');
  await assertSucceeds(updateDoc(doc(a, 'users/newbie'), { accountStatus: 'ACTIVE', audit: [{ action: 'APPROVED', by: 'admin', byName: 'A', at: Timestamp.now(), reason: '' }], lastAdminActionAt: serverTimestamp() }));
  await assertSucceeds(updateDoc(doc(a, 'users/dan'), { accountStatus: 'BLOCKED' }));
  await assertFails(updateDoc(doc(a, 'users/pam'), { role: 'ADMIN' }));
  await assertFails(updateDoc(doc(a, 'users/pam'), { points: 100 }));
  await assertFails(updateDoc(doc(a, 'users/admin'), { accountStatus: 'BLOCKED' }));
  await assertFails(updateDoc(doc(a, 'users/pam'), { accountStatus: 'SUPER' }));
});
test('users: only the owner deletes their doc (account deletion)', async () => {
  await assertFails(deleteDoc(doc(db('admin'), 'users/pam')));
  await assertFails(deleteDoc(doc(db('dan'), 'users/pam')));
  await assertSucceeds(deleteDoc(doc(db('pam'), 'users/pam')));
});

// ------------------------------------------------------------------ sites
test('sites: active members read; only admin writes; pending/blocked cannot read', async () => {
  await assertSucceeds(getDoc(doc(db('dan'), 'sites/ffl')));
  await assertFails(getDoc(doc(db('newbie'), 'sites/ffl')));
  await assertFails(getDoc(doc(db('bad'), 'sites/ffl')));
  await assertFails(setDoc(doc(db('dan'), 'sites/ffl'), { name: 'x' }));
  await assertSucceeds(setDoc(doc(db('admin'), 'sites/ffl'), { name: 'FFL', places: [], windows: [] }));
});

// ------------------------------------------------------------------ posts
test('posts: board read only by ACTIVE members', async () => {
  const board = (f) => getDocs(query(collection(f, 'posts'), where('siteId', '==', 'ffl'), where('date', '==', '2026-10-16'), where('windowId', '==', 'morning'), where('status', '==', 'OPEN')));
  await assertSucceeds(board(db('pam')));
  await assertFails(board(db('newbie')));
  await assertFails(board(db('bad')));
  await assertFails(board(db(null)));
});
test('posts: valid offer and request can be created', async () => {
  await assertSucceeds(setDoc(doc(db('eve'), 'posts/n1'), post('eve', 'OFFER')));
  await assertSucceeds(setDoc(doc(db('eve'), 'posts/n2'), post('eve', 'REQUEST')));
});
test('posts: invalid creates are rejected', async () => {
  const e = db('eve');
  await assertFails(setDoc(doc(e, 'posts/x1'), post('dan')));                                   // as someone else
  await assertFails(setDoc(doc(e, 'posts/x2'), post('eve', 'OFFER', { status: 'FULL' })));
  await assertFails(setDoc(doc(e, 'posts/x3'), post('eve', 'OFFER', { seats: 9, seatsLeft: 9 })));
  await assertFails(setDoc(doc(e, 'posts/x4'), post('eve', 'OFFER', { seats: 3, seatsLeft: 1 })));
  await assertFails(setDoc(doc(e, 'posts/x5'), post('eve', 'REQUEST', { seats: 2, seatsLeft: 2 })));
  await assertFails(setDoc(doc(e, 'posts/x6'), post('eve', 'OFFER', { rideId: 'x1' })));
  await assertFails(setDoc(doc(e, 'posts/x7'), post('eve', 'OFFER', { siteId: 'other' })));
  await assertFails(setDoc(doc(e, 'posts/x8'), post('eve', 'OFFER', { deleteAt: '2026-11-01' })));
  await assertFails(setDoc(doc(db('newbie'), 'posts/x9'), post('newbie')));
});
test('posts: owner may only toggle autoAccept/note; status, seats, rideId are server-only', async () => {
  await assertSucceeds(updateDoc(doc(db('dan'), 'posts/o1'), { autoAccept: false, note: 'AC car' }));
  await assertFails(updateDoc(doc(db('dan'), 'posts/o1'), { status: 'CANCELLED' }));
  await assertFails(updateDoc(doc(db('dan'), 'posts/o1'), { seatsLeft: 0 }));
  await assertFails(updateDoc(doc(db('dan'), 'posts/o1'), { rideId: 'x1' }));
  await assertFails(updateDoc(doc(db('dan'), 'posts/o1'), { departAt: ts(5) }));
  await assertFails(updateDoc(doc(db('pam'), 'posts/o1'), { autoAccept: false }));          // not owner
  await assertFails(deleteDoc(doc(db('dan'), 'posts/o1')));
  await assertSucceeds(deleteDoc(doc(db('admin'), 'posts/o1')));
});

// ------------------------------------------------------------------ rides
test('rides: only participants (and admin) read; nobody writes from the client', async () => {
  await assertSucceeds(getDoc(doc(db('dan'), 'rides/x1')));
  await assertSucceeds(getDoc(doc(db('pam'), 'rides/x1')));
  await assertSucceeds(getDoc(doc(db('admin'), 'rides/x1')));
  await assertFails(getDoc(doc(db('eve'), 'rides/x1')));
  await assertFails(updateDoc(doc(db('dan'), 'rides/x1'), { status: 'COMPLETED' }));
  await assertFails(updateDoc(doc(db('pam'), 'rides/x1'), { 'passengers.pam.pickedUp': true }));
  await assertFails(setDoc(doc(db('dan'), 'rides/new'), ride()));
  await assertFails(deleteDoc(doc(db('admin'), 'rides/x1')));
  await assertSucceeds(getDocs(query(collection(db('pam'), 'rides'), where('participantIds', 'array-contains', 'pam'), where('status', 'in', ['LOCKED', 'PICKED_UP']))));
});
test('live positions: each participant writes only their own; participants read; outsiders never', async () => {
  const pos = { lat: 28.2, lng: 70.0, at: serverTimestamp(), deleteAt: ts(360) };
  await assertSucceeds(setDoc(doc(db('dan'), 'rides/x1/live/dan'), pos));
  await assertSucceeds(setDoc(doc(db('pam'), 'rides/x1/live/pam'), pos));
  await assertFails(setDoc(doc(db('pam'), 'rides/x1/live/dan'), pos));                      // someone else's doc
  await assertFails(setDoc(doc(db('eve'), 'rides/x1/live/eve'), pos));                      // not in ride
  await assertFails(setDoc(doc(db('dan'), 'rides/x1/live/dan'), { ...pos, speed: 1 }));     // extra field
  await assertSucceeds(getDoc(doc(db('pam'), 'rides/x1/live/dan')));
  await assertFails(getDoc(doc(db('eve'), 'rides/x1/live/dan')));
  await assertFails(getDoc(doc(db('admin'), 'rides/x1/live/dan')));                         // admin is not in the ride
  await assertSucceeds(deleteDoc(doc(db('dan'), 'rides/x1/live/dan')));
  await seed((f) => updateDoc(doc(f, 'rides/x1'), { status: 'COMPLETED' }));
  await assertFails(setDoc(doc(db('pam'), 'rides/x1/live/pam'), pos));                      // ride over
});

// ------------------------------------------------------------------ points, monthly, notifications
test('points: own ledger readable, admin reads all, never writable', async () => {
  await assertSucceeds(getDocs(query(collection(db('pam'), 'points'), where('uid', '==', 'pam'))));
  await assertFails(getDocs(query(collection(db('dan'), 'points'), where('uid', '==', 'pam'))));
  await assertSucceeds(getDoc(doc(db('admin'), 'points/p1')));
  await assertFails(setDoc(doc(db('pam'), 'points/p2'), { uid: 'pam', delta: 100 }));
  await assertFails(updateDoc(doc(db('pam'), 'points/p1'), { delta: 100 }));
});
test('monthly: readable by members, never writable', async () => {
  await assertSucceeds(getDoc(doc(db('pam'), 'monthly/ffl_2026-10')));
  await assertFails(getDoc(doc(db('newbie'), 'monthly/ffl_2026-10')));
  await assertFails(updateDoc(doc(db('admin'), 'monthly/ffl_2026-10'), { totals: { kgSaved: 9 } }));
});
test('notifications: own list read/mark-read/delete; no creating; nobody else reads', async () => {
  await assertSucceeds(getDoc(doc(db('pam'), 'notifications/pam/items/n1')));
  await assertSucceeds(updateDoc(doc(db('pam'), 'notifications/pam/items/n1'), { read: true }));
  await assertFails(updateDoc(doc(db('pam'), 'notifications/pam/items/n1'), { title: 'x' }));
  await assertFails(setDoc(doc(db('pam'), 'notifications/pam/items/n2'), { title: 'x', body: 'y' }));
  await assertFails(getDoc(doc(db('dan'), 'notifications/pam/items/n1')));
  await assertSucceeds(deleteDoc(doc(db('pam'), 'notifications/pam/items/n1')));
});
