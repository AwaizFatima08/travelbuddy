// All Firebase access in one place. Screens only talk to Repo.
//
// Read budget: live listeners only on the signed-in user's doc, the site doc, the open posts of
// ONE window, the user's own active rides/posts, one ride + its live positions, the notification
// list, and (admins) the pending list. Everything else is a one-time get.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../firebase_options.dart' show googleServerClientId;
import 'models.dart';

/// A user-facing error with a plain-English message.
class AppError implements Exception {
  AppError(this.message);
  final String message;
  @override
  String toString() => message;
}

class RegisterForm {
  const RegisterForm({
    required this.name,
    required this.email,
    required this.password,
    required this.employeeId,
    required this.department,
    required this.phone,
    required this.townshipLocation,
    required this.hasCar,
  });
  final String name, email, password, employeeId, department, phone, townshipLocation;
  final bool hasCar;
}

class Repo {
  Repo._();
  static final Repo I = Repo._();

  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  final _fn = FirebaseFunctions.instanceFor(region: 'asia-south1');

  static const defaultSiteId = 'ffl';

  CollectionReference<Map<String, dynamic>> get _users => _db.collection('users');
  CollectionReference<Map<String, dynamic>> get _posts => _db.collection('posts');
  CollectionReference<Map<String, dynamic>> get _rides => _db.collection('rides');
  CollectionReference<Map<String, dynamic>> get _sites => _db.collection('sites');

  // ------------------------------------------------------------------ auth

  User? get currentUser => _auth.currentUser;
  Stream<User?> authChanges() => _auth.authStateChanges();

  Future<void> signInEmail(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
    } on FirebaseAuthException catch (e) {
      throw AppError(friendly(e));
    }
  }

  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      // Don't reveal whether the account exists.
      if (e.code != 'user-not-found') throw AppError(friendly(e));
    }
  }

  /// Google sign-in. Returns true if this Google user has no profile yet (must register).
  Future<bool> signInGoogle() async {
    UserCredential cred;
    try {
      if (kIsWeb) {
        final provider = GoogleAuthProvider()..addScope('email');
        cred = await _auth.signInWithPopup(provider);
      } else {
        final gsi = GoogleSignIn.instance;
        await gsi.initialize(serverClientId: googleServerClientId);
        final account = await gsi.authenticate();
        final idToken = account.authentication.idToken;
        if (idToken == null) throw AppError('Google sign-in failed. Please try again.');
        cred = await _auth.signInWithCredential(GoogleAuthProvider.credential(idToken: idToken));
      }
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) throw AppError('Sign-in cancelled.');
      throw AppError('Google sign-in failed: ${e.description ?? e.code.name}');
    } on FirebaseAuthException catch (e) {
      throw AppError(friendly(e));
    }
    final uid = cred.user!.uid;
    final doc = await _users.doc(uid).get();
    return !doc.exists;
  }

  /// Email registration: creates the Auth user, then the PENDING profile.
  Future<void> registerEmail(RegisterForm f) async {
    try {
      await _auth.createUserWithEmailAndPassword(email: f.email.trim(), password: f.password);
    } on FirebaseAuthException catch (e) {
      throw AppError(friendly(e));
    }
    await createProfile(f);
  }

  /// Creates the PENDING profile for the signed-in Auth user (email or Google).
  Future<void> createProfile(RegisterForm f) async {
    final u = _auth.currentUser;
    if (u == null) throw AppError('Please sign in again.');
    await _users.doc(u.uid).set({
      'name': f.name.trim(),
      'email': (u.email ?? f.email).trim().toLowerCase(),
      'phone': f.phone.trim(),
      'employeeId': f.employeeId.trim(),
      'department': f.department.trim(),
      'townshipLocation': f.townshipLocation.trim(),
      'hasCar': f.hasCar,
      'siteId': defaultSiteId,
      'accountStatus': 'PENDING',
      'role': 'USER',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> signOut() async {
    final u = _auth.currentUser;
    if (u != null) {
      // Stop push to this device after logout.
      await _users.doc(u.uid).update({'fcmTokens.${_lastToken ?? '-'}': FieldValue.delete()}).catchError((_) {});
    }
    if (!kIsWeb) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    }
    await _auth.signOut();
  }

  /// Deletes profile + sign-in. Email users pass their password; Google users re-sign-in.
  Future<void> deleteAccount({String? password}) async {
    final u = _auth.currentUser;
    if (u == null) throw AppError('Please sign in again.');
    try {
      final isGoogle = u.providerData.any((p) => p.providerId == 'google.com');
      if (isGoogle) {
        if (kIsWeb) {
          await u.reauthenticateWithPopup(GoogleAuthProvider());
        } else {
          final gsi = GoogleSignIn.instance;
          await gsi.initialize(serverClientId: googleServerClientId);
          final acc = await gsi.authenticate();
          await u.reauthenticateWithCredential(
              GoogleAuthProvider.credential(idToken: acc.authentication.idToken));
        }
      } else {
        if (password == null || password.isEmpty) throw AppError('Please enter your password.');
        await u.reauthenticateWithCredential(EmailAuthProvider.credential(email: u.email!, password: password));
      }
    } on FirebaseAuthException catch (e) {
      throw AppError(e.code == 'wrong-password' || e.code == 'invalid-credential' ? 'Wrong password.' : friendly(e));
    } on GoogleSignInException {
      throw AppError('Google confirmation was cancelled.');
    }
    await _call('deleteMyAccount', {});
    await u.delete();
    await signOut();
  }

  Stream<UserProfile?> userStream(String uid) =>
      _users.doc(uid).snapshots().map((d) => d.exists ? UserProfile.fromDoc(d) : null);

  Future<void> updateMyProfile(Map<String, dynamic> fields) async {
    final u = _auth.currentUser!;
    await _users.doc(u.uid).update(fields);
  }

  String? _lastToken;
  Future<void> saveFcmToken(String token) async {
    final u = _auth.currentUser;
    if (u == null) return;
    _lastToken = token;
    await _users.doc(u.uid).set({
      'fcmTokens': {token: FieldValue.serverTimestamp()}
    }, SetOptions(merge: true));
  }

  // ------------------------------------------------------------------ site

  Stream<Site?> siteStream(String siteId) =>
      _sites.doc(siteId).snapshots().map((d) => d.exists ? Site.fromDoc(d) : null);

  Future<Site?> getSite(String siteId) async {
    final d = await _sites.doc(siteId).get();
    return d.exists ? Site.fromDoc(d) : null;
  }

  Future<void> saveSite(Site site) => _sites.doc(site.id).set(site.toMap());

  // ------------------------------------------------------------------ posts

  /// Open posts (offers + requests) for one window on one date — the board. ONE listener.
  Stream<List<Post>> windowPosts(String siteId, String date, String windowId) => _posts
      .where('siteId', isEqualTo: siteId)
      .where('date', isEqualTo: date)
      .where('windowId', isEqualTo: windowId)
      .where('status', isEqualTo: 'OPEN')
      .snapshots()
      .map((s) => s.docs.map(Post.fromDoc).toList()..sort((a, b) => a.departAt.compareTo(b.departAt)));

  /// My posts that are still open (so the home screen can show "you're offering / waiting").
  Stream<List<Post>> myOpenPosts(String uid) => _posts
      .where('userId', isEqualTo: uid)
      .where('status', whereIn: ['OPEN', 'FULL'])
      .snapshots()
      .map((s) => s.docs.map(Post.fromDoc).toList()..sort((a, b) => a.departAt.compareTo(b.departAt)));

  Future<String> createPost({
    required UserProfile me,
    required PostKind kind,
    required WindowSlotData slot,
    required DateTime departAt,
    required String fromPlaceId,
    required String toPlaceId,
    int seats = 1,
    bool autoAccept = true,
    String note = '',
  }) async {
    final ref = _posts.doc();
    await ref.set({
      'siteId': me.siteId,
      'kind': kind == PostKind.offer ? 'OFFER' : 'REQUEST',
      'userId': me.uid,
      'userName': me.name,
      'userPhone': me.phone,
      'windowId': slot.windowId,
      'date': slot.date,
      'departAt': Timestamp.fromDate(departAt),
      'fromPlaceId': fromPlaceId,
      'toPlaceId': toPlaceId,
      'seats': kind == PostKind.offer ? seats : 1,
      'seatsLeft': kind == PostKind.offer ? seats : 1,
      'status': 'OPEN',
      'autoAccept': autoAccept,
      'note': note.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'deleteAt': Timestamp.fromDate(departAt.add(const Duration(days: 30))),
    });
    return ref.id;
  }

  Future<void> cancelPost(String postId) => _call('cancelPost', {'postId': postId});

  Future<void> setAutoAccept(String postId, bool on) => _posts.doc(postId).update({'autoAccept': on});

  // ------------------------------------------------------------------ rides

  Stream<List<Ride>> myActiveRides(String uid) => _rides
      .where('participantIds', arrayContains: uid)
      .where('status', whereIn: ['LOCKED', 'PICKED_UP'])
      .snapshots()
      .map((s) => s.docs.map(Ride.fromDoc).toList()..sort((a, b) => a.departAt.compareTo(b.departAt)));

  Stream<Ride?> rideStream(String id) =>
      _rides.doc(id).snapshots().map((d) => d.exists ? Ride.fromDoc(d) : null);

  Stream<List<LivePosition>> liveStream(String rideId) =>
      _rides.doc(rideId).collection('live').snapshots().map((s) => s.docs.map(LivePosition.fromDoc).toList());

  /// Not awaited by callers; Firestore queues it offline.
  Future<void> writeLive(String rideId, double lat, double lng) {
    final u = _auth.currentUser!;
    return _rides.doc(rideId).collection('live').doc(u.uid).set({
      'lat': lat,
      'lng': lng,
      'at': FieldValue.serverTimestamp(),
      'deleteAt': Timestamp.fromDate(DateTime.now().add(const Duration(hours: 6))),
    });
  }

  Future<void> clearLive(String rideId) async {
    final u = _auth.currentUser!;
    try {
      await _rides.doc(rideId).collection('live').doc(u.uid).delete();
    } catch (_) {}
  }

  /// History: rides I was part of, newest first, 20 per page.
  Future<(List<Ride>, DocumentSnapshot?)> history(String uid, DocumentSnapshot? after) async {
    var q = _rides.where('participantIds', arrayContains: uid).orderBy('departAt', descending: true).limit(20);
    if (after != null) q = q.startAfterDocument(after);
    final s = await q.get();
    return (s.docs.map(Ride.fromDoc).toList(), s.docs.isEmpty ? null : s.docs.last);
  }

  // ---- server actions (Cloud Functions). Each is one transaction on the server.

  /// Driver accepts a passenger's request into their offer.
  Future<String> acceptRequest(String offerPostId, String requestPostId) async =>
      (await _call('acceptRequest', {'offerPostId': offerPostId, 'requestPostId': requestPostId}))['rideId']
          as String;

  /// Passenger joins an offered car directly (auto-accept) or asks to join.
  Future<Map<String, dynamic>> joinOffer(String offerPostId, String pickupPlaceId, String dropPlaceId) =>
      _call('joinOffer', {'offerPostId': offerPostId, 'pickupPlaceId': pickupPlaceId, 'dropPlaceId': dropPlaceId});

  Future<void> cancelRide(String rideId) => _call('cancelRide', {'rideId': rideId});
  Future<void> markPickedUp(String rideId, {String? passengerUid}) =>
      _call('markPickedUp', {'rideId': rideId, if (passengerUid != null) 'passengerUid': passengerUid});
  Future<void> completeRide(String rideId) => _call('completeRide', {'rideId': rideId});
  Future<void> reportNoShow(String rideId, String uid) => _call('reportNoShow', {'rideId': rideId, 'uid': uid});
  Future<void> disputeNoShow(String rideId) => _call('disputeNoShow', {'rideId': rideId});
  Future<void> resolveNoShow(String rideId, String uid, bool upheld) =>
      _call('resolveNoShow', {'rideId': rideId, 'uid': uid, 'upheld': upheld});
  Future<void> createDefaultSite() => _call('createDefaultSite', {});

  Future<Map<String, dynamic>> _call(String name, Map<String, dynamic> data) async {
    try {
      final r = await _fn.httpsCallable(name).call<Map<String, dynamic>?>(data);
      return Map<String, dynamic>.from(r.data ?? const {});
    } on FirebaseFunctionsException catch (e) {
      throw AppError(e.message ?? 'Something went wrong (${e.code}).');
    }
  }

  // ------------------------------------------------------------------ notifications

  Stream<List<AppNotification>> notifications(String uid) => _db
      .collection('notifications')
      .doc(uid)
      .collection('items')
      .orderBy('at', descending: true)
      .limit(50)
      .snapshots()
      .map((s) => s.docs.map(AppNotification.fromDoc).toList());

  Future<void> markRead(String uid, String id) =>
      _db.collection('notifications').doc(uid).collection('items').doc(id).update({'read': true});

  // ------------------------------------------------------------------ points & leaderboard

  Future<List<PointsEntry>> myPoints(String uid, {int limit = 50}) async {
    final s = await _db
        .collection('points')
        .where('uid', isEqualTo: uid)
        .orderBy('at', descending: true)
        .limit(limit)
        .get();
    return s.docs.map(PointsEntry.fromDoc).toList();
  }

  /// Monthly totals doc id: "<siteId>_YYYY-MM".
  Future<(List<MonthlyRow>, Map<String, dynamic>)> monthly(String siteId, String ym) async {
    final d = await _db.collection('monthly').doc('${siteId}_$ym').get();
    final m = d.data() ?? const {};
    final users = Map<String, dynamic>.from((m['users'] as Map?) ?? const {});
    final rows = users.entries
        .map((e) => MonthlyRow.fromMap(e.key, Map<String, dynamic>.from(e.value as Map)))
        .toList()
      ..sort((a, b) => b.points.compareTo(a.points));
    return (rows, Map<String, dynamic>.from((m['totals'] as Map?) ?? const {}));
  }

  // ------------------------------------------------------------------ admin

  Stream<List<UserProfile>> pendingUsers() => _users
      .where('accountStatus', isEqualTo: 'PENDING')
      .snapshots()
      .map((s) => s.docs.map(UserProfile.fromDoc).toList()..sort((a, b) => a.name.compareTo(b.name)));

  Future<List<UserProfile>> recentAdminActions() async {
    final s = await _users.orderBy('lastAdminActionAt', descending: true).limit(30).get();
    return s.docs.map(UserProfile.fromDoc).toList();
  }

  Future<List<UserProfile>> findUsers(String text) async {
    final t = text.trim().toLowerCase();
    final byEmail = await _users.where('email', isEqualTo: t).limit(5).get();
    if (byEmail.docs.isNotEmpty) return byEmail.docs.map(UserProfile.fromDoc).toList();
    final byEmp = await _users.where('employeeId', isEqualTo: text.trim()).limit(5).get();
    return byEmp.docs.map(UserProfile.fromDoc).toList();
  }

  /// APPROVED → ACTIVE, BLOCKED → BLOCKED, UNBLOCKED → ACTIVE, with an audit entry (last 20 kept).
  Future<void> adminAction(String targetUid, String action, String reason, UserProfile admin) async {
    if (targetUid == admin.uid) throw AppError("You can't change your own account.");
    final status = action == 'BLOCKED' ? 'BLOCKED' : 'ACTIVE';
    final ref = _users.doc(targetUid);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw AppError('That user no longer exists.');
      final old = List<Map<String, dynamic>>.from(
          ((snap.data()!['audit'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
      old.add({
        'action': action,
        'by': admin.uid,
        'byName': admin.name,
        'at': Timestamp.now(),
        'reason': reason.trim(),
      });
      tx.update(ref, {
        'accountStatus': status,
        'audit': old.length > 20 ? old.sublist(old.length - 20) : old,
        'lastAdminActionAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<List<Ride>> ridesWithOpenDisputes(String siteId) async {
    final s = await _rides.where('siteId', isEqualTo: siteId).where('hasOpenDispute', isEqualTo: true).limit(50).get();
    return s.docs.map(Ride.fromDoc).toList();
  }

  Future<Map<String, dynamic>> adminReport(String siteId, String ym) async =>
      _call('adminReport', {'siteId': siteId, 'month': ym});

  // ------------------------------------------------------------------ errors

  static String friendly(Object e) {
    if (e is AppError) return e.message;
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'invalid-credential':
        case 'wrong-password':
        case 'user-not-found':
          return 'Wrong email or password.';
        case 'email-already-in-use':
          return 'An account with this email already exists. Try logging in.';
        case 'invalid-email':
          return "That email address doesn't look right.";
        case 'weak-password':
          return 'Password must be at least 8 characters.';
        case 'network-request-failed':
          return 'No internet connection. Please try again.';
        case 'too-many-requests':
          return 'Too many attempts. Please wait a few minutes.';
        case 'account-exists-with-different-credential':
          return 'This email is already registered with a password. Log in with the password instead.';
      }
      return e.message ?? 'Sign-in failed.';
    }
    if (e is FirebaseException) {
      if (e.code == 'permission-denied') return 'Not allowed. Your account may not be approved yet.';
      if (e.code == 'unavailable') return 'No internet connection. Please try again.';
      if (e.code == 'failed-precondition') return 'Database index is still building. Try again in a few minutes.';
      return e.message ?? 'Something went wrong.';
    }
    return e.toString();
  }
}

/// The bits of a window slot a post needs (kept free of Flutter types so Repo stays testable).
class WindowSlotData {
  const WindowSlotData({required this.date, required this.windowId});
  final String date;
  final String windowId;
}
