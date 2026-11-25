// All Firestore and Auth access. Each method mirrors the Android app's repository function of the
// same purpose (RideRepository.kt, AuthRepository.kt, UserRepository.kt, AdminRepository.kt), so a
// ride started on the phone can be finished on the web and the other way round.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'models.dart';

class Repo {
  Repo._();
  static final Repo I = Repo._();

  final FirebaseAuth auth = FirebaseAuth.instance;
  final FirebaseFirestore db = FirebaseFirestore.instance;

  /// True while a registration is writing the profile (so the gate shows a spinner, not the profile form).
  final registering = ValueNotifierLite(false);

  CollectionReference<Map<String, dynamic>> get _users => db.collection('users');
  CollectionReference<Map<String, dynamic>> get _rides => db.collection('rides');
  CollectionReference<Map<String, dynamic>> get _needs => db.collection('passengerNeeds');
  CollectionReference<Map<String, dynamic>> get _reqs => db.collection('rideRequests');
  CollectionReference<Map<String, dynamic>> get _locks => db.collection('activePassengerRides');
  CollectionReference<Map<String, dynamic>> get _config => db.collection('systemConfig');

  // ------------------------------------------------------------------ auth
  Stream<User?> authChanges() => auth.authStateChanges();
  User? get currentUser => auth.currentUser;
  String get uid => auth.currentUser?.uid ?? '';

  Stream<AppUser?> userStream(String uid) => _users.doc(uid).snapshots().map(AppUser.fromDoc);

  /// Email login (AuthRepository.login). A sign-in with no profile document gets a recovered pending one.
  Future<void> signIn(String email, String password) async {
    final e = email.trim();
    if (!e.contains('@')) throw 'Please enter your complete email address.';
    final cred = await auth.signInWithEmailAndPassword(email: e, password: password);
    final u = cred.user!;
    final doc = await _users.doc(u.uid).get();
    if (!doc.exists) {
      final name = (u.displayName ?? '').trim().isNotEmpty
          ? u.displayName!.trim()
          : e.split('@').first.replaceAll('.', ' ').split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
      final fresh = AppUser.fresh(uid: u.uid, name: name, email: e, employeeId: '', department: 'Administration', townshipLocation: 'EMs', mode: AppUser.modePassenger, defaultSeats: 3);
      await _users.doc(u.uid).set(fresh.toMap());
    } else {
      final me = AppUser.fromDoc(doc)!;
      if (me.isBlocked || me.isRemoved) {
        await auth.signOut();
        throw 'Your account is currently restricted. Please contact the administrator.';
      }
    }
  }

  /// AuthRepository.register: Auth user → employee-ID uniqueness → users + employeeRegistry batch.
  Future<void> register({
    required String name,
    required String email,
    required String password,
    required String employeeId,
    required String department,
    required String townshipLocation,
    required String mode,
    required int defaultSeats,
  }) async {
    if (name.trim().isEmpty) throw 'Please enter your full name.';
    if (!email.contains('@') || !email.contains('.')) throw 'Please enter a valid email address.';
    if (password.length < 6) throw 'Password must be at least 6 characters long.';
    final empNorm = employeeId.trim().replaceAll(' ', '').toUpperCase();
    registering.value = true;
    try {
      final cred = await auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
      final u = cred.user!;
      if (empNorm.isNotEmpty) {
        final reg = await db.collection('employeeRegistry').doc(empNorm).get();
        if (reg.exists && reg.data()?['uid'] != u.uid) {
          try { await u.delete(); } catch (_) {}
          await auth.signOut();
          throw 'This Employee ID is already registered to another account.';
        }
      }
      final fresh = AppUser.fresh(uid: u.uid, name: name, email: email, employeeId: employeeId, department: department, townshipLocation: townshipLocation, mode: mode, defaultSeats: defaultSeats);
      try {
        final b = db.batch();
        b.set(_users.doc(u.uid), fresh.toMap());
        if (empNorm.isNotEmpty) b.set(db.collection('employeeRegistry').doc(empNorm), {'uid': u.uid, 'createdAt': fresh.createdAt});
        await b.commit();
      } catch (e) {
        try { await u.delete(); } catch (_) {}
        await auth.signOut();
        rethrow;
      }
    } finally {
      registering.value = false;
    }
  }

  /// Google sign-in in a popup. Returns true when a profile already exists (else Complete Profile is needed).
  Future<bool> signInWithGoogle() async {
    final cred = await auth.signInWithPopup(GoogleAuthProvider());
    final u = cred.user!;
    final doc = await _users.doc(u.uid).get();
    if (!doc.exists) return false;
    final me = AppUser.fromDoc(doc)!;
    if (me.isBlocked || me.isRemoved) {
      await auth.signOut();
      throw 'Your account is currently restricted. Please contact the administrator.';
    }
    return true;
  }

  /// AuthRepository.completeGoogleProfile.
  Future<void> completeProfile({
    required String employeeId,
    required String department,
    required String townshipLocation,
    required String mode,
    required int defaultSeats,
    required String phone,
  }) async {
    final u = auth.currentUser;
    if (u == null) throw 'No signed-in user.';
    final empNorm = employeeId.trim().replaceAll(' ', '').toUpperCase();
    registering.value = true;
    try {
      if (empNorm.isNotEmpty) {
        final reg = await db.collection('employeeRegistry').doc(empNorm).get();
        if (reg.exists && reg.data()?['uid'] != u.uid) throw 'This Employee ID is already registered.';
      }
      final name = (u.displayName ?? '').trim().isEmpty ? 'Employee' : u.displayName!.trim();
      final fresh = AppUser.fresh(uid: u.uid, name: name, email: u.email ?? '', employeeId: employeeId, department: department, townshipLocation: townshipLocation, mode: mode, defaultSeats: defaultSeats, phone: phone);
      final b = db.batch();
      b.set(_users.doc(u.uid), fresh.toMap());
      if (empNorm.isNotEmpty) b.set(db.collection('employeeRegistry').doc(empNorm), {'uid': u.uid, 'createdAt': fresh.createdAt});
      await b.commit();
    } finally {
      registering.value = false;
    }
  }

  Future<void> resetPassword(String email) => auth.sendPasswordResetEmail(email: email.trim());

  Future<void> changePassword(String newPassword) async {
    final u = auth.currentUser;
    if (u == null) throw 'Not signed in.';
    await u.updatePassword(newPassword);
    await _users.doc(u.uid).update({'isPasswordChanged': true});
  }

  Future<void> signOut() => auth.signOut();

  /// systemConfig/appApproval → sustainability fallback (AuthRepository.getApproverInfo).
  Future<(String, String)> approverInfo() async {
    try {
      final a = await _config.doc('appApproval').get();
      final d = a.data();
      if (d != null) {
        final n = str(d, ['approverDisplayName', 'name']);
        if (n.isNotEmpty) return (n, str(d, ['approverEmail', 'email']));
      }
      final s = await _config.doc('sustainability').get();
      final sd = s.data() ?? {};
      return (str(sd, ['approverDisplayName'], fallback: 'Administrator'), str(sd, ['approverEmail']));
    } catch (_) {
      return ('Administrator', '');
    }
  }

  // ------------------------------------------------------------------ profile (UserRepository)
  Future<void> updateMode(String mode) => _users.doc(uid).update({'currentMode': mode});

  Future<void> updateProfile({required String name, required String phone, required String department, required String townshipLocation, required String defaultRolePreference, required int defaultDriverSeats}) =>
      _users.doc(uid).update({
        'name': name.trim(),
        'phone': phone.trim(),
        'department': department,
        'townshipLocation': townshipLocation,
        'defaultRolePreference': defaultRolePreference == AppUser.modeDriver ? AppUser.modeDriver : AppUser.modePassenger,
        'defaultDriverSeats': defaultDriverSeats.clamp(1, 8),
      });

  // ------------------------------------------------------------------ driver side
  /// Today's active ride of a driver (getDriverTodayRideFlow).
  Stream<Ride?> driverTodayRide(String driverId, String date) =>
      _rides.where('driverId', isEqualTo: driverId).where('date', isEqualTo: date).snapshots().map((s) {
        final active = s.docs.map(Ride.fromDoc).where((r) => r.isActive).toList();
        if (active.isEmpty) return null;
        active.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return active.first;
      });

  /// createOrUpdateDriverAvailability: one ride per driver per day; re-publishing edits it.
  Future<Ride> publishAvailability({required AppUser me, required String pickupZone, required int totalSeats, String message = '', String customPickupLocation = ''}) async {
    if (!me.isActive) throw 'Your account is currently restricted. Please contact the administrator.';
    final date = todayKarachi();
    final cleanPickup = pickupZone.trim().isEmpty ? 'EMs' : pickupZone.trim();
    final side = MasterData.sideForPickup(cleanPickup);
    final custom = customPickupLocation.trim().length > 150 ? customPickupLocation.trim().substring(0, 150) : customPickupLocation.trim();
    if (side == PickupSide.other && custom.isEmpty) throw 'Please enter your pickup location.';
    final seats = totalSeats.clamp(1, 8);
    final now = nowMs();

    final existing = await _rides.where('driverId', isEqualTo: me.uid).where('date', isEqualTo: date).get();
    final active = existing.docs.map(Ride.fromDoc).where((r) => r.isActive).toList();
    final current = active.isEmpty ? null : active.first;
    final accepted = current?.acceptedPassengerIds ?? const <String>[];
    final available = (seats - accepted.length).clamp(0, 8);
    final status = available == 0 ? RideStatus.full : (accepted.isNotEmpty ? RideStatus.partiallyFull : RideStatus.available);

    final ride = Ride(
      rideId: current?.rideId ?? '${me.uid}_${date}_$now',
      driverId: me.uid, driverName: me.name, driverPhone: me.phone, driverDepartment: me.department, date: date,
      pickupZone: side == PickupSide.other ? 'OTHER' : cleanPickup, pickupSide: side,
      customPickupLocation: side == PickupSide.other ? custom : '',
      totalSeats: seats, availableSeats: available, acceptedPassengerIds: accepted,
      completedPassengerIds: current?.completedPassengerIds ?? const [],
      message: message.trim().length > 250 ? message.trim().substring(0, 250) : message.trim(),
      status: status, expiresAt: now + defaultExpiryMs, creationSource: 'APP',
      createdAt: current?.createdAt ?? now, updatedAt: now, startedAt: current?.startedAt ?? 0,
      completedAt: current?.completedAt ?? 0, finalPassengerCount: 0, confirmedPassengerCount: 0,
    );
    final b = db.batch();
    if (current == null) {
      b.set(_rides.doc(ride.rideId), ride.toMap());
    } else {
      // Only the keys the rules allow a driver to edit.
      b.update(_rides.doc(ride.rideId), {
        'pickupZone': ride.pickupZone, 'pickupSide': ride.pickupSide, 'customPickupLocation': ride.customPickupLocation,
        'totalSeats': seats, 'availableSeats': available, 'status': status, 'message': ride.message,
        'expiresAt': ride.expiresAt, 'updatedAt': now, 'direction': MasterData.directionFor(side),
        'destinationZone': MasterData.destinationFor(side), 'commuteWindow': 'Any',
      });
    }
    b.update(_users.doc(me.uid), {'currentMode': AppUser.modeDriver, 'updatedAt': now});
    await b.commit();
    return ride;
  }

  /// Passengers who joined the driver today (getIncomingRequestsForDriverFlow).
  Stream<List<RideRequest>> incomingRequests(String driverId, String date) =>
      _reqs.where('driverId', isEqualTo: driverId).where('date', isEqualTo: date).snapshots().map((s) => s.docs.map(RideRequest.fromDoc).where((r) => r.isActive).toList());

  /// People looking for a ride today on this side (getMatchingPassengerNeedsFlow); "OTHER" matches every side.
  Stream<List<PassengerNeed>> lookingNeeds(String date, String side) =>
      _needs.where('date', isEqualTo: date).where('status', isEqualTo: NeedStatus.looking).limit(30).snapshots().map((s) {
        final now = nowMs();
        final list = s.docs.map(PassengerNeed.fromDoc).where((n) => n.passengerId != uid && (n.expiresAt == 0 || n.expiresAt > now) && (side == PickupSide.other || n.pickupSide == PickupSide.other || n.pickupSide == side)).toList();
        list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        return list;
      });

  /// acceptPassengerNeedDirectly: one transaction locks the need, seats the passenger, creates the request.
  Future<void> acceptNeed(AppUser me, PassengerNeed need) async {
    if (!me.isActive) throw 'Your account is currently restricted. Please contact the administrator.';
    if (need.passengerId == me.uid) throw 'You cannot accept your own ride request.';
    final now = nowMs();
    final existingSnap = await _rides.where('driverId', isEqualTo: me.uid).where('date', isEqualTo: need.date).get();
    final existing = existingSnap.docs.map(Ride.fromDoc).where((r) => RideStatus.open.contains(r.status) && r.availableSeats > 0).toList();
    final current = existing.isEmpty ? null : existing.first;
    final rideId = current?.rideId ?? '${me.uid}_${need.date}_$now';
    final rideRef = _rides.doc(rideId);
    final needRef = _needs.doc(need.needId);
    final lockRef = _locks.doc(need.passengerId);
    final reqId = '${rideId}_${need.passengerId}';

    await db.runTransaction((tx) async {
      final needDoc = await tx.get(needRef);
      if (!needDoc.exists) throw 'Ride request not found.';
      if (needDoc.data()?['status'] != NeedStatus.looking) throw 'This ride request is no longer available.';
      final lock = await tx.get(lockRef);
      if (lock.exists) throw 'This passenger already has an active ride.';
      // Reading a ride that does not exist yet would trip the rules (resource is null), so only
      // read the live copy when the driver already has a ride today.
      final live = current == null ? null : Ride.fromDoc(await tx.get(rideRef));
      if (live != null && !RideStatus.open.contains(live.status)) throw 'Your ride for today is no longer open.';

      final seats = live?.totalSeats ?? me.defaultDriverSeats.clamp(1, 8);
      final accepted = live?.acceptedPassengerIds ?? const <String>[];
      if (accepted.contains(need.passengerId)) throw 'Passenger already joined this ride.';
      final newAccepted = [...accepted, need.passengerId];
      final available = (seats - newAccepted.length).clamp(0, 8);
      final status = available == 0 ? RideStatus.full : RideStatus.partiallyFull;

      if (live == null) {
        final ride = Ride(
          rideId: rideId, driverId: me.uid, driverName: me.name, driverPhone: me.phone, driverDepartment: me.department,
          date: need.date, pickupZone: need.pickupZone, pickupSide: need.pickupSide, customPickupLocation: need.customPickupLocation,
          totalSeats: seats, availableSeats: available, acceptedPassengerIds: newAccepted, completedPassengerIds: const [],
          message: '', status: status, expiresAt: now + defaultExpiryMs, creationSource: 'DIRECT_ACCEPT',
          createdAt: now, updatedAt: now, startedAt: 0, completedAt: 0, finalPassengerCount: 0, confirmedPassengerCount: 0,
        );
        tx.set(rideRef, ride.toMap());
      } else {
        tx.update(rideRef, {'acceptedPassengerIds': newAccepted, 'availableSeats': available, 'status': status, 'updatedAt': now, 'creationSource': 'DIRECT_ACCEPT'});
      }
      tx.update(needRef, {'status': NeedStatus.matched, 'matchedDriverId': me.uid, 'matchedRideId': rideId, 'matchedAt': now, 'updatedAt': now});
      final req = RideRequest(
        requestId: reqId, rideId: rideId, needId: need.needId, passengerId: need.passengerId, passengerName: need.passengerName,
        passengerPhone: need.passengerPhone, passengerDepartment: need.passengerDepartment, driverId: me.uid, driverName: me.name,
        driverDepartment: me.department, driverPhone: me.phone, date: need.date, direction: MasterData.directionFor(need.pickupSide),
        commuteWindow: 'Any', pickupZone: need.pickupZone, customPickupLocation: need.customPickupLocation,
        destinationZone: MasterData.destinationFor(need.pickupSide), status: ReqStatus.accepted, message: need.message,
        requestedAt: now, responseAt: now, passengerCompletedAt: 0,
      );
      tx.set(_reqs.doc(reqId), req.toMap());
      tx.set(lockRef, {'rideId': rideId, 'requestId': reqId, 'passengerId': need.passengerId, 'driverId': me.uid, 'createdAt': now});
      tx.update(_users.doc(me.uid), {'currentMode': AppUser.modeDriver, 'updatedAt': now});
    });
  }

  /// closeRideAsDriver: "ride happened" (COMPLETED) or "didn't happen" (CANCELLED).
  Future<void> closeRideAsDriver(String rideId, {required bool happened}) async {
    final now = nowMs();
    final rideRef = _rides.doc(rideId);
    var passengerCount = 0;
    var completedIds = <String>[];
    var driverName = '', driverDept = '';

    await db.runTransaction((tx) async {
      final rDoc = await tx.get(rideRef);
      if (!rDoc.exists) throw 'Ride not found.';
      final ride = Ride.fromDoc(rDoc);
      if (ride.driverId != uid) throw 'You can only close your own ride.';
      if (const [RideStatus.completed, RideStatus.cancelled, RideStatus.offline].contains(ride.status)) return;
      driverName = ride.driverName;
      driverDept = ride.driverDepartment;

      final reqDocs = <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final p in ride.acceptedPassengerIds) {
        reqDocs[p] = await tx.get(_reqs.doc('${rideId}_$p'));
      }
      final needDocs = <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final r in reqDocs.values) {
        final needId = (r.data()?['needId'] as String?) ?? '';
        if (needId.isNotEmpty) needDocs[needId] = await tx.get(_needs.doc(needId));
      }

      var confirmed = 0, finalCount = 0;
      for (final p in ride.acceptedPassengerIds) {
        final rq = reqDocs[p]!;
        final st = (rq.data()?['status'] as String?) ?? '';
        final needId = (rq.data()?['needId'] as String?) ?? '';
        void cancelNeed() {
          final nd = needDocs[needId];
          if (nd != null && nd.exists && nd.data()?['status'] == NeedStatus.matched) {
            tx.update(nd.reference, {'status': NeedStatus.cancelled, 'cancelledAt': now, 'updatedAt': now});
          }
        }
        if (happened) {
          if (st == ReqStatus.completed) {
            confirmed++;
            finalCount++;
          } else if (const [ReqStatus.accepted, 'RIDE_STARTED', ReqStatus.requested].contains(st)) {
            finalCount++;
            tx.update(rq.reference, {'status': ReqStatus.closedUnconfirmed, 'closedAt': now, 'responseAt': now, 'updatedAt': now});
            cancelNeed();
          } else if (st == ReqStatus.closedUnconfirmed) {
            finalCount++;
          }
        } else if (const [ReqStatus.accepted, 'RIDE_STARTED', ReqStatus.requested].contains(st)) {
          tx.update(rq.reference, {'status': ReqStatus.cancelledByDriver, 'cancelledAt': now, 'responseAt': now, 'updatedAt': now});
          cancelNeed();
        }
        tx.delete(_locks.doc(p));
      }
      final target = happened ? RideStatus.completed : RideStatus.cancelled;
      final updates = <String, dynamic>{
        'status': target,
        'completedPassengerIds': happened ? ride.completedPassengerIds : <String>[],
        'finalPassengerCount': happened ? finalCount : 0,
        'confirmedPassengerCount': happened ? confirmed : 0,
        'updatedAt': now,
      };
      if (happened) updates['completedAt'] = now;
      if (happened) {
        passengerCount = finalCount;
        completedIds = ride.completedPassengerIds;
      }
      tx.update(rideRef, updates);
    });

    if (happened && passengerCount > 0) {
      try {
        await _logDriverCo2(rideId: rideId, driverId: uid, driverName: driverName, driverDept: driverDept, passengerCount: passengerCount, completedPassengerIds: completedIds);
      } catch (_) {}
    }
  }

  // ------------------------------------------------------------------ passenger side
  Stream<RideRequest?> _activeRequest(String passengerId) =>
      _reqs.where('passengerId', isEqualTo: passengerId).where('status', whereIn: ReqStatus.activeStatuses).limit(5).snapshots().map((s) {
        final list = s.docs.map(RideRequest.fromDoc).toList();
        if (list.isEmpty) return null;
        list.sort((a, b) => b.requestedAt.compareTo(a.requestedAt));
        return list.first;
      });

  Stream<PassengerNeed?> _lookingNeed(String passengerId, String date) =>
      _needs.where('passengerId', isEqualTo: passengerId).where('date', isEqualTo: date).snapshots().map((s) {
        final list = s.docs.map(PassengerNeed.fromDoc).where((n) => n.status == NeedStatus.looking).toList();
        if (list.isEmpty) return null;
        list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        return list.first;
      });

  /// getPassengerEligibilityFlow: active ride wins, then an open request, else free.
  Stream<PassengerState> passengerState(String passengerId, String date) {
    final ctl = StreamController<PassengerState>();
    RideRequest? req;
    PassengerNeed? need;
    var gotReq = false, gotNeed = false;
    void emit() {
      if (!gotReq || !gotNeed) return;
      if (req != null) {
        ctl.add(PassengerRiding(req!));
      } else if (need != null) {
        ctl.add(PassengerLooking(need!));
      } else {
        ctl.add(const PassengerFree());
      }
    }
    final s1 = _activeRequest(passengerId).listen((r) { req = r; gotReq = true; emit(); }, onError: ctl.addError);
    final s2 = _lookingNeed(passengerId, date).listen((n) { need = n; gotNeed = true; emit(); }, onError: ctl.addError);
    ctl.onCancel = () { s1.cancel(); s2.cancel(); };
    return ctl.stream;
  }

  /// createPassengerNeed with the same three exclusivity checks.
  Future<PassengerNeed> createNeed({required AppUser me, required String pickupZone, String message = '', String customPickupLocation = ''}) async {
    if (!me.isActive) throw 'Your account is currently restricted. Please contact the administrator.';
    final date = todayKarachi();
    final lock = await _locks.doc(me.uid).get();
    if (lock.exists) throw 'You already have an active ride.';
    final active = await _reqs.where('passengerId', isEqualTo: me.uid).where('status', whereIn: ReqStatus.activeStatuses).limit(1).get();
    if (active.docs.isNotEmpty) throw 'You already have an active ride.';
    final looking = await _needs.where('passengerId', isEqualTo: me.uid).where('date', isEqualTo: date).where('status', isEqualTo: NeedStatus.looking).limit(1).get();
    if (looking.docs.isNotEmpty) throw 'You already have an active ride request.';

    final cleanPickup = pickupZone.trim().isEmpty ? 'EMs' : pickupZone.trim();
    final side = MasterData.sideForPickup(cleanPickup);
    final custom = customPickupLocation.trim().length > 150 ? customPickupLocation.trim().substring(0, 150) : customPickupLocation.trim();
    if (side == PickupSide.other && custom.isEmpty) throw 'Please enter your pickup location.';
    final now = nowMs();
    final need = PassengerNeed(
      needId: '${me.uid}_${date}_$now', passengerId: me.uid, passengerName: me.name, passengerDepartment: me.department,
      passengerPhone: me.phone, date: date, pickupZone: side == PickupSide.other ? 'OTHER' : cleanPickup, pickupSide: side,
      customPickupLocation: side == PickupSide.other ? custom : '',
      message: message.trim().length > 250 ? message.trim().substring(0, 250) : message.trim(),
      status: NeedStatus.looking, expiresAt: now + defaultExpiryMs, matchedDriverId: '', matchedRideId: '',
      createdAt: now, updatedAt: now, matchedAt: 0,
    );
    final b = db.batch();
    b.set(_needs.doc(need.needId), need.toMap());
    b.update(_users.doc(me.uid), {'currentMode': AppUser.modePassenger, 'updatedAt': now});
    await b.commit();
    return need;
  }

  Future<void> cancelNeed(String needId) async {
    final doc = await _needs.doc(needId).get();
    if (!doc.exists) throw 'Passenger request not found.';
    if (doc.data()?['passengerId'] != uid) throw 'You can only cancel your own ride request.';
    await _needs.doc(needId).update({'status': NeedStatus.cancelled, 'updatedAt': nowMs()});
  }

  /// Drivers with seats today on this side (getAvailableDriversFlow, without the unused departureTime order).
  Stream<List<Ride>> availableDrivers(String date, String side) =>
      _rides.where('date', isEqualTo: date).where('status', whereIn: RideStatus.open).limit(30).snapshots().map((s) {
        final now = nowMs();
        final list = s.docs.map(Ride.fromDoc).where((r) => r.driverId != uid && r.availableSeats > 0 && (r.expiresAt == 0 || r.expiresAt > now) && (side == PickupSide.other || r.pickupSide == PickupSide.other || r.pickupSide == side)).toList();
        list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        return list;
      });

  /// joinRide: seat taken in a transaction, request + lock created, open need (if any) marked MATCHED.
  Future<void> joinRide(AppUser me, Ride ride, {String message = ''}) async {
    if (!me.isActive) throw 'Your account is currently restricted. Please contact the administrator.';
    if (ride.driverId == me.uid) throw 'You cannot join your own ride.';
    final now = nowMs();
    final rideRef = _rides.doc(ride.rideId);
    final lockRef = _locks.doc(me.uid);
    final reqId = '${ride.rideId}_${me.uid}';

    await db.runTransaction((tx) async {
      final rDoc = await tx.get(rideRef);
      if (!rDoc.exists) throw 'Ride no longer exists.';
      final lock = await tx.get(lockRef);
      if (lock.exists) throw 'You already have an active ride.';
      final live = Ride.fromDoc(rDoc);
      if (!RideStatus.open.contains(live.status) || live.availableSeats <= 0) throw 'This ride is already full.';
      if (live.acceptedPassengerIds.contains(me.uid)) throw 'You have already joined this ride.';
      final newAccepted = [...live.acceptedPassengerIds, me.uid];
      final available = (live.totalSeats - newAccepted.length).clamp(0, 8);
      final status = available == 0 ? RideStatus.full : RideStatus.partiallyFull;
      tx.update(rideRef, {'acceptedPassengerIds': newAccepted, 'availableSeats': available, 'status': status, 'updatedAt': now});
      final req = RideRequest(
        requestId: reqId, rideId: ride.rideId, needId: '', passengerId: me.uid, passengerName: me.name, passengerPhone: me.phone,
        passengerDepartment: me.department, driverId: live.driverId, driverName: live.driverName, driverDepartment: live.driverDepartment,
        driverPhone: live.driverPhone, date: live.date, direction: MasterData.directionFor(live.pickupSide), commuteWindow: 'Any',
        pickupZone: live.pickupZone, customPickupLocation: live.customPickupLocation, destinationZone: MasterData.destinationFor(live.pickupSide),
        status: ReqStatus.accepted, message: message.trim().length > 250 ? message.trim().substring(0, 250) : message.trim(),
        requestedAt: now, responseAt: now, passengerCompletedAt: 0,
      );
      tx.set(_reqs.doc(reqId), req.toMap());
      tx.set(lockRef, {'rideId': ride.rideId, 'requestId': reqId, 'passengerId': me.uid, 'driverId': live.driverId, 'createdAt': now});
      tx.update(_users.doc(me.uid), {'currentMode': AppUser.modePassenger, 'updatedAt': now});
    });

    try {
      final needs = await _needs.where('passengerId', isEqualTo: me.uid).where('date', isEqualTo: ride.date).where('status', isEqualTo: NeedStatus.looking).limit(1).get();
      for (final d in needs.docs) {
        await d.reference.update({'status': NeedStatus.matched, 'matchedDriverId': ride.driverId, 'matchedRideId': ride.rideId, 'matchedAt': now, 'updatedAt': now});
      }
    } catch (_) {}
  }

  /// closeMyRide: passenger says "I completed this ride" or "I didn't take this ride".
  Future<void> closeMyRide(String requestId, {required bool completed}) async {
    final reqRef = _reqs.doc(requestId);
    final first = await reqRef.get();
    if (!first.exists) throw 'Ride request not found.';
    final initial = RideRequest.fromDoc(first);
    if (initial.passengerId != uid) throw 'You can only close your own ride participation.';
    if (ReqStatus.terminal.contains(initial.status)) throw 'This ride has already been closed.';
    final rideRef = _rides.doc(initial.rideId);
    final needRef = initial.needId.isNotEmpty ? _needs.doc(initial.needId) : null;
    final now = nowMs();

    await db.runTransaction((tx) async {
      final liveReq = await tx.get(reqRef);
      if (ReqStatus.terminal.contains(liveReq.data()?['status'])) throw 'This ride has already been closed.';
      final rDoc = await tx.get(rideRef);
      if (!rDoc.exists) throw 'Ride not found.';
      final ride = Ride.fromDoc(rDoc);
      final needDoc = needRef == null ? null : await tx.get(needRef);
      final others = <String, String>{};
      for (final p in ride.acceptedPassengerIds.where((p) => p != uid)) {
        final o = await tx.get(_reqs.doc('${initial.rideId}_$p'));
        others[p] = (o.data()?['status'] as String?) ?? '';
      }
      final mine = completed ? ReqStatus.completed : ReqStatus.cancelledByPassenger;
      String statusOf(String p) => p == uid ? mine : (others[p] ?? '');
      final accepted = ride.acceptedPassengerIds;
      final allTerminal = accepted.isNotEmpty && accepted.every((p) => ReqStatus.terminal.contains(statusOf(p)));
      final confirmed = accepted.where((p) => statusOf(p) == ReqStatus.completed).length;
      final finalCount = accepted.where((p) => const [ReqStatus.completed, ReqStatus.closedUnconfirmed].contains(statusOf(p))).length;
      final newCompleted = completed && !ride.completedPassengerIds.contains(uid) ? [...ride.completedPassengerIds, uid] : ride.completedPassengerIds;

      final reqUpdates = <String, dynamic>{'status': mine, 'responseAt': now, 'updatedAt': now};
      if (completed) {
        reqUpdates['passengerCompletedAt'] = now;
        reqUpdates['completedAt'] = now;
      } else {
        reqUpdates['cancelledAt'] = now;
      }
      tx.update(reqRef, reqUpdates);

      if (needRef != null && needDoc != null && needDoc.exists && needDoc.data()?['status'] == NeedStatus.matched) {
        tx.update(needRef, {
          'status': completed ? NeedStatus.completed : NeedStatus.cancelled,
          'updatedAt': now,
          if (completed) 'completedAt': now else 'cancelledAt': now,
        });
      }

      if (completed) {
        final ru = <String, dynamic>{'completedPassengerIds': newCompleted, 'updatedAt': now};
        if (allTerminal) {
          final target = confirmed > 0 ? RideStatus.completed : RideStatus.cancelled;
          ru['status'] = target;
          ru['finalPassengerCount'] = finalCount;
          ru['confirmedPassengerCount'] = confirmed;
          if (target == RideStatus.completed) ru['completedAt'] = now;
        }
        tx.update(rideRef, ru);
      } else if (allTerminal) {
        final target = confirmed > 0 ? RideStatus.completed : RideStatus.cancelled;
        final ru = <String, dynamic>{'status': target, 'completedPassengerIds': ride.completedPassengerIds, 'finalPassengerCount': finalCount, 'confirmedPassengerCount': confirmed, 'updatedAt': now};
        if (target == RideStatus.completed) ru['completedAt'] = now;
        tx.update(rideRef, ru);
      }
      tx.delete(_locks.doc(uid));
    });

    if (completed) {
      try {
        await _logPassengerCo2(rideId: initial.rideId, passengerId: uid, name: initial.passengerName, dept: initial.passengerDepartment);
      } catch (_) {}
    }
  }

  // ------------------------------------------------------------------ history
  Stream<List<RideRequest>> passengerHistory(String passengerId) =>
      _reqs.where('passengerId', isEqualTo: passengerId).limit(20).snapshots().map((s) {
        final l = s.docs.map(RideRequest.fromDoc).toList();
        l.sort((a, b) => (b.requestedAt > b.responseAt ? b.requestedAt : b.responseAt).compareTo(a.requestedAt > a.responseAt ? a.requestedAt : a.responseAt));
        return l;
      });

  Stream<List<Ride>> driverHistory(String driverId) =>
      _rides.where('driverId', isEqualTo: driverId).limit(20).snapshots().map((s) {
        final l = s.docs.map(Ride.fromDoc).toList();
        int key(Ride r) => [r.createdAt, r.startedAt, r.completedAt].reduce((a, b) => a > b ? a : b);
        l.sort((a, b) => key(b).compareTo(key(a)));
        return l;
      });

  // ------------------------------------------------------------------ CO₂ + leaderboard (same maths as the phone)
  Future<SustainabilityConfig> sustainability() async {
    try {
      return SustainabilityConfig.fromDoc(await _config.doc('sustainability').get());
    } catch (_) {
      return const SustainabilityConfig();
    }
  }

  Stream<List<LeaderboardEntry>> leaderboard() => _config.doc('leaderboard').snapshots().map(LeaderboardEntry.parse);

  String _monthYear(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).add(const Duration(hours: 5));
    return '${d.year}-${d.month.toString().padLeft(2, '0')}';
  }

  Future<void> _writeCo2(String recordId, String rideId, String uid, String name, String dept, int passengerCount, SustainabilityConfig c, int now) async {
    final avoided = passengerCount * c.baselineDistanceKm;
    final saved = avoided * c.co2FactorKgPerKm;
    await db.collection('co2Records').doc(recordId).set({
      'recordId': recordId, 'rideId': rideId, 'driverId': uid, 'driverName': name, 'driverDepartment': dept,
      'passengerCount': passengerCount, 'baselineDistanceKm': c.baselineDistanceKm, 'totalAvoidedKm': avoided,
      'co2FactorKgPerKm': c.co2FactorKgPerKm, 'co2SavedKg': saved, 'monthYear': _monthYear(now), 'timestamp': now,
    });
    try {
      await _users.doc(uid).update({'totalCo2SavedKg': FieldValue.increment(saved), 'totalCompletedRides': FieldValue.increment(1)});
    } catch (_) {}
  }

  Future<void> _logDriverCo2({required String rideId, required String driverId, required String driverName, required String driverDept, required int passengerCount, required List<String> completedPassengerIds}) async {
    final now = nowMs();
    final c = await sustainability();
    final driverSaved = passengerCount * c.baselineDistanceKm * c.co2FactorKgPerKm;
    await _writeCo2('${rideId}_driver_$driverId', rideId, driverId, driverName.isEmpty ? 'Driver' : driverName, driverDept.isEmpty ? 'Operations' : driverDept, passengerCount, c, now);
    for (final p in completedPassengerIds) {
      String pName = 'Passenger', pDept = 'Operations';
      try {
        final pd = await _users.doc(p).get();
        pName = str(pd.data() ?? {}, ['name'], fallback: 'Passenger');
        pDept = str(pd.data() ?? {}, ['department'], fallback: 'Operations');
      } catch (_) {}
      await _writeCo2('${rideId}_passenger_$p', rideId, p, pName, pDept, 1, c, now);
    }
    await _syncLeaderboard(driverId, driverName, driverDept, driverSaved);
  }

  Future<void> _logPassengerCo2({required String rideId, required String passengerId, required String name, required String dept}) async {
    final now = nowMs();
    final c = await sustainability();
    await _writeCo2('${rideId}_passenger_$passengerId', rideId, passengerId, name.isEmpty ? 'Passenger' : name, dept.isEmpty ? 'Operations' : dept, 1, c, now);
    await _syncLeaderboard(passengerId, name, dept, c.baselineDistanceKm * c.co2FactorKgPerKm);
  }

  /// syncLeaderboardFromCo2Records: keep systemConfig/leaderboard's top 3 current.
  Future<void> _syncLeaderboard(String uid, String name, String dept, double increment) async {
    if (uid.isEmpty || increment <= 0) return;
    final ref = _config.doc('leaderboard');
    await db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final entries = LeaderboardEntry.parse(snap).toList();
      final idx = entries.indexWhere((e) => e.uid == uid);
      final minCo2 = entries.isEmpty ? 0.0 : entries.last.co2SavedKg;
      if (idx != -1) {
        entries[idx] = entries[idx].copyWith(co2SavedKg: entries[idx].co2SavedKg + increment, rideCount: entries[idx].rideCount + 1);
      } else if (entries.length < 3) {
        entries.add(LeaderboardEntry(uid: uid, name: name.isEmpty ? 'Contributor' : name, department: dept.isEmpty ? 'Operations' : dept, co2SavedKg: increment, rideCount: 1, rank: 1));
      } else if (increment > minCo2) {
        final ud = await tx.get(_users.doc(uid));
        final total = dbl(ud.data() ?? {}, ['totalCo2SavedKg'], fallback: increment);
        if (total <= minCo2) return;
        entries.add(LeaderboardEntry(uid: uid, name: name.isEmpty ? 'Contributor' : name, department: dept.isEmpty ? 'Operations' : dept, co2SavedKg: total, rideCount: intOf(ud.data() ?? {}, ['totalCompletedRides'], fallback: 1), rank: 1));
      } else {
        return;
      }
      entries.sort((a, b) => b.co2SavedKg.compareTo(a.co2SavedKg));
      final top = [for (var i = 0; i < entries.length && i < 3; i++) entries[i].copyWith(rank: i + 1)];
      tx.set(ref, {'entries': top.map((e) => e.toMap()).toList(), 'updatedAt': nowMs()}, SetOptions(merge: true));
    });
  }

  // ------------------------------------------------------------------ admin (AdminRepository)
  Stream<List<AppUser>> pendingUsers() => _users.where('accountStatus', isEqualTo: AppUser.statusPending).snapshots().map((s) {
        final l = s.docs.map(AppUser.fromDoc).whereType<AppUser>().where((u) => u.isPending).toList();
        l.sort((a, b) => (b.approvalRequestedAt > 0 ? b.approvalRequestedAt : b.createdAt).compareTo(a.approvalRequestedAt > 0 ? a.approvalRequestedAt : a.createdAt));
        return l;
      });

  Stream<List<AppUser>> members({int limit = 300}) => _users.orderBy('name').limit(limit).snapshots().map((s) => s.docs.map(AppUser.fromDoc).whereType<AppUser>().toList());

  Future<void> _audit(AppUser admin, AppUser target, String action, String reason, int now, String idPart) =>
      db.collection('auditLogs').doc('${now}_${idPart}_${target.uid}').set(AuditLog(auditId: '${now}_${idPart}_${target.uid}', adminUid: admin.uid, adminName: admin.name, adminEmail: admin.email, targetUid: target.uid, targetName: target.name, targetEmail: target.email, action: action, reason: reason, timestamp: now).toMap());

  Future<void> approveUser(AppUser admin, AppUser target) async {
    if (!admin.isAdmin) throw 'Only an administrator can approve accounts.';
    final now = nowMs();
    await _users.doc(target.uid).update({'accountStatus': AppUser.statusActive, 'approvedAt': now, 'approvedBy': admin.uid, 'updatedAt': now});
    try {
      await _config.doc('appApproval').set({'approverDisplayName': admin.name.isEmpty ? 'Administrator' : admin.name, 'approverEmail': admin.email, 'updatedAt': now}, SetOptions(merge: true));
    } catch (_) {}
    await _audit(admin, target, AuditLog.approveUser, 'Account approved by administrator', now, 'approve');
  }

  Future<void> blockMember(AppUser admin, AppUser target, String reason) async {
    final now = nowMs();
    await _users.doc(target.uid).update({'accountStatus': AppUser.statusBlocked, 'blockedAt': now, 'blockedBy': admin.uid, 'blockReason': reason.trim(), 'updatedAt': now});
    await _audit(admin, target, AuditLog.blockMember, reason.trim(), now, 'block');
  }

  Future<void> unblockMember(AppUser admin, AppUser target) async {
    final now = nowMs();
    await _users.doc(target.uid).update({'accountStatus': AppUser.statusActive, 'blockedAt': 0, 'blockedBy': '', 'blockReason': '', 'updatedAt': now});
    await _audit(admin, target, AuditLog.unblockMember, 'Unblocked by admin', now, 'unblock');
  }

  Future<void> removeMember(AppUser admin, AppUser target, String reason) async {
    final now = nowMs();
    await _users.doc(target.uid).update({'accountStatus': AppUser.statusRemoved, 'removedAt': now, 'removedBy': admin.uid, 'removeReason': reason.trim(), 'updatedAt': now});
    await _audit(admin, target, AuditLog.removeMember, reason.trim(), now, 'remove');
  }

  Future<void> setRole(AppUser admin, AppUser target, bool makeAdmin) async {
    final role = makeAdmin ? AppUser.roleAdmin : AppUser.roleUser;
    final now = nowMs();
    await _users.doc(target.uid).update({'role': role});
    await _audit(admin, target, AuditLog.roleChange, 'Role changed to $role', now, 'role');
  }

  Stream<ManagementReport> managementReport() => _config.doc('managementReport').snapshots().map(ManagementReport.fromDoc);

  /// recalculateAndPersistManagementReport: every member, completed rides and completed requests.
  Future<ManagementReport> recalculateReport() async {
    final now = nowMs();
    final users = (await _users.get()).docs.map(AppUser.fromDoc).whereType<AppUser>().toList();
    final rides = (await _rides.where('status', isEqualTo: RideStatus.completed).get()).docs.map(Ride.fromDoc).toList();
    final reqs = (await _reqs.where('status', isEqualTo: ReqStatus.completed).get()).docs.map(RideRequest.fromDoc).toList();
    final c = await sustainability();
    final rows = users.map((u) {
      final dr = rides.where((r) => r.driverId == u.uid).toList();
      final delivered = dr.fold<int>(0, (s, r) => s + (r.finalPassengerCount > 0 ? r.finalPassengerCount : (r.completedPassengerIds.length > r.acceptedPassengerIds.length ? r.completedPassengerIds.length : r.acceptedPassengerIds.length)));
      final pr = reqs.where((r) => r.passengerId == u.uid).length;
      return ManagementReportRow(serialNumber: 0, personName: u.name.isEmpty ? 'User ${u.uid.substring(0, u.uid.length < 5 ? u.uid.length : 5)}' : u.name, co2Saved: (delivered + pr) * c.baselineDistanceKm * c.co2FactorKgPerKm, ridesAsDriver: dr.length, ridesAsPassenger: pr);
    }).toList()
      ..sort((a, b) => b.co2Saved.compareTo(a.co2Saved));
    final numbered = [for (var i = 0; i < rows.length; i++) ManagementReportRow(serialNumber: i + 1, personName: rows[i].personName, co2Saved: rows[i].co2Saved, ridesAsDriver: rows[i].ridesAsDriver, ridesAsPassenger: rows[i].ridesAsPassenger)];
    final report = ManagementReport(rows: numbered, totalMembers: numbered.length, totalCo2Saved: numbered.fold(0.0, (s, r) => s + r.co2Saved), totalDriverRides: rides.length, totalPassengerRides: reqs.length, updatedAt: now);
    await _config.doc('managementReport').set({
      'rows': numbered.map((r) => r.toMap()).toList(), 'updatedAt': now, 'totalMembers': report.totalMembers,
      'totalCo2Saved': report.totalCo2Saved, 'totalDriverRides': report.totalDriverRides, 'totalPassengerRides': report.totalPassengerRides,
    }, SetOptions(merge: true));
    return report;
  }

  Stream<List<AuditLog>> auditLogs({int limit = 50}) => db.collection('auditLogs').orderBy('timestamp', descending: true).limit(limit).snapshots().map((s) => s.docs.map(AuditLog.fromDoc).toList());

  Future<void> updateSustainability(double baselineKm, double factor) async {
    if (baselineKm <= 0) throw 'Baseline distance must be greater than zero.';
    if (factor <= 0) throw 'CO₂ factor must be greater than zero.';
    await _config.doc('sustainability').set({'baselineDistanceKm': baselineKm, 'co2FactorKgPerKm': factor}, SetOptions(merge: true));
  }

  Stream<List<Ride>> todayRides(String date) => _rides.where('date', isEqualTo: date).limit(50).snapshots().map((s) => s.docs.map(Ride.fromDoc).toList());

  // ------------------------------------------------------------------ errors
  static String friendly(Object e) {
    if (e is String) return e;
    if (e is FirebaseAuthException) {
      return switch (e.code) {
        'invalid-credential' || 'wrong-password' || 'user-not-found' || 'invalid-login-credentials' => 'Email or password is incorrect.',
        'invalid-email' => 'Please enter a valid email address.',
        'email-already-in-use' => 'An account with this email already exists. Please log in.',
        'weak-password' => 'Password must be at least 6 characters long.',
        'too-many-requests' => 'Too many attempts. Please wait a few minutes and try again.',
        'network-request-failed' => 'No internet connection.',
        'popup-closed-by-user' || 'cancelled-popup-request' => 'Google sign-in was cancelled.',
        'popup-blocked' => 'The browser blocked the Google sign-in window. Allow pop-ups for this site and try again.',
        'unauthorized-domain' => 'Google sign-in is not enabled for this website yet. Please use email sign-in or contact the administrator.',
        'account-exists-with-different-credential' => 'This email is registered with a password. Please log in with email and password.',
        _ => e.message ?? 'Sign-in failed (${e.code}).',
      };
    }
    if (e is FirebaseException) {
      if (e.code == 'permission-denied') return 'Not allowed. Refresh the page and try again, or contact the administrator.';
      if (e.code == 'unavailable') return 'No connection to the server. Check your internet and try again.';
      if (e.code == 'failed-precondition') return 'The server needs a database index for this view. Please tell the administrator.';
      return e.message ?? 'Something went wrong (${e.code}).';
    }
    final s = e.toString();
    return s.startsWith('Exception: ') ? s.substring(11) : s;
  }
}

/// Tiny ValueNotifier without importing Flutter here.
class ValueNotifierLite {
  ValueNotifierLite(this._v);
  bool _v;
  final _ctl = StreamController<bool>.broadcast();
  bool get value => _v;
  set value(bool v) {
    _v = v;
    _ctl.add(v);
  }
  Stream<bool> get stream => _ctl.stream;
}
