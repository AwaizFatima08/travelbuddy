// Data model of the FFL Travel Buddy Android app (com.aistudio.carpool.kjqxcv), mirrored field by
// field so the web app and the phone app read and write the same Firestore documents.
// Source of truth: the Kotlin data classes in app/src/main/java/com/example/data/model/.
import 'package:cloud_firestore/cloud_firestore.dart';

// ---------------------------------------------------------------- parsing helpers
String str(Map<String, dynamic> d, List<String> keys, {String fallback = ''}) {
  for (final k in keys) {
    final v = d[k];
    if (v == null) continue;
    final s = v is String ? v : v.toString();
    if (s.trim().isNotEmpty) return s.trim();
  }
  return fallback;
}

int millis(Map<String, dynamic> d, String key, {int fallback = 0}) {
  final v = d[key];
  if (v is Timestamp) return v.millisecondsSinceEpoch;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

int intOf(Map<String, dynamic> d, List<String> keys, {int fallback = 0}) {
  for (final k in keys) {
    final v = d[k];
    if (v == null) continue;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }
  return fallback;
}

double dbl(Map<String, dynamic> d, List<String> keys, {double fallback = 0}) {
  for (final k in keys) {
    final v = d[k];
    if (v == null) continue;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? fallback;
    return fallback;
  }
  return fallback;
}

bool boolOf(Map<String, dynamic> d, String key, {bool fallback = false}) {
  final v = d[key];
  if (v is bool) return v;
  if (v is String) return v.toLowerCase() == 'true';
  if (v is num) return v != 0;
  return fallback;
}

List<String> strList(Map<String, dynamic> d, String key) =>
    ((d[key] as List?) ?? const []).whereType<String>().toList();

int nowMs() => DateTime.now().millisecondsSinceEpoch;

// ---------------------------------------------------------------- master data (MasterData.kt)
class PickupSide {
  static const township = 'TOWNSHIP';
  static const plant = 'PLANT';
  static const other = 'OTHER';
  static String label(String side) => switch (side) { plant => 'Plant', other => 'Other', _ => 'Township' };
}

class MasterData {
  static const townshipLocations = [
    'D-Type — Blocks A–K/L',
    'C-Type',
    'MOQs',
    'EMs',
    'BOQs',
    'Guest Houses',
    'Single Staff',
  ];
  static const plantLocations = [
    'FFL Plant Main Gate',
    'HSE Building',
    'Warehouse',
    'L&DC Building',
    'Main Workshop',
    'Laboratory',
    'CCR-1',
    'MCR',
    'Maintenance South Workshop',
    'Maintenance North Workshop',
  ];
  static const otherLocationName = 'Other / Different Location';
  static const otherZone = 'OTHER';
  static const departments = [
    'Maintenance',
    'HSE',
    'Production',
    'Administration',
    'Laboratory',
    'Logistics & Warehouse',
    'Engineering',
    'IT & Telecom',
  ];

  static String sideForPickup(String pickup) {
    final t = pickup.trim().toLowerCase();
    if (t == otherLocationName.toLowerCase() || t == otherZone.toLowerCase()) return PickupSide.other;
    if (plantLocations.any((p) => p.toLowerCase() == t)) return PickupSide.plant;
    return PickupSide.township;
  }

  /// Legacy direction string the Android app still writes.
  static String directionFor(String side) => side == PickupSide.township ? 'Township → Plant' : 'Plant → Township';
  static String destinationFor(String side) => side == PickupSide.township ? 'FFL Plant Main Gate' : 'EMs';
}

/// Today in Pakistan time (Asia/Karachi, UTC+5, no daylight saving) as "YYYY-MM-DD" — TimeUtils.kt.
String todayKarachi() {
  final k = DateTime.now().toUtc().add(const Duration(hours: 5));
  return '${k.year.toString().padLeft(4, '0')}-${k.month.toString().padLeft(2, '0')}-${k.day.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------- users (User.kt)
class AppUser {
  AppUser({
    required this.uid,
    required this.name,
    required this.email,
    required this.employeeId,
    required this.department,
    required this.role,
    required this.accountStatus,
    required this.phone,
    required this.townshipLocation,
    required this.currentMode,
    required this.defaultRolePreference,
    required this.defaultDriverSeats,
    required this.muteUntilTimestamp,
    required this.isPasswordChanged,
    required this.createdAt,
    required this.blockedAt,
    required this.blockedBy,
    required this.blockReason,
    required this.removedAt,
    required this.removedBy,
    required this.removeReason,
    required this.approvalRequestedAt,
    required this.approvedAt,
    required this.approvedBy,
    required this.consentAcceptedAt,
    required this.consentVersion,
    required this.privacyNoticeVersion,
    required this.totalCo2SavedKg,
    required this.totalCompletedRides,
  });

  static const roleUser = 'USER';
  static const roleAdmin = 'ADMIN';
  static const statusActive = 'ACTIVE';
  static const statusPending = 'PENDING_APPROVAL';
  static const statusBlocked = 'BLOCKED';
  static const statusRemoved = 'REMOVED';
  static const modePassenger = 'PASSENGER';
  static const modeDriver = 'DRIVER';

  final String uid, name, email, employeeId, department, role, accountStatus, phone, townshipLocation;
  final String currentMode, defaultRolePreference;
  final int defaultDriverSeats, muteUntilTimestamp;
  final bool isPasswordChanged;
  final int createdAt, blockedAt, removedAt, approvalRequestedAt, approvedAt, consentAcceptedAt;
  final String blockedBy, blockReason, removedBy, removeReason, approvedBy;
  final int consentVersion, privacyNoticeVersion;
  final double totalCo2SavedKg;
  final int totalCompletedRides;

  bool get isAdmin => role == roleAdmin;
  bool get isActive => accountStatus == statusActive;
  bool get isPending => accountStatus == statusPending;
  bool get isBlocked => accountStatus == statusBlocked;
  bool get isRemoved => accountStatus == statusRemoved;
  bool get prefersDriver => defaultRolePreference == modeDriver;

  /// New profile exactly as AuthRepository.register / completeGoogleProfile write it.
  factory AppUser.fresh({
    required String uid,
    required String name,
    required String email,
    required String employeeId,
    required String department,
    required String townshipLocation,
    required String mode,
    required int defaultSeats,
    String phone = '',
  }) {
    final now = nowMs();
    final safeMode = mode.trim().toUpperCase() == modeDriver ? modeDriver : modePassenger;
    return AppUser(
      uid: uid, name: name.trim(), email: email.trim(), employeeId: employeeId.trim(), department: department,
      role: roleUser, accountStatus: statusPending, phone: phone.trim(), townshipLocation: townshipLocation,
      currentMode: safeMode, defaultRolePreference: safeMode, defaultDriverSeats: defaultSeats.clamp(1, 8),
      muteUntilTimestamp: 0, isPasswordChanged: true, createdAt: now, blockedAt: 0, blockedBy: '', blockReason: '',
      removedAt: 0, removedBy: '', removeReason: '', approvalRequestedAt: now, approvedAt: 0, approvedBy: '',
      consentAcceptedAt: now, consentVersion: 1, privacyNoticeVersion: 1, totalCo2SavedKg: 0, totalCompletedRides: 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'uid': uid, 'name': name, 'email': email, 'employeeId': employeeId, 'department': department,
        'role': role, 'accountStatus': accountStatus, 'phone': phone, 'townshipLocation': townshipLocation,
        'currentMode': currentMode, 'defaultRolePreference': defaultRolePreference,
        'defaultDriverSeats': defaultDriverSeats, 'muteUntilTimestamp': muteUntilTimestamp,
        'isPasswordChanged': isPasswordChanged, 'createdAt': createdAt, 'blockedAt': blockedAt,
        'blockedBy': blockedBy, 'blockReason': blockReason, 'removedAt': removedAt, 'removedBy': removedBy,
        'removeReason': removeReason, 'approvalRequestedAt': approvalRequestedAt, 'approvedAt': approvedAt,
        'approvedBy': approvedBy, 'consentAcceptedAt': consentAcceptedAt, 'consentVersion': consentVersion,
        'privacyNoticeVersion': privacyNoticeVersion, 'totalCo2SavedKg': totalCo2SavedKg,
        'totalCompletedRides': totalCompletedRides,
      };

  /// Tolerant parser matching User.fromSnapshot (role/status/mode normalised).
  static AppUser? fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    if (!doc.exists) return null;
    final d = doc.data() ?? {};
    final rawRole = str(d, ['role'], fallback: roleUser).toUpperCase();
    final role = rawRole == roleAdmin || boolOf(d, 'isAdmin') ? roleAdmin : roleUser;
    final rawStatus = str(d, ['accountStatus', 'status'], fallback: statusActive).toUpperCase();
    final status = const [statusPending, statusBlocked, statusRemoved].contains(rawStatus) ? rawStatus : statusActive;
    String mode = str(d, ['currentMode'], fallback: modePassenger).toUpperCase();
    final pref = str(d, ['defaultRolePreference'], fallback: modePassenger).toUpperCase();
    if (mode != modePassenger && mode != modeDriver) mode = (pref == modeDriver) ? modeDriver : modePassenger;
    return AppUser(
      uid: str(d, ['uid'], fallback: doc.id),
      name: str(d, ['name', 'displayName', 'fullName']),
      email: str(d, ['email']),
      employeeId: str(d, ['employeeId', 'empId']),
      department: str(d, ['department'], fallback: 'Administration'),
      role: role,
      accountStatus: status,
      phone: str(d, ['phone', 'phoneNumber']),
      townshipLocation: str(d, ['townshipLocation', 'location'], fallback: 'EMs'),
      currentMode: mode,
      defaultRolePreference: pref == modeDriver ? modeDriver : modePassenger,
      defaultDriverSeats: intOf(d, ['defaultDriverSeats', 'seats'], fallback: 3).clamp(1, 8),
      muteUntilTimestamp: millis(d, 'muteUntilTimestamp'),
      isPasswordChanged: boolOf(d, 'isPasswordChanged', fallback: true),
      createdAt: millis(d, 'createdAt'),
      blockedAt: millis(d, 'blockedAt'),
      blockedBy: str(d, ['blockedBy']),
      blockReason: str(d, ['blockReason']),
      removedAt: millis(d, 'removedAt'),
      removedBy: str(d, ['removedBy']),
      removeReason: str(d, ['removeReason']),
      approvalRequestedAt: millis(d, 'approvalRequestedAt'),
      approvedAt: millis(d, 'approvedAt'),
      approvedBy: str(d, ['approvedBy']),
      consentAcceptedAt: millis(d, 'consentAcceptedAt'),
      consentVersion: intOf(d, ['consentVersion'], fallback: 1),
      privacyNoticeVersion: intOf(d, ['privacyNoticeVersion'], fallback: 1),
      totalCo2SavedKg: dbl(d, ['totalCo2SavedKg', 'co2Saved', 'co2SavedKg']),
      totalCompletedRides: intOf(d, ['totalCompletedRides', 'completedRides']),
    );
  }
}

// ---------------------------------------------------------------- rides (Ride.kt)
class RideStatus {
  static const offline = 'OFFLINE';
  static const available = 'AVAILABLE';
  static const partiallyFull = 'PARTIALLY_FULL';
  static const full = 'FULL';
  static const started = 'RIDE_STARTED';
  static const completed = 'COMPLETED';
  static const cancelled = 'CANCELLED';
  static const expired = 'EXPIRED';
  static const active = [available, partiallyFull, full, started];
  static const open = [available, partiallyFull];
}

const int defaultExpiryMs = 18 * 3600 * 1000; // RideRepository.DEFAULT_EXPIRY_MILLIS

class Ride {
  Ride({
    required this.rideId,
    required this.driverId,
    required this.driverName,
    required this.driverPhone,
    required this.driverDepartment,
    required this.date,
    required this.pickupZone,
    required this.pickupSide,
    required this.customPickupLocation,
    required this.totalSeats,
    required this.availableSeats,
    required this.acceptedPassengerIds,
    required this.completedPassengerIds,
    required this.message,
    required this.status,
    required this.expiresAt,
    required this.creationSource,
    required this.createdAt,
    required this.updatedAt,
    required this.startedAt,
    required this.completedAt,
    required this.finalPassengerCount,
    required this.confirmedPassengerCount,
  });

  final String rideId, driverId, driverName, driverPhone, driverDepartment, date, pickupZone, pickupSide;
  final String customPickupLocation, message, status, creationSource;
  final int totalSeats, availableSeats, expiresAt, createdAt, updatedAt, startedAt, completedAt;
  final int finalPassengerCount, confirmedPassengerCount;
  final List<String> acceptedPassengerIds, completedPassengerIds;

  bool get isActive => RideStatus.active.contains(status);
  String get displayPickup =>
      (pickupSide == PickupSide.other && customPickupLocation.isNotEmpty) ? customPickupLocation : pickupZone;

  /// Full document, including the legacy fields the Android app writes for old readers.
  Map<String, dynamic> toMap() => {
        'rideId': rideId, 'driverId': driverId, 'driverName': driverName, 'driverPhone': driverPhone,
        'driverDepartment': driverDepartment, 'date': date, 'pickupZone': pickupZone, 'pickupSide': pickupSide,
        'customPickupLocation': customPickupLocation, 'totalSeats': totalSeats, 'availableSeats': availableSeats,
        'acceptedPassengerIds': acceptedPassengerIds, 'completedPassengerIds': completedPassengerIds,
        'message': message, 'status': status, 'expiresAt': expiresAt, 'creationSource': creationSource,
        'createdAt': createdAt, 'updatedAt': updatedAt, 'startedAt': startedAt, 'completedAt': completedAt,
        'finalPassengerCount': finalPassengerCount, 'confirmedPassengerCount': confirmedPassengerCount,
        'discoverable': true, 'commuteSlotId': '', 'originSide': '',
        'commuteWindow': 'Any', 'direction': MasterData.directionFor(pickupSide),
        'destinationZone': MasterData.destinationFor(pickupSide), 'pickupDetails': '',
      };

  static Ride fromMap(String id, Map<String, dynamic> d) => Ride(
        rideId: str(d, ['rideId'], fallback: id),
        driverId: str(d, ['driverId']),
        driverName: str(d, ['driverName']),
        driverPhone: str(d, ['driverPhone']),
        driverDepartment: str(d, ['driverDepartment']),
        date: str(d, ['date']),
        pickupZone: str(d, ['pickupZone'], fallback: 'EMs'),
        pickupSide: str(d, ['pickupSide'], fallback: PickupSide.township).toUpperCase(),
        customPickupLocation: str(d, ['customPickupLocation']),
        totalSeats: intOf(d, ['totalSeats'], fallback: 3),
        availableSeats: intOf(d, ['availableSeats'], fallback: 3),
        acceptedPassengerIds: strList(d, 'acceptedPassengerIds'),
        completedPassengerIds: strList(d, 'completedPassengerIds'),
        message: str(d, ['message']),
        status: str(d, ['status'], fallback: RideStatus.available),
        expiresAt: millis(d, 'expiresAt'),
        creationSource: str(d, ['creationSource'], fallback: 'APP'),
        createdAt: millis(d, 'createdAt'),
        updatedAt: millis(d, 'updatedAt'),
        startedAt: millis(d, 'startedAt'),
        completedAt: millis(d, 'completedAt'),
        finalPassengerCount: intOf(d, ['finalPassengerCount']),
        confirmedPassengerCount: intOf(d, ['confirmedPassengerCount']),
      );
  static Ride fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) => fromMap(doc.id, doc.data() ?? {});
}

// ---------------------------------------------------------------- passenger needs (PassengerNeed.kt)
class NeedStatus {
  static const looking = 'LOOKING';
  static const requested = 'REQUESTED';
  static const matched = 'MATCHED';
  static const completed = 'COMPLETED';
  static const cancelled = 'CANCELLED';
  static const expired = 'EXPIRED';
}

class PassengerNeed {
  PassengerNeed({
    required this.needId,
    required this.passengerId,
    required this.passengerName,
    required this.passengerDepartment,
    required this.passengerPhone,
    required this.date,
    required this.pickupZone,
    required this.pickupSide,
    required this.customPickupLocation,
    required this.message,
    required this.status,
    required this.expiresAt,
    required this.matchedDriverId,
    required this.matchedRideId,
    required this.createdAt,
    required this.updatedAt,
    required this.matchedAt,
  });
  final String needId, passengerId, passengerName, passengerDepartment, passengerPhone, date, pickupZone, pickupSide;
  final String customPickupLocation, message, status, matchedDriverId, matchedRideId;
  final int expiresAt, createdAt, updatedAt, matchedAt;

  String get displayPickup =>
      (pickupSide == PickupSide.other && customPickupLocation.isNotEmpty) ? customPickupLocation : pickupZone;

  Map<String, dynamic> toMap() => {
        'needId': needId, 'passengerId': passengerId, 'passengerName': passengerName,
        'passengerDepartment': passengerDepartment, 'passengerPhone': passengerPhone, 'date': date,
        'pickupZone': pickupZone, 'pickupSide': pickupSide, 'customPickupLocation': customPickupLocation,
        'message': message, 'status': status, 'expiresAt': expiresAt, 'matchedDriverId': matchedDriverId,
        'matchedRideId': matchedRideId, 'requestedRideId': '', 'createdAt': createdAt, 'updatedAt': updatedAt,
        'matchedAt': matchedAt, 'discoverable': true, 'commuteSlotId': '', 'originSide': '',
        'direction': MasterData.directionFor(pickupSide), 'commuteWindow': 'Any',
        'destinationZone': MasterData.destinationFor(pickupSide), 'pickupDetails': '',
      };

  static PassengerNeed fromMap(String id, Map<String, dynamic> d) => PassengerNeed(
        needId: str(d, ['needId'], fallback: id),
        passengerId: str(d, ['passengerId']),
        passengerName: str(d, ['passengerName']),
        passengerDepartment: str(d, ['passengerDepartment']),
        passengerPhone: str(d, ['passengerPhone']),
        date: str(d, ['date']),
        pickupZone: str(d, ['pickupZone'], fallback: 'EMs'),
        pickupSide: str(d, ['pickupSide'], fallback: PickupSide.township).toUpperCase(),
        customPickupLocation: str(d, ['customPickupLocation']),
        message: str(d, ['message']),
        status: str(d, ['status'], fallback: NeedStatus.looking),
        expiresAt: millis(d, 'expiresAt'),
        matchedDriverId: str(d, ['matchedDriverId']),
        matchedRideId: str(d, ['matchedRideId']),
        createdAt: millis(d, 'createdAt'),
        updatedAt: millis(d, 'updatedAt'),
        matchedAt: millis(d, 'matchedAt'),
      );
  static PassengerNeed fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) => fromMap(doc.id, doc.data() ?? {});
}

// ---------------------------------------------------------------- ride requests (RideRequest.kt)
class ReqStatus {
  static const requested = 'REQUESTED';
  static const accepted = 'ACCEPTED';
  static const rejected = 'REJECTED';
  static const cancelled = 'CANCELLED';
  static const cancelledByPassenger = 'CANCELLED_BY_PASSENGER';
  static const cancelledByDriver = 'CANCELLED_BY_DRIVER';
  static const closedUnconfirmed = 'CLOSED_UNCONFIRMED';
  static const expired = 'EXPIRED';
  static const completed = 'COMPLETED';
  static const activeStatuses = [accepted, 'RIDE_STARTED'];
  static const terminal = [completed, cancelledByPassenger, cancelledByDriver, closedUnconfirmed];
}

class RideRequest {
  RideRequest({
    required this.requestId,
    required this.rideId,
    required this.needId,
    required this.passengerId,
    required this.passengerName,
    required this.passengerPhone,
    required this.passengerDepartment,
    required this.driverId,
    required this.driverName,
    required this.driverDepartment,
    required this.driverPhone,
    required this.date,
    required this.direction,
    required this.commuteWindow,
    required this.pickupZone,
    required this.customPickupLocation,
    required this.destinationZone,
    required this.status,
    required this.message,
    required this.requestedAt,
    required this.responseAt,
    required this.passengerCompletedAt,
  });
  final String requestId, rideId, needId, passengerId, passengerName, passengerPhone, passengerDepartment;
  final String driverId, driverName, driverDepartment, driverPhone, date, direction, commuteWindow;
  final String pickupZone, customPickupLocation, destinationZone, status, message;
  final int requestedAt, responseAt, passengerCompletedAt;

  String get displayPickup => customPickupLocation.isNotEmpty ? customPickupLocation : pickupZone;
  bool get isActive => ReqStatus.activeStatuses.contains(status);

  Map<String, dynamic> toMap() => {
        'requestId': requestId, 'rideId': rideId, 'needId': needId, 'passengerId': passengerId,
        'passengerName': passengerName, 'passengerPhone': passengerPhone, 'passengerDepartment': passengerDepartment,
        'driverId': driverId, 'driverName': driverName, 'driverDepartment': driverDepartment,
        'driverPhone': driverPhone, 'date': date, 'direction': direction, 'commuteWindow': commuteWindow,
        'pickupZone': pickupZone, 'customPickupLocation': customPickupLocation, 'destinationZone': destinationZone,
        'status': status, 'pickupDetails': '', 'message': message, 'requestedAt': requestedAt,
        'responseAt': responseAt, 'passengerCompletedAt': passengerCompletedAt,
      };

  static RideRequest fromMap(String id, Map<String, dynamic> d) => RideRequest(
        requestId: str(d, ['requestId'], fallback: id),
        rideId: str(d, ['rideId']),
        needId: str(d, ['needId']),
        passengerId: str(d, ['passengerId']),
        passengerName: str(d, ['passengerName']),
        passengerPhone: str(d, ['passengerPhone']),
        passengerDepartment: str(d, ['passengerDepartment']),
        driverId: str(d, ['driverId']),
        driverName: str(d, ['driverName']),
        driverDepartment: str(d, ['driverDepartment']),
        driverPhone: str(d, ['driverPhone']),
        date: str(d, ['date']),
        direction: str(d, ['direction']),
        commuteWindow: str(d, ['commuteWindow']),
        pickupZone: str(d, ['pickupZone']),
        customPickupLocation: str(d, ['customPickupLocation']),
        destinationZone: str(d, ['destinationZone']),
        status: str(d, ['status'], fallback: ReqStatus.accepted),
        message: str(d, ['message']),
        requestedAt: millis(d, 'requestedAt'),
        responseAt: millis(d, 'responseAt'),
        passengerCompletedAt: millis(d, 'passengerCompletedAt'),
      );
  static RideRequest fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) => fromMap(doc.id, doc.data() ?? {});
}

// ---------------------------------------------------------------- config, leaderboard, reports, audit
class SustainabilityConfig {
  const SustainabilityConfig({this.baselineDistanceKm = 3.0, this.co2FactorKgPerKm = 0.12});
  final double baselineDistanceKm, co2FactorKgPerKm;
  static SustainabilityConfig fromDoc(DocumentSnapshot<Map<String, dynamic>>? doc) {
    final d = doc?.data();
    if (d == null) return const SustainabilityConfig();
    return SustainabilityConfig(
      baselineDistanceKm: dbl(d, ['baselineDistanceKm'], fallback: 3.0),
      co2FactorKgPerKm: dbl(d, ['co2FactorKgPerKm'], fallback: 0.12),
    );
  }
}

class LeaderboardEntry {
  const LeaderboardEntry({required this.uid, required this.name, required this.department, required this.co2SavedKg, required this.rideCount, required this.rank});
  final String uid, name, department;
  final double co2SavedKg;
  final int rideCount, rank;
  Map<String, dynamic> toMap() => {'uid': uid, 'name': name, 'department': department, 'co2SavedKg': co2SavedKg, 'rideCount': rideCount, 'rank': rank};
  LeaderboardEntry copyWith({double? co2SavedKg, int? rideCount, int? rank}) =>
      LeaderboardEntry(uid: uid, name: name, department: department, co2SavedKg: co2SavedKg ?? this.co2SavedKg, rideCount: rideCount ?? this.rideCount, rank: rank ?? this.rank);

  /// Top 3 by CO₂ as AdminRepository.parseLeaderboardEntries does.
  static List<LeaderboardEntry> parse(DocumentSnapshot<Map<String, dynamic>>? doc) {
    final raw = (doc?.data()?['entries'] as List?) ?? const [];
    final list = <LeaderboardEntry>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final co2 = dbl(m, ['co2SavedKg']);
      if (co2 <= 0) continue;
      list.add(LeaderboardEntry(uid: str(m, ['uid']), name: str(m, ['name'], fallback: 'Contributor'), department: str(m, ['department'], fallback: 'Operations'), co2SavedKg: co2, rideCount: intOf(m, ['rideCount']), rank: intOf(m, ['rank'], fallback: 1)));
    }
    list.sort((a, b) => b.co2SavedKg.compareTo(a.co2SavedKg));
    return [for (var i = 0; i < list.length && i < 3; i++) list[i].copyWith(rank: i + 1)];
  }
}

class ManagementReportRow {
  const ManagementReportRow({required this.serialNumber, required this.personName, required this.co2Saved, required this.ridesAsDriver, required this.ridesAsPassenger});
  final int serialNumber, ridesAsDriver, ridesAsPassenger;
  final String personName;
  final double co2Saved;
  Map<String, dynamic> toMap() => {'serialNumber': serialNumber, 'personName': personName, 'co2Saved': co2Saved, 'ridesAsDriver': ridesAsDriver, 'ridesAsPassenger': ridesAsPassenger};
}

class ManagementReport {
  const ManagementReport({this.rows = const [], this.totalMembers = 0, this.totalCo2Saved = 0, this.totalDriverRides = 0, this.totalPassengerRides = 0, this.updatedAt = 0});
  final List<ManagementReportRow> rows;
  final int totalMembers, totalDriverRides, totalPassengerRides, updatedAt;
  final double totalCo2Saved;

  static ManagementReport fromDoc(DocumentSnapshot<Map<String, dynamic>>? doc) {
    final d = doc?.data();
    if (d == null) return const ManagementReport();
    final raw = (d['rows'] as List?) ?? const [];
    final rows = <ManagementReportRow>[];
    for (var i = 0; i < raw.length; i++) {
      final e = raw[i];
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      rows.add(ManagementReportRow(serialNumber: intOf(m, ['serialNumber'], fallback: i + 1), personName: str(m, ['personName'], fallback: 'User'), co2Saved: dbl(m, ['co2Saved']), ridesAsDriver: intOf(m, ['ridesAsDriver']), ridesAsPassenger: intOf(m, ['ridesAsPassenger'])));
    }
    final total = dbl(d, ['totalCo2Saved']);
    return ManagementReport(
      rows: rows,
      totalMembers: intOf(d, ['totalMembers']) > 0 ? intOf(d, ['totalMembers']) : rows.length,
      totalCo2Saved: total > 0 ? total : rows.fold(0.0, (s, r) => s + r.co2Saved),
      totalDriverRides: intOf(d, ['totalDriverRides']),
      totalPassengerRides: intOf(d, ['totalPassengerRides']),
      updatedAt: millis(d, 'updatedAt'),
    );
  }
}

class AuditLog {
  const AuditLog({required this.auditId, required this.adminUid, required this.adminName, required this.adminEmail, required this.targetUid, required this.targetName, required this.targetEmail, required this.action, required this.reason, required this.timestamp});
  final String auditId, adminUid, adminName, adminEmail, targetUid, targetName, targetEmail, action, reason;
  final int timestamp;

  static const blockMember = 'BLOCK_MEMBER';
  static const unblockMember = 'UNBLOCK_MEMBER';
  static const removeMember = 'REMOVE_MEMBER';
  static const roleChange = 'ROLE_CHANGE';
  static const approveUser = 'APPROVE_USER';

  Map<String, dynamic> toMap() => {'auditId': auditId, 'adminUid': adminUid, 'adminName': adminName, 'adminEmail': adminEmail, 'targetUid': targetUid, 'targetName': targetName, 'targetEmail': targetEmail, 'action': action, 'reason': reason, 'timestamp': timestamp};
  static AuditLog fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return AuditLog(auditId: str(d, ['auditId'], fallback: doc.id), adminUid: str(d, ['adminUid']), adminName: str(d, ['adminName']), adminEmail: str(d, ['adminEmail']), targetUid: str(d, ['targetUid']), targetName: str(d, ['targetName']), targetEmail: str(d, ['targetEmail']), action: str(d, ['action']), reason: str(d, ['reason']), timestamp: millis(d, 'timestamp'));
  }
}

/// What the passenger side of Home shows (PassengerEligibility.kt).
sealed class PassengerState {
  const PassengerState();
}
class PassengerLoading extends PassengerState { const PassengerLoading(); }
class PassengerFree extends PassengerState { const PassengerFree(); }
class PassengerLooking extends PassengerState { const PassengerLooking(this.need); final PassengerNeed need; }
class PassengerRiding extends PassengerState { const PassengerRiding(this.request); final RideRequest request; }
