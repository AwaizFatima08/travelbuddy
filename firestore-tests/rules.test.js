// Security-rules tests for TravelBuddy. Run with:
//   firebase emulators:exec --only firestore "npm --prefix firestore-tests test"
import { test, before, after, beforeEach } from 'node:test';
import { readFileSync } from 'node:fs';
import {
  initializeTestEnvironment, assertSucceeds, assertFails,
} from '@firebase/rules-unit-testing';
import {
  doc, getDoc, setDoc, updateDoc, deleteDoc, collection, query, where, getDocs,
  deleteField, Timestamp, serverTimestamp,
} from 'firebase/firestore';

let env;
const deleteAt = Timestamp.fromDate(new Date(Date.now() + 30 * 864e5));

const user = (uid, status = 'ACTIVE', role = 'USER') => ({
  name: uid.toUpperCase(), email: `${uid}@x.com`, phone: '03001234567', employeeId: 'E1',
  department: 'Ops', townshipLocation: 'Block A', accountStatus: status, role,
});

const offer = (driver = 'dan', extra = {}) => ({
  type: 'OFFER', driverId: driver, driverName: 'Dan', driverPhone: '0300',
  posterId: driver, posterName: 'Dan', posterPhone: '0300',
  date: '2026-10-01', slot: 'MORNING', direction: 'TO_PLANT', departTime: '07:20',
  stopId: 's1', stopName: 'Gate 1', note: '', totalSeats: 3, status: 'OPEN',
  requests: {}, participantIds: [driver], startedAt: null, completedAt: null, deleteAt, ...extra,
});

const request = (poster = 'pam', extra = {}) => ({
  ...offer(poster, extra), type: 'REQUEST', driverId: '', driverName: '', driverPhone: '',
  posterName: 'Pam', totalSeats: 1, ...extra,
});

const db = (uid) => (uid ? env.authenticatedContext(uid) : env.unauthenticatedContext()).firestore();

async function seed(fn) {
  await env.withSecurityRulesDisabled(async (ctx) => fn(ctx.firestore()));
}

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
    await setDoc(doc(f, 'settings/stops'), { stops: [] });
    await setDoc(doc(f, 'rides/o1'), offer());
    await setDoc(doc(f, 'rides/r1'), request());
  });
});

// ------------------------------------------------------------------ users

test('register: own PENDING/USER doc allowed', async () => {
  const { accountStatus, role, ...rest } = user('fresh');
  await assertSucceeds(setDoc(doc(db('fresh'), 'users/fresh'), { ...rest, accountStatus: 'PENDING', role: 'USER' }));
});
test('register: cannot self-approve, self-admin, add audit, or create for someone else', async () => {
  await assertFails(setDoc(doc(db('fresh'), 'users/fresh'), user('fresh', 'ACTIVE')));
  await assertFails(setDoc(doc(db('fresh'), 'users/fresh'), user('fresh', 'PENDING', 'ADMIN')));
  await assertFails(setDoc(doc(db('fresh'), 'users/fresh'), { ...user('fresh', 'PENDING'), audit: [] }));
  await assertFails(setDoc(doc(db('fresh'), 'users/other'), user('other', 'PENDING')));
  await assertFails(setDoc(doc(db(null), 'users/x'), user('x', 'PENDING')));
});
test('users: self can edit profile fields but not status/role/audit', async () => {
  await assertSucceeds(updateDoc(doc(db('newbie'), 'users/newbie'), { phone: '03111111111' }));
  await assertFails(updateDoc(doc(db('newbie'), 'users/newbie'), { accountStatus: 'ACTIVE' }));
  await assertFails(updateDoc(doc(db('dan'), 'users/dan'), { role: 'ADMIN' }));
  await assertFails(updateDoc(doc(db('dan'), 'users/dan'), { audit: [] }));
  await assertFails(updateDoc(doc(db('dan'), 'users/dan'), { lastAdminActionAt: serverTimestamp() }));
  await assertFails(updateDoc(doc(db('dan'), 'users/dan'), { email: 'new@x.com' }));
});
test('users: read own doc only; admin reads all; nobody else lists users', async () => {
  await assertSucceeds(getDoc(doc(db('newbie'), 'users/newbie')));
  await assertFails(getDoc(doc(db('dan'), 'users/pam')));
  await assertSucceeds(getDoc(doc(db('admin'), 'users/pam')));
  await assertSucceeds(getDocs(query(collection(db('admin'), 'users'), where('accountStatus', '==', 'PENDING'))));
  await assertFails(getDocs(query(collection(db('dan'), 'users'), where('accountStatus', '==', 'PENDING'))));
});
test('admin: approve / block with audit allowed; cannot change role; cannot self-edit status', async () => {
  const a = db('admin');
  await assertSucceeds(updateDoc(doc(a, 'users/newbie'), {
    accountStatus: 'ACTIVE', audit: [{ action: 'APPROVED', by: 'admin', byName: 'A', at: Timestamp.now(), reason: '' }],
    lastAdminActionAt: serverTimestamp(),
  }));
  await assertSucceeds(updateDoc(doc(a, 'users/dan'), { accountStatus: 'BLOCKED' }));
  await assertFails(updateDoc(doc(a, 'users/pam'), { role: 'ADMIN' }));
  await assertFails(updateDoc(doc(a, 'users/admin'), { accountStatus: 'BLOCKED' }));
  await assertFails(updateDoc(doc(a, 'users/pam'), { accountStatus: 'SUPER' }));
});
test('users: nobody can delete a user doc', async () => {
  await assertFails(deleteDoc(doc(db('admin'), 'users/pam')));
  await assertFails(deleteDoc(doc(db('pam'), 'users/pam')));
});

// ------------------------------------------------------------------ settings

test('settings: active members read, only admin writes; pending/blocked cannot read', async () => {
  await assertSucceeds(getDoc(doc(db('dan'), 'settings/stops')));
  await assertFails(getDoc(doc(db('newbie'), 'settings/stops')));
  await assertFails(getDoc(doc(db('bad'), 'settings/stops')));
  await assertFails(setDoc(doc(db('dan'), 'settings/stops'), { stops: [] }));
  await assertSucceeds(setDoc(doc(db('admin'), 'settings/stops'), { stops: [{ id: 'a', name: 'A', lat: 1, lng: 2, active: true, order: 0 }] }));
});

// ------------------------------------------------------------------ rides: read / create

test('rides: only ACTIVE members can read', async () => {
  const board = (f) => getDocs(query(collection(f, 'rides'),
    where('date', '==', '2026-10-01'), where('slot', '==', 'MORNING'),
    where('direction', '==', 'TO_PLANT'), where('status', '==', 'OPEN')));
  await assertSucceeds(board(db('pam')));
  await assertFails(board(db('newbie')));
  await assertFails(board(db('bad')));
  await assertFails(board(db(null)));
});
test('rides: valid OFFER and REQUEST can be posted', async () => {
  await assertSucceeds(setDoc(doc(db('eve'), 'rides/n1'), offer('eve')));
  await assertSucceeds(setDoc(doc(db('eve'), 'rides/n2'), request('eve')));
});
test('rides: invalid posts are rejected', async () => {
  const e = db('eve');
  await assertFails(setDoc(doc(e, 'rides/x1'), offer('dan')));                               // posting as someone else
  await assertFails(setDoc(doc(e, 'rides/x2'), offer('eve', { status: 'FULL' })));
  await assertFails(setDoc(doc(e, 'rides/x3'), offer('eve', { totalSeats: 12 })));
  await assertFails(setDoc(doc(e, 'rides/x4'), offer('eve', { requests: { pam: { name: 'P', phone: '', stopId: '', status: 'ACCEPTED' } } })));
  await assertFails(setDoc(doc(e, 'rides/x5'), offer('eve', { participantIds: ['eve', 'pam'] })));
  await assertFails(setDoc(doc(e, 'rides/x6'), { ...request('eve'), driverId: 'dan' }));
  await assertFails(setDoc(doc(e, 'rides/x7'), offer('eve', { deleteAt: '2026-11-01' })));
  await assertFails(setDoc(doc(e, 'rides/x8'), offer('eve', { driverLoc: { lat: 1, lng: 1 } })));
  await assertFails(setDoc(doc(db('newbie'), 'rides/x9'), offer('newbie')));
});

// ------------------------------------------------------------------ rides: seat requests

const ask = (status = 'ASKED') => ({ 'requests.pam': { name: 'Pam', phone: '0300', stopId: 's1', status } });

test('seat: passenger can ask and withdraw an ASKED request', async () => {
  await assertSucceeds(updateDoc(doc(db('pam'), 'rides/o1'), ask()));
  await assertSucceeds(updateDoc(doc(db('pam'), 'rides/o1'), { 'requests.pam': deleteField() }));
});
test('seat: passenger can NOT accept their own request', async () => {
  await assertFails(updateDoc(doc(db('pam'), 'rides/o1'), ask('ACCEPTED')));
  await seed((f) => updateDoc(doc(f, 'rides/o1'), ask()));
  await assertFails(updateDoc(doc(db('pam'), 'rides/o1'), { 'requests.pam.status': 'ACCEPTED' }));
  await assertFails(updateDoc(doc(db('pam'), 'rides/o1'), { participantIds: ['dan', 'pam'] }));
});
test('seat: passenger cannot touch other requests or other fields', async () => {
  await seed((f) => updateDoc(doc(f, 'rides/o1'), { 'requests.eve': { name: 'E', phone: '', stopId: 's1', status: 'ASKED' } }));
  await assertFails(updateDoc(doc(db('pam'), 'rides/o1'), { 'requests.eve': deleteField() }));
  await assertFails(updateDoc(doc(db('pam'), 'rides/o1'), { ...ask(), note: 'hi' }));
  await assertFails(updateDoc(doc(db('pam'), 'rides/o1'), { 'requests.pam': { name: 'P', phone: '', stopId: '', status: 'ASKED', extra: 1 } }));
});
test('seat: cannot re-ask after decline, withdraw after accept, or ask on a FULL ride', async () => {
  await seed((f) => updateDoc(doc(f, 'rides/o1'), ask('DECLINED')));
  await assertFails(updateDoc(doc(db('pam'), 'rides/o1'), ask()));
  await seed((f) => updateDoc(doc(f, 'rides/o1'), { ...ask('ACCEPTED'), participantIds: ['dan', 'pam'] }));
  await assertFails(updateDoc(doc(db('pam'), 'rides/o1'), { 'requests.pam': deleteField() }));
  await seed((f) => updateDoc(doc(f, 'rides/o1'), { status: 'FULL', 'requests.pam': deleteField() }));
  await assertFails(updateDoc(doc(db('pam'), 'rides/o1'), ask()));
});
test('seat: driver cannot ask a seat in own ride', async () => {
  await assertFails(updateDoc(doc(db('dan'), 'rides/o1'), { 'requests.dan': { name: 'D', phone: '', stopId: '', status: 'ASKED' } }));
});
test('driver: can accept (requests + participantIds + status)', async () => {
  await seed((f) => updateDoc(doc(f, 'rides/o1'), ask()));
  await assertSucceeds(updateDoc(doc(db('dan'), 'rides/o1'), {
    'requests.pam.status': 'ACCEPTED', participantIds: ['dan', 'pam'], status: 'OPEN',
  }));
});
test('driver: ride details are frozen after posting', async () => {
  await assertFails(updateDoc(doc(db('dan'), 'rides/o1'), { date: '2026-10-02' }));
  await assertFails(updateDoc(doc(db('dan'), 'rides/o1'), { driverId: 'eve' }));
  await assertFails(updateDoc(doc(db('dan'), 'rides/o1'), { deleteAt: Timestamp.now() }));
  await assertFails(updateDoc(doc(db('dan'), 'rides/o1'), { status: 'BOGUS' }));
});
test('driver: start / complete; finished rides are locked', async () => {
  await assertSucceeds(updateDoc(doc(db('dan'), 'rides/o1'), { status: 'STARTED', startedAt: serverTimestamp() }));
  await assertSucceeds(updateDoc(doc(db('dan'), 'rides/o1'), { status: 'COMPLETED', completedAt: serverTimestamp() }));
  await assertFails(updateDoc(doc(db('dan'), 'rides/o1'), { status: 'OPEN' }));
});
test('non-participants cannot change a ride', async () => {
  await assertFails(updateDoc(doc(db('eve'), 'rides/o1'), { status: 'CANCELLED' }));
  await assertFails(updateDoc(doc(db('eve'), 'rides/r1'), { status: 'CANCELLED' }));
});

// ------------------------------------------------------------------ rides: take this passenger

const take = (uid = 'dan', extra = {}) => ({
  driverId: uid, driverName: 'Dan', driverPhone: '0300', participantIds: ['pam', uid], status: 'FULL', ...extra,
});

test('take: a member can take an open REQUEST', async () => {
  await assertSucceeds(updateDoc(doc(db('dan'), 'rides/r1'), take()));
});
test('take: cannot change ANY other field while taking', async () => {
  await assertFails(updateDoc(doc(db('dan'), 'rides/r1'), take('dan', { note: 'changed' })));
  await assertFails(updateDoc(doc(db('dan'), 'rides/r1'), take('dan', { date: '2026-10-05' })));
  await assertFails(updateDoc(doc(db('dan'), 'rides/r1'), take('dan', { stopId: 's9' })));
  await assertFails(updateDoc(doc(db('dan'), 'rides/r1'), take('dan', { participantIds: ['pam', 'dan', 'eve'] })));
  await assertFails(updateDoc(doc(db('dan'), 'rides/r1'), take('dan', { status: 'OPEN' })));
  await assertFails(updateDoc(doc(db('dan'), 'rides/r1'), take('eve')));                 // naming someone else
});
test('take: cannot take own request or an already-taken one', async () => {
  await assertFails(updateDoc(doc(db('pam'), 'rides/r1'), take('pam', { participantIds: ['pam', 'pam'] })));
  await seed((f) => updateDoc(doc(f, 'rides/r1'), take('eve', { participantIds: ['pam', 'eve'] })));
  await assertFails(updateDoc(doc(db('dan'), 'rides/r1'), take()));
});
test('take: after taking, ride details stay frozen; only status progress allowed', async () => {
  await seed((f) => updateDoc(doc(f, 'rides/r1'), take()));
  await assertFails(updateDoc(doc(db('dan'), 'rides/r1'), { note: 'x' }));
  await assertFails(updateDoc(doc(db('dan'), 'rides/r1'), { departTime: '09:00' }));
  await assertFails(updateDoc(doc(db('dan'), 'rides/r1'), { participantIds: ['dan'] }));
  await assertFails(updateDoc(doc(db('pam'), 'rides/r1'), { status: 'STARTED' }));       // passenger can't start
  await assertSucceeds(updateDoc(doc(db('dan'), 'rides/r1'), { status: 'STARTED', startedAt: serverTimestamp() }));
  await assertSucceeds(updateDoc(doc(db('pam'), 'rides/r1'), { status: 'CANCELLED' }));  // poster may cancel
});

// ------------------------------------------------------------------ live location

test('live loc: driver writes only while STARTED; only participants read', async () => {
  const loc = { lat: 31.5, lng: 74.3, at: serverTimestamp(), deleteAt };
  await seed((f) => updateDoc(doc(f, 'rides/o1'), { ...ask('ACCEPTED'), participantIds: ['dan', 'pam'] }));
  await assertFails(setDoc(doc(db('dan'), 'rides/o1/live/loc'), loc));                  // not started yet
  await seed((f) => updateDoc(doc(f, 'rides/o1'), { status: 'STARTED' }));
  await assertSucceeds(setDoc(doc(db('dan'), 'rides/o1/live/loc'), loc));
  await assertFails(setDoc(doc(db('dan'), 'rides/o1/live/other'), loc));
  await assertFails(setDoc(doc(db('dan'), 'rides/o1/live/loc'), { ...loc, extra: 1 }));
  await assertFails(setDoc(doc(db('pam'), 'rides/o1/live/loc'), loc));                  // passenger can't write
  await assertSucceeds(getDoc(doc(db('pam'), 'rides/o1/live/loc')));                    // accepted passenger reads
  await assertSucceeds(getDoc(doc(db('dan'), 'rides/o1/live/loc')));
  await assertFails(getDoc(doc(db('eve'), 'rides/o1/live/loc')));                       // other member can't
  await assertFails(getDoc(doc(db('admin'), 'rides/o1/live/loc')));
  await assertFails(deleteDoc(doc(db('pam'), 'rides/o1/live/loc')));
  await assertSucceeds(deleteDoc(doc(db('dan'), 'rides/o1/live/loc')));
});

// ------------------------------------------------------------------ delete

test('delete: poster deletes an untouched OPEN post; not once someone asked; others never', async () => {
  await assertFails(deleteDoc(doc(db('eve'), 'rides/o1')));
  await seed((f) => updateDoc(doc(f, 'rides/o1'), ask()));
  await assertFails(deleteDoc(doc(db('dan'), 'rides/o1')));
  await assertSucceeds(deleteDoc(doc(db('pam'), 'rides/r1')));
  await assertSucceeds(deleteDoc(doc(db('admin'), 'rides/o1')));
});
