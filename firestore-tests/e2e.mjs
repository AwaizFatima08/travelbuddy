// End-to-end helper for the LOCAL EMULATOR ONLY (never the real project).
// Plays the "other people" while the phone is driven by hand/adb.
//   node firestore-tests/e2e.mjs seed <lat> <lng>
//   node firestore-tests/e2e.mjs as <uid> <op> [args...]
// Security rules stay ON for every "as" call (mock auth tokens for that uid).
import { readFileSync } from 'node:fs';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import {
  doc, getDoc, setDoc, updateDoc, collection, query, where, getDocs, runTransaction,
  serverTimestamp, Timestamp, deleteDoc,
} from 'firebase/firestore';

const PROJECT = 'travelbuddy-12d76';
const FS_PORT = 8185;
const AUTH = 'http://127.0.0.1:9199';
// Emulator-only test password (not used anywhere real).
export const TEST_PASSWORD = 'emu-test-pass-1';

const env = await initializeTestEnvironment({
  projectId: PROJECT,
  firestore: { host: '127.0.0.1', port: FS_PORT, rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
});

const people = {
  u_admin: { name: 'Admin Tester', email: 'admin@tb.test', status: 'ACTIVE', role: 'ADMIN' },
  u_dan: { name: 'Dan Driver', email: 'dan@tb.test', status: 'ACTIVE', role: 'USER' },
  u_pam: { name: 'Pam Passenger', email: 'pam@tb.test', status: 'ACTIVE', role: 'USER' },
  u_newbie: { name: 'Nadia Newbie', email: 'nadia@tb.test', status: 'PENDING', role: 'USER' },
};

async function authAccount(localId, email) {
  const r = await fetch(`${AUTH}/identitytoolkit.googleapis.com/v1/projects/${PROJECT}/accounts`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer owner' },
    body: JSON.stringify({ localId, email, password: TEST_PASSWORD, emailVerified: true }),
  });
  if (!r.ok && !(await r.text()).includes('DUPLICATE')) throw new Error(`auth create failed ${localId}`);
}

function today() {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Karachi' }).format(new Date());
}
const deleteAt = () => Timestamp.fromDate(new Date(Date.now() + 30 * 864e5));
const fs = (uid) => env.authenticatedContext(uid).firestore();

const [cmd, ...args] = process.argv.slice(2);

if (cmd === 'seed') {
  const [lat, lng] = args.map(Number);
  for (const [uid, p] of Object.entries(people)) await authAccount(uid, p.email);
  await env.withSecurityRulesDisabled(async (ctx) => {
    const f = ctx.firestore();
    for (const [uid, p] of Object.entries(people)) {
      await setDoc(doc(f, 'users', uid), {
        name: p.name, email: p.email, phone: '03001234567', employeeId: `E-${uid}`, department: 'Production',
        townshipLocation: 'Block C', accountStatus: p.status, role: p.role,
      });
    }
    // Stops around the given point: one right there, one ~1.2 km, one ~3 km away.
    await setDoc(doc(f, 'settings/stops'), {
      stops: [
        { id: 'far', name: 'Plant Main Gate', lat: lat + 0.027, lng, active: true, order: 0 },
        { id: 'near', name: 'Township Mosque', lat, lng, active: true, order: 1 },
        { id: 'mid', name: 'Club Chowk', lat: lat + 0.011, lng, active: true, order: 2 },
      ],
    });
  });
  console.log('seeded; today =', today());
} else if (cmd === 'as') {
  const [uid, op, ...rest] = args;
  const f = fs(uid);
  const me = people[uid] ?? { name: uid };
  const out = (x) => console.log(JSON.stringify(x));
  switch (op) {
    case 'postOffer': { // slot direction time seats
      const [slot, direction, time, seats] = rest;
      const ref = doc(collection(f, 'rides'));
      await setDoc(ref, {
        type: 'OFFER', driverId: uid, driverName: me.name, driverPhone: '03001112223',
        posterId: uid, posterName: me.name, posterPhone: '03001112223',
        date: process.env.RIDE_DATE ?? today(), slot, direction, departTime: time, stopId: 'mid', stopName: 'Club Chowk', note: 'Test ride',
        totalSeats: Number(seats ?? 3), status: 'OPEN', requests: {}, participantIds: [uid],
        startedAt: null, completedAt: null, deleteAt: deleteAt(),
      });
      out({ rideId: ref.id }); break;
    }
    case 'postRequest': {
      const [slot, direction, time] = rest;
      const ref = doc(collection(f, 'rides'));
      await setDoc(ref, {
        type: 'REQUEST', driverId: '', driverName: '', driverPhone: '',
        posterId: uid, posterName: me.name, posterPhone: '03004445556',
        date: process.env.RIDE_DATE ?? today(), slot, direction, departTime: time, stopId: 'near', stopName: 'Township Mosque', note: '',
        totalSeats: 1, status: 'OPEN', requests: {}, participantIds: [uid],
        startedAt: null, completedAt: null, deleteAt: deleteAt(),
      });
      out({ rideId: ref.id }); break;
    }
    case 'ask': {
      const [rideId, stopId = 'near'] = rest;
      await updateDoc(doc(f, 'rides', rideId), { [`requests.${uid}`]: { name: me.name, phone: '03004445556', stopId, status: 'ASKED' } });
      out({ ok: true }); break;
    }
    case 'decide': { // rideId passengerUid accept|decline
      const [rideId, p, what] = rest;
      await runTransaction(f, async (tx) => {
        const r = (await tx.get(doc(f, 'rides', rideId))).data();
        const reqs = { ...r.requests, [p]: { ...r.requests[p], status: what === 'accept' ? 'ACCEPTED' : 'DECLINED' } };
        const acc = Object.entries(reqs).filter(([, v]) => v.status === 'ACCEPTED').map(([k]) => k);
        tx.update(doc(f, 'rides', rideId), {
          [`requests.${p}.status`]: reqs[p].status, participantIds: [r.driverId, ...acc],
          status: acc.length >= r.totalSeats ? 'FULL' : 'OPEN',
        });
      });
      out({ ok: true }); break;
    }
    case 'take': {
      const [rideId] = rest;
      const r = (await getDoc(doc(f, 'rides', rideId))).data();
      await updateDoc(doc(f, 'rides', rideId), {
        driverId: uid, driverName: me.name, driverPhone: '03001112223', participantIds: [r.posterId, uid], status: 'FULL',
      });
      out({ ok: true }); break;
    }
    case 'status': {
      const [rideId, status] = rest;
      const m = { status };
      if (status === 'STARTED') m.startedAt = serverTimestamp();
      if (status === 'COMPLETED') m.completedAt = serverTimestamp();
      await updateDoc(doc(f, 'rides', rideId), m);
      out({ ok: true }); break;
    }
    case 'loc': {
      const [rideId, lat, lng] = rest;
      await setDoc(doc(f, 'rides', rideId, 'live', 'loc'), {
        lat: Number(lat), lng: Number(lng), at: serverTimestamp(), deleteAt: Timestamp.fromDate(new Date(Date.now() + 864e5)),
      });
      out({ ok: true }); break;
    }
    case 'readLoc': {
      const [rideId] = rest;
      out((await getDoc(doc(f, 'rides', rideId, 'live', 'loc'))).data() ?? null); break;
    }
    case 'approve': case 'block': case 'unblock': {
      const [target, reason = ''] = rest;
      const action = { approve: 'APPROVED', block: 'BLOCKED', unblock: 'UNBLOCKED' }[op];
      const snap = await getDoc(doc(f, 'users', target));
      const audit = [...(snap.data().audit ?? []), { action, by: uid, byName: me.name, at: Timestamp.now(), reason }].slice(-20);
      await updateDoc(doc(f, 'users', target), {
        accountStatus: action === 'BLOCKED' ? 'BLOCKED' : 'ACTIVE', audit, lastAdminActionAt: serverTimestamp(),
      });
      out({ ok: true }); break;
    }
    default: throw new Error('unknown op ' + op);
  }
} else if (cmd === 'dump') {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const f = ctx.firestore();
    const what = args[0] ?? 'rides';
    const s = await getDocs(collection(f, what));
    s.forEach((d) => console.log(d.id, JSON.stringify(d.data())));
  });
} else if (cmd === 'findUser') {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const s = await getDocs(query(collection(ctx.firestore(), 'users'), where('email', '==', args[0])));
    s.forEach((d) => console.log(d.id, JSON.stringify(d.data())));
  });
}
process.exit(0);
