// Home: mode switch (Passenger / Driver), today's check-in, discovery and ride closure — HomeScreen.kt.
import 'package:flutter/material.dart';

import '../app/widgets.dart';
import '../core/models.dart';
import '../core/repo.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.me});
  final AppUser me;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late bool driverMode = widget.me.prefersDriver;
  final today = todayKarachi();

  @override
  Widget build(BuildContext context) {
    final me = widget.me;
    return StreamBuilder<Ride?>(
      stream: Repo.I.driverTodayRide(me.uid, today),
      builder: (context, rideSnap) => StreamBuilder<PassengerState>(
        stream: Repo.I.passengerState(me.uid, today),
        initialData: const PassengerLoading(),
        builder: (context, psSnap) {
          final ride = rideSnap.data;
          final ps = psSnap.data ?? const PassengerLoading();
          if (rideSnap.hasError || psSnap.hasError) {
            return Center(child: Pad(child: Text(Repo.friendly(rideSnap.error ?? psSnap.error!), textAlign: TextAlign.center)));
          }
          return MaxWidth(
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
              _Header(me: me, today: today),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: const [ButtonSegment(value: false, label: Text('Passenger'), icon: Icon(Icons.hail)), ButtonSegment(value: true, label: Text('Driver'), icon: Icon(Icons.directions_car))],
                selected: {driverMode},
                onSelectionChanged: (s) => setState(() => driverMode = s.first),
              ),
              const SizedBox(height: 16),
              if (driverMode) _DriverPanel(me: me, ride: ride, passengerState: ps, today: today) else _PassengerPanel(me: me, ride: ride, state: ps, today: today),
              const SizedBox(height: 20),
              _Impact(me: me),
              const SizedBox(height: 16),
              const _Leaderboard(),
            ]),
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.me, required this.today});
  final AppUser me;
  final String today;
  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Hello, ${me.name.split(' ').first}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          Muted('${fmtDate(today)} · ${me.department}'),
        ])),
        if (me.isAdmin) const Chip(label: Text('Admin'), visualDensity: VisualDensity.compact),
      ]);
}

// ----------------------------------------------------------------------------- driver
class _DriverPanel extends StatefulWidget {
  const _DriverPanel({required this.me, required this.ride, required this.passengerState, required this.today});
  final AppUser me;
  final Ride? ride;
  final PassengerState passengerState;
  final String today;
  @override
  State<_DriverPanel> createState() => _DriverPanelState();
}

class _DriverPanelState extends State<_DriverPanel> {
  late String pickup = widget.me.townshipLocation.isEmpty ? 'EMs' : widget.me.townshipLocation;
  final custom = TextEditingController();
  final note = TextEditingController();
  late int seats = widget.me.defaultDriverSeats;
  var busy = false;

  @override
  void initState() {
    super.initState();
    _syncFromRide();
  }

  @override
  void didUpdateWidget(covariant _DriverPanel old) {
    super.didUpdateWidget(old);
    if (old.ride?.rideId != widget.ride?.rideId) _syncFromRide();
  }

  void _syncFromRide() {
    final r = widget.ride;
    if (r == null) return;
    pickup = r.pickupSide == PickupSide.other ? MasterData.otherLocationName : r.pickupZone;
    custom.text = r.customPickupLocation;
    note.text = r.message;
    seats = r.totalSeats;
  }

  Future<void> _run(Future<void> Function() f, {String? ok}) async {
    setState(() => busy = true);
    try {
      await f();
      if (ok != null && mounted) toast(context, ok);
    } catch (e) {
      if (mounted) toast(context, Repo.friendly(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ride = widget.ride;
    final side = MasterData.sideForPickup(pickup);
    final blockedByPassengerRide = widget.passengerState is PassengerRiding || widget.passengerState is PassengerLooking;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (ride == null) ...[
        if (blockedByPassengerRide)
          TbCard(
            tint: const Color(0xFFFFF3DB),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
              Eyebrow('Active passenger request'),
              SizedBox(height: 6),
              Text('Close or complete your current ride before posting as a Driver.'),
              Muted('Switch to Passenger to see it.'),
            ]),
          )
        else
          TbCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Eyebrow('Offer a ride to colleagues'),
              const Text('Set up your availability', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              PickupPicker(value: pickup, onChanged: (v) => setState(() => pickup = v)),
              if (side == PickupSide.other) ...[
                const SizedBox(height: 12),
                TextField(controller: custom, maxLength: 150, decoration: const InputDecoration(labelText: 'Pickup Location (Required)')),
              ],
              const SizedBox(height: 12),
              Row(children: [
                const Expanded(child: Text('Available Seats', style: TextStyle(fontWeight: FontWeight.w500))),
                IconButton.outlined(onPressed: seats > 1 ? () => setState(() => seats--) : null, icon: const Icon(Icons.remove)),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('$seats', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                IconButton.outlined(onPressed: seats < 8 ? () => setState(() => seats++) : null, icon: const Icon(Icons.add)),
              ]),
              const SizedBox(height: 8),
              TextField(controller: note, maxLength: 250, decoration: const InputDecoration(labelText: 'Message for Passengers (optional)')),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: busy ? null : () => _run(() => Repo.I.publishAvailability(me: widget.me, pickupZone: pickup, totalSeats: seats, message: note.text, customPickupLocation: custom.text), ok: 'Availability published. Colleagues can now join your ride.'),
                icon: const Icon(Icons.campaign),
                label: const Text('PUBLISH AVAILABILITY'),
              ),
            ]),
          ),
      ] else ...[
        _ActiveRideCard(ride: ride, me: widget.me, today: widget.today, busy: busy, onEdit: () => _editSheet(ride), onClose: (happened) => _run(() => Repo.I.closeRideAsDriver(ride.rideId, happened: happened), ok: happened ? 'Ride closed. Thank you for driving!' : 'Ride cancelled.')),
      ],
      const SizedBox(height: 16),
      Text('PEOPLE LOOKING FOR A RIDE (${PickupSide.label(side).toUpperCase()})', style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
      const SizedBox(height: 8),
      StreamBuilder<List<PassengerNeed>>(
        stream: Repo.I.lookingNeeds(widget.today, side),
        builder: (context, s) {
          if (s.hasError) return Muted(Repo.friendly(s.error!));
          if (!s.hasData) return const Loading();
          final needs = s.data!;
          if (needs.isEmpty) return TbCard(child: Muted('No passengers currently looking for a ride on ${PickupSide.label(side)}.', center: true));
          return Column(children: [
            for (final n in needs)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TbCard(
                  child: Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(n.passengerName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      Muted('Dept: ${n.passengerDepartment}'),
                      Muted('Pickup: ${n.displayPickup} (${PickupSide.label(n.pickupSide)})'),
                      if (n.message.isNotEmpty) Muted('Note: "${n.message}"'),
                    ])),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: busy || blockedByPassengerRide ? null : () => _acceptDialog(n),
                      child: const Text('DRIVE & ACCEPT'),
                    ),
                  ]),
                ),
              ),
          ]);
        },
      ),
    ]);
  }

  Future<void> _acceptDialog(PassengerNeed n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('RIDE REQUEST'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(n.passengerName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          Text('Department: ${n.passengerDepartment}'),
          Text('Pickup Area: ${n.displayPickup} (${PickupSide.label(n.pickupSide)})'),
          if (n.message.isNotEmpty) Text('Message: "${n.message}"'),
          const SizedBox(height: 8),
          Muted(widget.ride == null ? 'Accepting creates your ride for today with ${widget.me.defaultDriverSeats} seats (your default).' : 'The passenger takes one of your ${widget.ride!.availableSeats} free seats.'),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('DRIVE & ACCEPT'))],
      ),
    );
    if (ok != true) return;
    await _run(() => Repo.I.acceptNeed(widget.me, n), ok: '${n.passengerName} is now riding with you.');
  }

  Future<void> _editSheet(Ride ride) async {
    pickup = ride.pickupSide == PickupSide.other ? MasterData.otherLocationName : ride.pickupZone;
    custom.text = ride.customPickupLocation;
    note.text = ride.message;
    seats = ride.totalSeats;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Edit today\'s availability', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            PickupPicker(value: pickup, onChanged: (v) => setS(() => pickup = v)),
            if (MasterData.sideForPickup(pickup) == PickupSide.other) ...[const SizedBox(height: 12), TextField(controller: custom, decoration: const InputDecoration(labelText: 'Pickup Location (Required)'))],
            const SizedBox(height: 12),
            Row(children: [
              const Expanded(child: Text('Total seats')),
              IconButton.outlined(onPressed: seats > (ride.acceptedPassengerIds.isEmpty ? 1 : ride.acceptedPassengerIds.length) ? () => setS(() => seats--) : null, icon: const Icon(Icons.remove)),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('$seats', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
              IconButton.outlined(onPressed: seats < 8 ? () => setS(() => seats++) : null, icon: const Icon(Icons.add)),
            ]),
            TextField(controller: note, maxLength: 250, decoration: const InputDecoration(labelText: 'Message for Passengers (optional)')),
            const SizedBox(height: 8),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('SAVE')),
          ]),
        ),
      ),
    );
    if (ok != true) return;
    await _run(() => Repo.I.publishAvailability(me: widget.me, pickupZone: pickup, totalSeats: seats, message: note.text, customPickupLocation: custom.text), ok: 'Availability updated.');
  }
}

class _ActiveRideCard extends StatelessWidget {
  const _ActiveRideCard({required this.ride, required this.me, required this.today, required this.busy, required this.onEdit, required this.onClose});
  final Ride ride;
  final AppUser me;
  final String today;
  final bool busy;
  final VoidCallback onEdit;
  final ValueChanged<bool> onClose;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<RideRequest>>(
        stream: Repo.I.incomingRequests(me.uid, today),
        builder: (context, s) {
          final reqs = (s.data ?? const <RideRequest>[]).where((r) => r.rideId == ride.rideId).toList();
          final completed = ride.completedPassengerIds.length;
          return TbCard(
            tint: primaryVeryLight,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const Expanded(child: Eyebrow("Today's active ride")),
                Chip(label: Text(ride.status.replaceAll('_', ' ')), visualDensity: VisualDensity.compact),
              ]),
              const SizedBox(height: 4),
              Text('Pickup: ${ride.displayPickup} (${PickupSide.label(ride.pickupSide)})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Muted('Seats: ${ride.acceptedPassengerIds.length} / ${ride.totalSeats} taken · ${ride.availableSeats} free'),
              if (ride.message.isNotEmpty) Muted('Message: "${ride.message}"'),
              if (ride.acceptedPassengerIds.isNotEmpty) Text('Passengers completed: $completed / ${ride.acceptedPassengerIds.length}', style: const TextStyle(color: primaryDark, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text('CONFIRMED PASSENGERS (${reqs.length})', style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5, fontSize: 13)),
              if (reqs.isEmpty) const Muted('No passengers have joined this ride yet.'),
              for (final r in reqs)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(backgroundColor: primaryLight, child: Text(r.passengerName.isEmpty ? '?' : r.passengerName[0], style: const TextStyle(color: primaryDark))),
                  title: Text(r.passengerName),
                  subtitle: Text('Dept: ${r.passengerDepartment} · Pickup: ${r.displayPickup}${ride.completedPassengerIds.contains(r.passengerId) ? ' · arrived ✅' : ''}'),
                  trailing: r.passengerPhone.isEmpty ? null : IconButton(icon: const Icon(Icons.phone), tooltip: r.passengerPhone, onPressed: () => dial(r.passengerPhone)),
                ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: OutlinedButton.icon(onPressed: busy ? null : onEdit, icon: const Icon(Icons.edit), label: const Text('EDIT'))),
                const SizedBox(width: 8),
                Expanded(flex: 2, child: FilledButton.icon(onPressed: busy ? null : () => _closeDialog(context), icon: const Icon(Icons.flag), label: const Text('CLOSE RIDE'))),
              ]),
            ]),
          );
        },
      );

  Future<void> _closeDialog(BuildContext context) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Close today\'s ride'),
        content: const Text('Did the ride happen? Passengers who did not confirm themselves are closed without CO₂ credit; "didn\'t happen" cancels every seat.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Back')),
          OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("RIDE DIDN'T HAPPEN")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('RIDE HAPPENED')),
        ],
      ),
    );
    if (r != null) onClose(r);
  }
}

// ----------------------------------------------------------------------------- passenger
class _PassengerPanel extends StatefulWidget {
  const _PassengerPanel({required this.me, required this.ride, required this.state, required this.today});
  final AppUser me;
  final Ride? ride;
  final PassengerState state;
  final String today;
  @override
  State<_PassengerPanel> createState() => _PassengerPanelState();
}

class _PassengerPanelState extends State<_PassengerPanel> {
  late String pickup = widget.me.townshipLocation.isEmpty ? 'EMs' : widget.me.townshipLocation;
  final custom = TextEditingController();
  final note = TextEditingController();
  var busy = false;

  Future<void> _run(Future<void> Function() f, {String? ok}) async {
    setState(() => busy = true);
    try {
      await f();
      if (ok != null && mounted) toast(context, ok);
    } catch (e) {
      if (mounted) toast(context, Repo.friendly(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.state;
    final side = MasterData.sideForPickup(pickup);
    final hasDriverRide = widget.ride != null;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      switch (st) {
        PassengerLoading() => const TbCard(child: Muted('Checking ride status...')),
        PassengerRiding(:final request) => _MyRideCard(request: request, busy: busy, onClose: (completed) => _run(() => Repo.I.closeMyRide(request.requestId, completed: completed), ok: completed ? 'Ride completed. CO₂ saved!' : 'Seat released.')),
        PassengerLooking(:final need) => TbCard(
            tint: primaryVeryLight,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Eyebrow('Looking for a ride today'),
              Text('Pickup: ${need.displayPickup} (${PickupSide.label(need.pickupSide)})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Muted('Status: Looking for a driver'),
              if (need.message.isNotEmpty) Muted('Message: "${need.message}"'),
              const SizedBox(height: 8),
              const Muted('Drivers on your side can accept your request directly. You can also join a driver below.'),
              const SizedBox(height: 8),
              OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: errorColor),
                onPressed: busy
                    ? null
                    : () async {
                        if (await confirm(context, 'Cancel Ride Request?', 'Drivers will no longer see your request for today.', yes: 'Cancel Request', danger: true)) {
                          await _run(() => Repo.I.cancelNeed(need.needId), ok: 'Request cancelled.');
                        }
                      },
                child: const Text('Cancel Request'),
              ),
            ]),
          ),
        PassengerFree() => hasDriverRide
            ? TbCard(
                tint: const Color(0xFFFFF3DB),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
                  Eyebrow('Active driver availability'),
                  SizedBox(height: 6),
                  Text('You already have active Driver availability.'),
                  Muted('Close your current availability before requesting a ride as a Passenger. Switch to Driver to see it.'),
                ]),
              )
            : TbCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Eyebrow('I need a ride'),
                  const Text('Post your ride request', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  PickupPicker(value: pickup, onChanged: (v) => setState(() => pickup = v)),
                  if (side == PickupSide.other) ...[const SizedBox(height: 12), TextField(controller: custom, maxLength: 150, decoration: const InputDecoration(labelText: 'Pickup Location (Required)'))],
                  const SizedBox(height: 8),
                  TextField(controller: note, maxLength: 250, decoration: const InputDecoration(labelText: 'Message for Drivers (optional)')),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: busy ? null : () => _run(() => Repo.I.createNeed(me: widget.me, pickupZone: pickup, message: note.text, customPickupLocation: custom.text), ok: 'Request posted. Drivers on your side can now accept it.'),
                    icon: const Icon(Icons.hail),
                    label: const Text('POST RIDE REQUEST'),
                  ),
                ]),
              ),
      },
      if (st is! PassengerRiding) ...[
        const SizedBox(height: 16),
        Text('AVAILABLE DRIVERS (${PickupSide.label(side).toUpperCase()})', style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        const SizedBox(height: 8),
        StreamBuilder<List<Ride>>(
          stream: Repo.I.availableDrivers(widget.today, side),
          builder: (context, s) {
            if (s.hasError) return Muted(Repo.friendly(s.error!));
            if (!s.hasData) return const Loading();
            final rides = s.data!;
            if (rides.isEmpty) {
              return TbCard(child: Column(children: [Muted('No drivers published for ${PickupSide.label(side)} yet.', center: true), const Muted('Post your ride request so nearby drivers can accept directly!', center: true, size: 12.5)]));
            }
            return Column(children: [
              for (final r in rides)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TbCard(
                    child: Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r.driverName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        Muted('Dept: ${r.driverDepartment}'),
                        Muted('Pickup: ${r.displayPickup} (${PickupSide.label(r.pickupSide)})'),
                        Muted('Seats free: ${r.availableSeats} / ${r.totalSeats}'),
                        if (r.message.isNotEmpty) Muted('Note: "${r.message}"'),
                      ])),
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                        onPressed: busy || hasDriverRide ? null : () => _run(() => Repo.I.joinRide(widget.me, r), ok: "Ride confirmed! You're riding with ${r.driverName}."),
                        child: const Text('JOIN RIDE'),
                      ),
                    ]),
                  ),
                ),
            ]);
          },
        ),
      ],
    ]);
  }
}

class _MyRideCard extends StatelessWidget {
  const _MyRideCard({required this.request, required this.busy, required this.onClose});
  final RideRequest request;
  final bool busy;
  final ValueChanged<bool> onClose;
  @override
  Widget build(BuildContext context) => TbCard(
        tint: primaryVeryLight,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Eyebrow('My ride'),
          Text('Driver: ${request.driverName}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Muted('Dept: ${request.driverDepartment} · Pickup: ${request.displayPickup}'),
          if (request.message.isNotEmpty) Muted('Note: "${request.message}"'),
          if (request.driverPhone.isNotEmpty)
            Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => dial(request.driverPhone), icon: const Icon(Icons.phone), label: Text(request.driverPhone))),
          const SizedBox(height: 8),
          const Muted('When the ride is over, confirm it here so your CO₂ saving counts.'),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: busy ? null : () => _ask(context, false), child: const Text("I DIDN'T TAKE IT"))),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: FilledButton.icon(onPressed: busy ? null : () => _ask(context, true), icon: const Icon(Icons.check_circle), label: const Text('I COMPLETED THIS RIDE'))),
          ]),
        ]),
      );

  Future<void> _ask(BuildContext context, bool completed) async {
    final ok = await confirm(
      context,
      completed ? 'Complete this ride?' : "Didn't take this ride?",
      completed ? 'Your CO₂ saving is recorded and your seat is released.' : 'Your seat is released with no CO₂ credit.',
      yes: completed ? 'Yes, completed' : 'Yes, release seat',
      danger: !completed,
    );
    if (ok) onClose(completed);
  }
}

// ----------------------------------------------------------------------------- impact + leaderboard
class _Impact extends StatelessWidget {
  const _Impact({required this.me});
  final AppUser me;
  @override
  Widget build(BuildContext context) => TbCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Eyebrow('Your impact'),
          const SizedBox(height: 8),
          Row(children: [
            _stat('CO₂ saved', kg(me.totalCo2SavedKg)),
            _stat('Rides completed', '${me.totalCompletedRides}'),
          ]),
          const SizedBox(height: 4),
          const Muted('Counted when a ride is confirmed completed, as a driver or a passenger.', size: 12),
        ]),
      );
  Widget _stat(String k, String v) => Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(v, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: primaryDark)), Muted(k)]));
}

class _Leaderboard extends StatelessWidget {
  const _Leaderboard();
  @override
  Widget build(BuildContext context) => StreamBuilder<List<LeaderboardEntry>>(
        stream: Repo.I.leaderboard(),
        builder: (context, s) {
          final list = s.data ?? const [];
          return TbCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Eyebrow('Community CO₂ leaders'),
              const SizedBox(height: 8),
              if (s.hasError) Muted(Repo.friendly(s.error!))
              else if (!s.hasData) const Muted('Loading…')
              else if (list.isEmpty) const Muted('No completed carpools yet. The first spot is open for the first carpoolers!')
              else
                for (final e in list)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(backgroundColor: e.rank == 1 ? const Color(0xFFF2A516) : primaryLight, child: Text('${e.rank}', style: const TextStyle(fontWeight: FontWeight.bold, color: textPrimary))),
                    title: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${e.department} · ${e.rideCount} rides'),
                    trailing: Text(kg(e.co2SavedKg), style: const TextStyle(fontWeight: FontWeight.bold, color: primaryDark)),
                  ),
            ]),
          );
        },
      );
}
