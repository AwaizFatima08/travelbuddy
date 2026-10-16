// Live approach for a locked ride (§7): shares my position with the other people in the ride,
// watches theirs, and fires ONE approaching alert. On Android the position stream runs inside a
// foreground service (visible notification), so it keeps working with the screen off.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../app/widgets.dart';
import '../core/models.dart';
import '../core/repo.dart';
import 'push.dart';

class LiveShare {
  LiveShare._();
  static final LiveShare I = LiveShare._();

  final ValueNotifier<String?> activeRideId = ValueNotifier(null);
  final ValueNotifier<Position?> myPosition = ValueNotifier(null);

  StreamSubscription<Position>? _pos;
  StreamSubscription<Ride?>? _ride;
  StreamSubscription<List<LivePosition>>? _live;
  DateTime? _lastWrite;
  Position? _lastWritten;
  bool _alerted = false;
  Timer? _autoStop;
  String? _myUid;

  static Future<bool> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    return p == LocationPermission.always || p == LocationPermission.whileInUse;
  }

  Future<bool> start(Ride ride, String myUid) async {
    if (activeRideId.value == ride.id) return true;
    await stop();
    if (!await ensurePermission()) return false;
    _myUid = myUid;
    _alerted = false;
    activeRideId.value = ride.id;

    final settings = kIsWeb
        ? const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 15)
        : AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 15,
            intervalDuration: const Duration(seconds: 10),
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'TravelBuddy ride',
              notificationText: 'Sharing your position with your ride until pickup',
              notificationIcon: AndroidResource(name: 'ic_stat_car', defType: 'drawable'),
              enableWakeLock: true,
              setOngoing: true,
            ),
          );
    _pos = Geolocator.getPositionStream(locationSettings: settings).listen(_onPosition, onError: (_) {});
    try {
      final p = await Geolocator.getCurrentPosition();
      _onPosition(p);
    } catch (_) {}

    _ride = Repo.I.rideStream(ride.id).listen((r) {
      final isDriver = r?.driverId == myUid;
      final allPickedUp = r != null && r.passengers.isNotEmpty && r.passengers.values.every((p) => p.pickedUp);
      if (r == null || !r.isActive || (r.passengers[myUid]?.pickedUp ?? false) || (isDriver && allPickedUp)) stop();
    });
    _live = Repo.I.liveStream(ride.id).listen((list) => _checkApproach(ride, list));
    // Safety net: never share for more than 45 minutes.
    _autoStop = Timer(const Duration(minutes: 45), stop);
    return true;
  }

  void _onPosition(Position p) {
    myPosition.value = p;
    final id = activeRideId.value;
    if (id == null) return;
    final now = DateTime.now();
    final moved = _lastWritten == null ||
        distanceMeters(_lastWritten!.latitude, _lastWritten!.longitude, p.latitude, p.longitude) >= 20;
    final due = _lastWrite == null || now.difference(_lastWrite!).inSeconds >= 10;
    if (moved && due) {
      _lastWrite = now;
      _lastWritten = p;
      Repo.I.writeLive(id, p.latitude, p.longitude);
    }
  }

  void _checkApproach(Ride ride, List<LivePosition> list) {
    if (_alerted || _myUid == null) return;
    final me = myPosition.value;
    if (me == null) return;
    final isDriver = ride.driverId == _myUid;
    for (final o in list) {
      if (o.uid == _myUid) continue;
      if (isDriver && !ride.passengers.containsKey(o.uid)) continue;
      if (!isDriver && o.uid != ride.driverId) continue;
      final d = distanceMeters(me.latitude, me.longitude, o.lat, o.lng);
      if (isApproaching(d)) {
        _alerted = true;
        final who = isDriver ? (ride.passengers[o.uid]?.name ?? 'Passenger') : ride.driverName;
        PushService.I.show(
          isDriver ? '$who is close by' : 'Your ride is ~1 min away',
          '$who is ${etaText(d)} from you.',
          payload: '${ride.id}|',
          id: 7,
        );
        break;
      }
    }
  }

  Future<void> stop() async {
    final id = activeRideId.value;
    _autoStop?.cancel();
    await _pos?.cancel();
    await _ride?.cancel();
    await _live?.cancel();
    _pos = null;
    _ride = null;
    _live = null;
    _lastWrite = null;
    _lastWritten = null;
    activeRideId.value = null;
    if (id != null) await Repo.I.clearLive(id);
  }
}
