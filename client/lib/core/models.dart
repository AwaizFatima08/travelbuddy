// Data model for TravelBuddy v2 — mirrors docs/DESIGN-v2.md §11.
// Mapping is done by hand (no code generation) so the app stays simple to read.
import 'package:cloud_firestore/cloud_firestore.dart';

enum AccountStatus { pending, active, blocked }

enum PostKind { offer, request }

enum PostStatus { open, full, closed, cancelled }

enum RideStatus { locked, pickedUp, completed, cancelled, noShow }

enum Side { township, plant }

/// Which way a post or ride goes. Stored as TO_PLANT / TO_TOWNSHIP.
enum Direction {
  toPlant,
  toTownship;

  Side get from => this == Direction.toPlant ? Side.township : Side.plant;
  Side get to => this == Direction.toPlant ? Side.plant : Side.township;
  String get label => this == Direction.toPlant ? 'Township → Plant' : 'Plant → Township';
  Direction get opposite => this == Direction.toPlant ? Direction.toTownship : Direction.toPlant;
}

T _enumOr<T extends Enum>(List<T> values, Object? raw, T fallback) {
  if (raw is! String) return fallback;
  final want = raw.replaceAll('_', '').toUpperCase();
  for (final v in values) {
    if (v.name == raw || v.name.toUpperCase() == want) return v;
  }
  return fallback;
}

String enumName(Enum e) => switch (e) {
      Direction.toPlant => 'TO_PLANT',
      Direction.toTownship => 'TO_TOWNSHIP',
      _ => e.name.toUpperCase(),
    };

/// A pickup / drop landmark, e.g. "E-Type End" or "CCR Parking".
class Place {
  const Place({
    required this.id,
    required this.name,
    required this.side,
    this.lat = 0,
    this.lng = 0,
    this.active = true,
    this.order = 0,
    this.neighbours = const [],
  });

  final String id;
  final String name;
  final Side side;
  final double lat;
  final double lng;
  final bool active;
  final int order;

  /// Ids of places close enough to share a pickup (e.g. E-Type End ↔ E-Modified Parking).
  final List<String> neighbours;

  bool get hasPoint => lat != 0 || lng != 0;

  factory Place.fromMap(Map<String, dynamic> m) => Place(
        id: m['id'] as String? ?? '',
        name: m['name'] as String? ?? '',
        side: _enumOr(Side.values, m['side'], Side.township),
        lat: (m['lat'] as num?)?.toDouble() ?? 0,
        lng: (m['lng'] as num?)?.toDouble() ?? 0,
        active: m['active'] as bool? ?? true,
        order: (m['order'] as num?)?.toInt() ?? 0,
        neighbours: (m['neighbours'] as List?)?.cast<String>() ?? const [],
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'side': enumName(side),
        'lat': lat,
        'lng': lng,
        'active': active,
        'order': order,
        'neighbours': neighbours,
      };

  Place copyWith({
    String? name,
    Side? side,
    double? lat,
    double? lng,
    bool? active,
    int? order,
    List<String>? neighbours,
  }) =>
      Place(
        id: id,
        name: name ?? this.name,
        side: side ?? this.side,
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
        active: active ?? this.active,
        order: order ?? this.order,
        neighbours: neighbours ?? this.neighbours,
      );
}

/// A commute window, e.g. Morning 07:00–07:40 township → plant. Times are "HH:mm" site-local.
class CommuteWindow {
  const CommuteWindow({
    required this.id,
    required this.name,
    required this.from,
    required this.to,
    required this.start,
    required this.end,
    this.active = true,
    this.order = 0,
  });

  final String id;
  final String name;
  final Side from;
  final Side to;
  final String start;
  final String end;
  final bool active;
  final int order;

  factory CommuteWindow.fromMap(Map<String, dynamic> m) => CommuteWindow(
        id: m['id'] as String? ?? '',
        name: m['name'] as String? ?? '',
        from: _enumOr(Side.values, m['from'], Side.township),
        to: _enumOr(Side.values, m['to'], Side.plant),
        start: m['start'] as String? ?? '00:00',
        end: m['end'] as String? ?? '00:00',
        active: m['active'] as bool? ?? true,
        order: (m['order'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'from': enumName(from),
        'to': enumName(to),
        'start': start,
        'end': end,
        'active': active,
        'order': order,
      };

  String get label => '$name $start–$end';
  String get directionLabel => from == Side.township ? 'Township → Plant' : 'Plant → Township';
}

/// A location where the app is used (FFL Township ⇄ Plant first). Everything site-specific lives here.
class Site {
  const Site({
    required this.id,
    required this.name,
    this.timezone = 'Asia/Karachi',
    this.places = const [],
    this.windows = const [],
    this.legKm = 2.5,
    this.co2PerKm = 0.17,
    this.matchMinutes = 15,
  });

  final String id;
  final String name;
  final String timezone;
  final List<Place> places;
  final List<CommuteWindow> windows;

  /// Typical trip length and CO₂ per km, used for the "kg saved" figure.
  final double legKm;
  final double co2PerKm;

  /// Posts within ± this many minutes match each other.
  final int matchMinutes;

  double get kgPerPassengerLeg => legKm * co2PerKm;

  Place? place(String id) {
    for (final p in places) {
      if (p.id == id) return p;
    }
    return null;
  }

  CommuteWindow? window(String id) {
    for (final w in windows) {
      if (w.id == id) return w;
    }
    return null;
  }

  List<Place> placesOn(Side side) =>
      places.where((p) => p.active && p.side == side).toList()..sort((a, b) => a.order.compareTo(b.order));

  factory Site.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return Site(
      id: d.id,
      name: m['name'] as String? ?? d.id,
      timezone: m['timezone'] as String? ?? 'Asia/Karachi',
      places: ((m['places'] as List?) ?? const [])
          .map((e) => Place.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order)),
      windows: ((m['windows'] as List?) ?? const [])
          .map((e) => CommuteWindow.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order)),
      legKm: (m['legKm'] as num?)?.toDouble() ?? 2.5,
      co2PerKm: (m['co2PerKm'] as num?)?.toDouble() ?? 0.17,
      matchMinutes: (m['matchMinutes'] as num?)?.toInt() ?? 15,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'timezone': timezone,
        'places': places.map((p) => p.toMap()).toList(),
        'windows': windows.map((w) => w.toMap()).toList(),
        'legKm': legKm,
        'co2PerKm': co2PerKm,
        'matchMinutes': matchMinutes,
      };
}

class AuditEntry {
  const AuditEntry({required this.action, required this.by, required this.byName, this.at, this.reason = ''});
  final String action;
  final String by;
  final String byName;
  final DateTime? at;
  final String reason;

  factory AuditEntry.fromMap(Map<String, dynamic> m) => AuditEntry(
        action: m['action'] as String? ?? '',
        by: m['by'] as String? ?? '',
        byName: m['byName'] as String? ?? '',
        at: (m['at'] as Timestamp?)?.toDate(),
        reason: m['reason'] as String? ?? '',
      );
}

class UserProfile {
  const UserProfile({
    required this.uid,
    required this.name,
    required this.email,
    required this.phone,
    required this.employeeId,
    required this.department,
    required this.townshipLocation,
    required this.hasCar,
    required this.siteId,
    required this.status,
    required this.role,
    this.audit = const [],
    this.lastRole,
    this.points = 0,
    this.noShows = 0,
    this.reminders = const {},
    this.driverRides = 0,
    this.passengerRides = 0,
    this.deviceCount = 0,
  });

  final String uid;
  final String name;
  final String email;
  final String phone;
  final String employeeId;
  final String department;
  final String townshipLocation;
  final bool hasCar;
  final String siteId;
  final AccountStatus status;
  final String role;
  final List<AuditEntry> audit;

  /// "driver" or "passenger" — pre-selected on the home screen.
  final String? lastRole;

  /// Running totals written by the server (points ledger).
  final int points;
  final int noShows;

  /// Per-slot commute reminders (windowId → on), Mon–Fri.
  final Map<String, bool> reminders;

  /// Completed-ride counters (server-written).
  final int driverRides;
  final int passengerRides;

  /// Number of push-registered devices (fcmTokens map size).
  final int deviceCount;

  bool get isAdmin => role == 'ADMIN' && status == AccountStatus.active;

  factory UserProfile.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return UserProfile(
      uid: d.id,
      name: m['name'] as String? ?? '',
      email: m['email'] as String? ?? '',
      phone: m['phone'] as String? ?? '',
      employeeId: m['employeeId'] as String? ?? '',
      department: m['department'] as String? ?? '',
      townshipLocation: m['townshipLocation'] as String? ?? '',
      hasCar: m['hasCar'] as bool? ?? false,
      siteId: m['siteId'] as String? ?? 'ffl',
      status: _enumOr(AccountStatus.values, m['accountStatus'], AccountStatus.pending),
      role: m['role'] as String? ?? 'USER',
      audit: ((m['audit'] as List?) ?? const [])
          .map((e) => AuditEntry.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      lastRole: m['lastRole'] as String?,
      points: (m['points'] as num?)?.toInt() ?? 0,
      noShows: (m['noShows'] as num?)?.toInt() ?? 0,
      reminders: Map<String, bool>.from(((m['reminders'] as Map?) ?? const {}).map((k, v) => MapEntry(k as String, v == true))),
      driverRides: (((m['stats'] as Map?) ?? const {})['driverRides'] as num?)?.toInt() ?? 0,
      passengerRides: (((m['stats'] as Map?) ?? const {})['passengerRides'] as num?)?.toInt() ?? 0,
      deviceCount: ((m['fcmTokens'] as Map?) ?? const {}).length,
    );
  }
}

/// A ride offer (driver) or ride request (passenger) for one window on one date.
class Post {
  const Post({
    required this.id,
    required this.siteId,
    required this.kind,
    required this.userId,
    required this.userName,
    required this.userPhone,
    required this.direction,
    required this.windowId,
    required this.date,
    required this.departAt,
    required this.fromPlaceId,
    required this.toPlaceId,
    required this.seats,
    required this.seatsLeft,
    required this.status,
    this.autoAccept = true,
    this.note = '',
    this.rideId,
    this.createdAt,
    this.cancelReason = '',
  });

  final String id;
  final String siteId;
  final PostKind kind;
  final String userId;
  final String userName;
  final String userPhone;
  final Direction direction;

  /// Decided slot the leaving time falls in, or "other" (shift / off-slot ride). Set by the server.
  final String windowId;

  /// "YYYY-MM-DD" in site-local time.
  final String date;
  final DateTime departAt;
  final String fromPlaceId;
  final String toPlaceId;
  final int seats;
  final int seatsLeft;
  final PostStatus status;

  /// Driver setting: a passenger who joins is locked in immediately.
  final bool autoAccept;
  final String note;

  /// For a REQUEST: the ride it was locked into, once matched.
  final String? rideId;
  final DateTime? createdAt;
  final String cancelReason;

  bool get isOffer => kind == PostKind.offer;
  bool get isOpen => status == PostStatus.open;

  factory Post.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return Post(
      id: d.id,
      siteId: m['siteId'] as String? ?? 'ffl',
      kind: _enumOr(PostKind.values, m['kind'], PostKind.request),
      userId: m['userId'] as String? ?? '',
      userName: m['userName'] as String? ?? '',
      userPhone: m['userPhone'] as String? ?? '',
      direction: _enumOr(Direction.values, m['direction'], Direction.toPlant),
      windowId: m['windowId'] as String? ?? 'other',
      date: m['date'] as String? ?? '',
      departAt: (m['departAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      fromPlaceId: m['fromPlaceId'] as String? ?? '',
      toPlaceId: m['toPlaceId'] as String? ?? '',
      seats: (m['seats'] as num?)?.toInt() ?? 1,
      seatsLeft: (m['seatsLeft'] as num?)?.toInt() ?? 1,
      status: _enumOr(PostStatus.values, m['status'], PostStatus.open),
      autoAccept: m['autoAccept'] as bool? ?? true,
      note: m['note'] as String? ?? '',
      rideId: m['rideId'] as String?,
      createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
      cancelReason: m['cancelReason'] as String? ?? '',
    );
  }
}

class RidePassenger {
  const RidePassenger({
    required this.uid,
    required this.name,
    required this.phone,
    required this.pickupPlaceId,
    this.postId,
    this.pickedUp = false,
    this.arrived = false,
  });
  final String uid;
  final String name;
  final String phone;
  final String pickupPlaceId;
  final String? postId;
  final bool pickedUp;
  final bool arrived;

  factory RidePassenger.fromMap(String uid, Map<String, dynamic> m) => RidePassenger(
        uid: uid,
        name: m['name'] as String? ?? '',
        phone: m['phone'] as String? ?? '',
        pickupPlaceId: m['pickupPlaceId'] as String? ?? '',
        postId: m['postId'] as String?,
        pickedUp: m['pickedUp'] as bool? ?? false,
        arrived: m['arrived'] as bool? ?? false,
      );
}

/// A locked ride: one driver, one or more passengers. Created only by the server.
class Ride {
  const Ride({
    required this.id,
    required this.siteId,
    required this.driverId,
    required this.driverName,
    required this.driverPhone,
    required this.offerPostId,
    required this.direction,
    required this.windowId,
    required this.date,
    required this.departAt,
    required this.fromPlaceId,
    required this.toPlaceId,
    required this.status,
    required this.passengers,
    required this.participantIds,
    this.startedAt,
    this.completedAt,
    this.noShowReports = const {},
    this.cancelReason = '',
  });

  final String id;
  final String siteId;
  final String driverId;
  final String driverName;
  final String driverPhone;
  final String offerPostId;
  final Direction direction;
  final String windowId;
  final String date;
  final DateTime departAt;
  final String fromPlaceId;
  final String toPlaceId;
  final RideStatus status;
  final Map<String, RidePassenger> passengers;
  final List<String> participantIds;
  final DateTime? startedAt;
  final DateTime? completedAt;

  /// uid reported → {by, at, disputed, resolved}
  final Map<String, dynamic> noShowReports;
  final String cancelReason;

  bool isDriver(String uid) => driverId == uid;
  bool isPassenger(String uid) => passengers.containsKey(uid);
  bool get isFinished =>
      status == RideStatus.completed || status == RideStatus.cancelled || status == RideStatus.noShow;
  bool get isActive => status == RideStatus.locked || status == RideStatus.pickedUp;

  factory Ride.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    final raw = (m['passengers'] as Map?) ?? const {};
    return Ride(
      id: d.id,
      siteId: m['siteId'] as String? ?? 'ffl',
      driverId: m['driverId'] as String? ?? '',
      driverName: m['driverName'] as String? ?? '',
      driverPhone: m['driverPhone'] as String? ?? '',
      offerPostId: m['offerPostId'] as String? ?? '',
      direction: _enumOr(Direction.values, m['direction'], Direction.toPlant),
      windowId: m['windowId'] as String? ?? 'other',
      date: m['date'] as String? ?? '',
      departAt: (m['departAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      fromPlaceId: m['fromPlaceId'] as String? ?? '',
      toPlaceId: m['toPlaceId'] as String? ?? '',
      status: _enumOr(RideStatus.values, m['status'], RideStatus.locked),
      passengers: raw.map((k, v) =>
          MapEntry(k as String, RidePassenger.fromMap(k, Map<String, dynamic>.from(v as Map)))),
      participantIds: (m['participantIds'] as List?)?.cast<String>() ?? const [],
      startedAt: (m['startedAt'] as Timestamp?)?.toDate(),
      completedAt: (m['completedAt'] as Timestamp?)?.toDate(),
      noShowReports: Map<String, dynamic>.from((m['noShowReports'] as Map?) ?? const {}),
      cancelReason: m['cancelReason'] as String? ?? '',
    );
  }
}

/// A live position shared between the people in one ride (rides/{id}/live/{uid}).
class LivePosition {
  const LivePosition({required this.uid, required this.lat, required this.lng, this.at});
  final String uid;
  final double lat;
  final double lng;
  final DateTime? at;

  factory LivePosition.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return LivePosition(
      uid: d.id,
      lat: (m['lat'] as num?)?.toDouble() ?? 0,
      lng: (m['lng'] as num?)?.toDouble() ?? 0,
      at: (m['at'] as Timestamp?)?.toDate(),
    );
  }
}

/// One line in the points ledger (server-written).
class PointsEntry {
  const PointsEntry({required this.id, required this.delta, required this.reason, this.rideId, this.at});
  final String id;
  final int delta;
  final String reason;
  final String? rideId;
  final DateTime? at;

  factory PointsEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return PointsEntry(
      id: d.id,
      delta: (m['delta'] as num?)?.toInt() ?? 0,
      reason: m['reason'] as String? ?? '',
      rideId: m['rideId'] as String?,
      at: (m['at'] as Timestamp?)?.toDate(),
    );
  }
}

/// An in-app notification (notifications/{uid}/items/{id}).
class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    this.rideId,
    this.postId,
    this.at,
    this.read = false,
  });
  final String id;
  final String title;
  final String body;
  final String? rideId;
  final String? postId;
  final DateTime? at;
  final bool read;

  factory AppNotification.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return AppNotification(
      id: d.id,
      title: m['title'] as String? ?? '',
      body: m['body'] as String? ?? '',
      rideId: m['rideId'] as String?,
      postId: m['postId'] as String?,
      at: (m['at'] as Timestamp?)?.toDate(),
      read: m['read'] as bool? ?? false,
    );
  }
}

/// Monthly leaderboard row (monthly/{siteId_YYYY-MM}.users[uid]).
class MonthlyRow {
  const MonthlyRow({
    required this.uid,
    required this.name,
    required this.department,
    required this.points,
    required this.driverLegs,
    required this.passengerLegs,
    required this.kgSaved,
    this.driverRides = 0,
    this.passengerRides = 0,
  });
  final String uid;
  final String name;
  final String department;
  final int points;
  final int driverLegs;
  final int passengerLegs;
  final double kgSaved;
  final int driverRides;
  final int passengerRides;

  factory MonthlyRow.fromMap(String uid, Map<String, dynamic> m) => MonthlyRow(
        uid: uid,
        name: m['name'] as String? ?? '',
        department: m['department'] as String? ?? '',
        points: (m['points'] as num?)?.toInt() ?? 0,
        driverLegs: (m['driverLegs'] as num?)?.toInt() ?? 0,
        passengerLegs: (m['passengerLegs'] as num?)?.toInt() ?? 0,
        kgSaved: (m['kgSaved'] as num?)?.toDouble() ?? 0,
        driverRides: (m['driverRides'] as num?)?.toInt() ?? 0,
        passengerRides: (m['passengerRides'] as num?)?.toInt() ?? 0,
      );
}

/// Default FFL site data, created once by the admin ("Create FFL site"). Coordinates are
/// captured on site later with the places editor.
Site defaultFflSite() {
  Place p(String id, String name, Side side, int order, [List<String> nb = const []]) =>
      Place(id: id, name: name, side: side, order: order, neighbours: nb);
  CommuteWindow w(String id, String name, Side from, Side to, String s, String e, int o) =>
      CommuteWindow(id: id, name: name, from: from, to: to, start: s, end: e, order: o);
  return Site(
    id: 'ffl',
    name: 'FFL Township ⇄ Plant',
    places: [
      p('d_type_ground', 'D-Type Play Ground', Side.township, 0, ['e_type_end']),
      p('e_type_end', 'E-Type End', Side.township, 1, ['e_mod_parking', 'd_type_ground']),
      p('e_mod_parking', 'E-Modified Parking', Side.township, 2, ['e_type_end']),
      p('mosque_rbt', 'Mosque Roundabout', Side.township, 3, ['boq_parking']),
      p('boq_parking', 'BOQ Parking', Side.township, 4, ['mosque_rbt']),
      p('admin_bldg', 'Admin Building', Side.plant, 10, ['ccr_parking']),
      p('ccr_parking', 'CCR Parking', Side.plant, 11, ['admin_bldg', 'mcr_parking']),
      p('mcr_parking', 'MCR Parking', Side.plant, 12, ['ccr_parking']),
      p('ldc', 'L&DC', Side.plant, 13),
      p('workshop_parking', 'Workshop Parking', Side.plant, 14, ['warehouse_parking']),
      p('warehouse_parking', 'Warehouse Parking', Side.plant, 15, ['workshop_parking']),
      p('hse_bldg', 'HSE Building', Side.plant, 16, ['laboratory']),
      p('laboratory', 'Laboratory', Side.plant, 17, ['hse_bldg']),
    ],
    windows: [
      w('morning', 'Morning', Side.township, Side.plant, '07:00', '07:40', 0),
      w('lunch_out', 'Lunch out', Side.plant, Side.township, '12:45', '13:15', 1),
      w('lunch_in', 'Lunch in', Side.township, Side.plant, '14:00', '14:30', 2),
      w('evening', 'Evening', Side.plant, Side.township, '17:15', '18:00', 3),
    ],
  );
}
