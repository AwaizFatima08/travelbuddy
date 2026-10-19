// One locked ride: people, live approach, pickup / complete / cancel / no-show.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/widgets.dart';
import '../../core/clock.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../services/live_share.dart';

class RideScreen extends StatefulWidget {
  const RideScreen(this.rideId, {super.key});
  final String rideId;
  @override
  State<RideScreen> createState() => _RideScreenState();
}

class _RideScreenState extends State<RideScreen> {
  Timer? _tick;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 20), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _act(Future<void> Function() f, {String? done}) async {
    setState(() => busy = true);
    await runAction(context, f, done: done);
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final scope = TbScope.of(context);
    final me = scope.me;
    final site = scope.site;
    final clock = scope.clock;
    return StreamBuilder<Ride?>(
      stream: Repo.I.rideStream(widget.rideId),
      builder: (context, snap) {
        if (snap.hasError) return Scaffold(appBar: AppBar(title: const Text('Ride')), body: ErrorNote(Repo.friendly(snap.error!)));
        if (!snap.hasData) return Scaffold(appBar: AppBar(title: const Text('Ride')), body: const Loading());
        final ride = snap.data;
        if (ride == null) return Scaffold(appBar: AppBar(title: const Text('Ride')), body: const EmptyNote('This ride was removed.'));
        final isDriver = ride.isDriver(me.uid);
        final myPickup = ride.passengers[me.uid]?.pickedUp ?? false;
        final afterDeparture = DateTime.now().isAfter(ride.departAt.add(const Duration(minutes: 5)));
        final myReport = ride.noShowReports[me.uid] as Map<String, dynamic>?;

        return Scaffold(
          appBar: AppBar(title: const Text('Ride')),
          body: MaxWidth(
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(isDriver ? 'You are driving' : 'Your ride', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))),
                      rideStatusPill(ride.status),
                    ]),
                    LabeledValue('When', '${rideWhen(site, ride.windowId, ride.date, ride.direction)} · leaving ${clock.hhmm(ride.departAt)}'),
                    if (ride.cancelReason.isNotEmpty) LabeledValue('Reason', ride.cancelReason),
                    LabeledValue('Route', '${site.place(ride.fromPlaceId)?.name ?? ''} → ${site.place(ride.toPlaceId)?.name ?? ''}'),
                  ]),
                ),
              ),
              if (ride.isActive && !myPickup) _LiveCard(ride: ride, me: me, busy: busy, onAct: _act),
              const SectionTitle('People'),
              _Person(role: 'Driver', name: ride.driverName, phone: isDriver ? '' : ride.driverPhone),
              for (final p in ride.passengers.values)
                _Person(
                  role: 'Passenger · ${site.place(p.pickupPlaceId)?.name ?? ''}${p.arrived ? ' · arrived ✅' : p.pickedUp ? ' · picked up ✅' : ''}',
                  name: p.name,
                  phone: p.uid == me.uid ? '' : p.phone,
                  trailing: isDriver && ride.isActive && !p.pickedUp
                      ? TextButton(onPressed: busy ? null : () => _act(() => Repo.I.markPickedUp(ride.id, passengerUid: p.uid), done: '${p.name} picked up'), child: const Text('Picked up'))
                      : null,
                ),
              const Divider(height: 32),
              if (ride.isFinished)
                Text('This ride is ${ride.status.name.toLowerCase()}.', style: Theme.of(context).textTheme.bodyLarge)
              else if (isDriver) ...[
                const Text('Close the ride when everyone is dropped off. It also closes by itself once every passenger taps "I\'ve arrived", or 90 minutes after departure.', style: TextStyle(fontSize: 12)),
                const SizedBox(height: 6),
                FilledButton(
                  onPressed: busy ? null : () => _act(() async {
                        await LiveShare.I.stop();
                        await Repo.I.completeRide(ride.id);
                      }, done: 'Ride completed. Thank you! 🌱'),
                  child: const Text('Complete ride'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                  onPressed: busy ? null : () => _cancel(ride, late: _isLate(ride)),
                  child: const Text('Cancel ride'),
                ),
              ] else ...[
                if (!myPickup)
                  FilledButton(
                    onPressed: busy ? null : () => _act(() => Repo.I.markPickedUp(ride.id), done: "You're in. Have a good trip!"),
                    child: const Text("I've been picked up"),
                  ),
                if (!(ride.passengers[me.uid]?.arrived ?? false)) ...[
                  const SizedBox(height: 8),
                  FilledButton.tonal(
                    onPressed: busy ? null : () => _act(() async {
                          await LiveShare.I.stop();
                          final done = await Repo.I.markArrived(ride.id);
                          if (!context.mounted) return;
                          toast(context, done ? 'Everyone has arrived — ride completed 🌱' : 'Noted. Thanks for riding!');
                        }),
                    child: const Text("I've arrived"),
                  ),
                ],
                const SizedBox(height: 8),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                  onPressed: busy ? null : () => _cancel(ride, late: _isLate(ride)),
                  child: const Text('Leave this ride'),
                ),
              ],
              if (afterDeparture && (ride.isActive || ride.status == RideStatus.completed)) ...[
                const SectionTitle("Didn't turn up?"),
                const Text('Report a no-show only if you were at the pickup place and the other person never came. They lose 2 points and can dispute once.', style: TextStyle(fontSize: 12)),
                Wrap(spacing: 8, children: [
                  if (!isDriver && ride.noShowReports[ride.driverId] == null)
                    OutlinedButton(onPressed: busy ? null : () => _report(ride, ride.driverId, ride.driverName), child: const Text('Driver was a no-show')),
                  if (isDriver)
                    for (final p in ride.passengers.values)
                      if (!p.pickedUp && ride.noShowReports[p.uid] == null)
                        OutlinedButton(onPressed: busy ? null : () => _report(ride, p.uid, p.name), child: Text('${p.name} was a no-show')),
                ]),
              ],
              if (myReport != null) ...[
                const SectionTitle('No-show reported against you'),
                Text('Reported by ${myReport['byName'] ?? 'a member'}. '
                    '${myReport['resolved'] == true ? (myReport['upheld'] == true ? 'Upheld by the admin.' : 'Cancelled by the admin — points restored.') : (myReport['disputed'] == true ? 'Your dispute is with the admin.' : 'You can dispute this within 24 hours.')}'),
                if (myReport['disputed'] != true && myReport['resolved'] != true)
                  OutlinedButton(onPressed: busy ? null : () => _act(() => Repo.I.disputeNoShow(ride.id), done: 'Dispute sent to the admin'), child: const Text('Dispute')),
              ],
            ]),
          ),
        );
      },
    );
  }

  bool _isLate(Ride r) => DateTime.now().isAfter(r.departAt.subtract(const Duration(minutes: 10)));

  Future<void> _cancel(Ride ride, {required bool late}) async {
    final isDriver = ride.isDriver(TbScope.of(context).me.uid);
    final ok = await confirm(
      context,
      isDriver ? 'Cancel this ride?' : 'Leave this ride?',
      (isDriver ? 'Your passengers will be told and their requests reopen. ' : 'The driver will be told. ') +
          (late ? 'It is less than 10 minutes to departure, so this costs 1 point.' : 'No penalty this early.'),
      yes: isDriver ? 'Cancel ride' : 'Leave',
      danger: true,
    );
    if (!ok || !mounted) return;
    final reason = await askReason(context, isDriver ? 'Tell your passengers why (optional)' : 'Tell the driver why (optional)',
        isDriver ? 'Cancel ride' : 'Leave', required: false);
    if (reason == null || !mounted) return;
    await _act(() async {
      await LiveShare.I.stop();
      await Repo.I.cancelRide(ride.id, reason: reason);
      if (mounted) Navigator.pop(context);
    }, done: isDriver ? 'Ride cancelled' : 'You left the ride');
  }

  Future<void> _report(Ride ride, String uid, String name) async {
    if (await confirm(context, 'Report $name as a no-show?', 'Only do this if you were at the pickup place and $name never came.', yes: 'Report', danger: true)) {
      if (mounted) await _act(() => Repo.I.reportNoShow(ride.id, uid), done: 'Reported');
    }
  }
}

class _Person extends StatelessWidget {
  const _Person({required this.role, required this.name, required this.phone, this.trailing});
  final String role, name, phone;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(name),
        subtitle: Text(role),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (trailing != null) trailing!,
          if (phone.isNotEmpty) CallButton(phone),
        ]),
      );
}

/// Live approach card: start/stop sharing, distance to the other side, stale warning.
class _LiveCard extends StatelessWidget {
  const _LiveCard({required this.ride, required this.me, required this.busy, required this.onAct});
  final Ride ride;
  final UserProfile me;
  final bool busy;
  final Future<void> Function(Future<void> Function(), {String? done}) onAct;

  @override
  Widget build(BuildContext context) {
    final isDriver = ride.isDriver(me.uid);
    return ValueListenableBuilder<String?>(
      valueListenable: LiveShare.I.activeRideId,
      builder: (context, activeId, _) {
        final sharing = activeId == ride.id;
        return Card(
          color: Theme.of(context).colorScheme.tertiaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(sharing ? '📡 Sharing your position' : 'Share your position', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              if (!sharing)
                Text(isDriver
                    ? 'Your passengers will see how far away you are and get an alert when you are close. Stops at pickup.'
                    : 'The driver will see where you are, and you get one alert when the car is close. Stops at pickup.',
                    style: const TextStyle(fontSize: 13)),
              if (sharing) ...[
                StreamBuilder<List<LivePosition>>(
                  stream: Repo.I.liveStream(ride.id),
                  builder: (context, snap) {
                    final list = snap.data ?? const [];
                    final mine = LiveShare.I.myPosition.value;
                    final others = list.where((p) => p.uid != me.uid).toList();
                    if (others.isEmpty) return const Text('Waiting for the other side to share…', style: TextStyle(fontSize: 13));
                    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      for (final o in others)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            '${isDriver ? (ride.passengers[o.uid]?.name ?? 'Passenger') : ride.driverName}: '
                            '${mine == null ? 'waiting for your GPS…' : etaText(distanceMeters(mine.latitude, mine.longitude, o.lat, o.lng))}'
                            '${staleText(o.at).isNotEmpty ? ' · ⚠ ${staleText(o.at)}' : ''}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                    ]);
                  },
                ),
                const SizedBox(height: 4),
                const Text('Straight-line estimate. Stops automatically at pickup or after 45 min.', style: TextStyle(fontSize: 12)),
              ],
              const SizedBox(height: 8),
              sharing
                  ? OutlinedButton(onPressed: () => LiveShare.I.stop(), child: const Text('Stop sharing'))
                  : FilledButton(
                      onPressed: busy
                          ? null
                          : () => onAct(() async {
                                final ok = await LiveShare.I.start(ride, me.uid);
                                if (!ok) throw AppError('Location is off or not allowed. Turn on location and allow it for TravelBuddy.');
                              }),
                      child: const Text("I'm on my way / waiting"),
                    ),
            ]),
          ),
        );
      },
    );
  }
}

// Keep the import used on web builds where minutesAgo is referenced by other screens.
// ignore: unused_element
final _keep = minutesAgo;
