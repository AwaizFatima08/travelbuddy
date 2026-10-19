// Home (v2.1): "Driving or riding?" → direction → live board for the next hour + my active ride.
// Booking is real-time only: leaving time = now … +60 min, any hour of the day. The four decided
// slots are shown as an info strip (they drive reminders, not booking).
import 'package:flutter/material.dart';

import '../../app/widgets.dart';
import '../../core/clock.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../ride/ride_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? role; // 'driver' | 'passenger'
  Direction? direction;

  @override
  Widget build(BuildContext context) {
    final scope = TbScope.of(context);
    final me = scope.me;
    final clock = scope.clock;
    role ??= me.hasCar ? (me.lastRole ?? 'driver') : 'passenger';
    if (!me.hasCar) role = 'passenger';
    direction ??= clock.suggestedDirection();

    return StreamBuilder<List<Ride>>(
      stream: Repo.I.myActiveRides(me.uid),
      builder: (context, ridesSnap) {
        final rides = ridesSnap.data ?? const [];
        return StreamBuilder<List<Post>>(
          stream: Repo.I.myOpenPosts(me.uid),
          builder: (context, mineSnap) {
            final mine = mineSnap.data ?? const <Post>[];
            final canPost = rides.isEmpty && mine.isEmpty;
            return Scaffold(
              appBar: AppBar(
                title: const Text('TravelBuddy'),
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Center(child: Text('⭐ ${me.points}', style: const TextStyle(fontWeight: FontWeight.bold))),
                  ),
                ],
              ),
              body: MaxWidth(
                child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    children: [
                      if (rides.isNotEmpty) ...[
                        const SectionTitle('Your ride'),
                        for (final r in rides) _ActiveRideCard(r),
                      ],
                      if (mine.isNotEmpty) ...[
                        const SectionTitle('Your post'),
                        for (final p in mine) _MyPostCard(p),
                      ],
                      const SectionTitle('Today I am…'),
                      SegmentedButton<String>(
                        segments: [
                          ButtonSegment(value: 'driver', icon: const Icon(Icons.directions_car), label: const Text('Driving'), enabled: me.hasCar),
                          const ButtonSegment(value: 'passenger', icon: Icon(Icons.hail), label: Text('Riding')),
                        ],
                        selected: {role!},
                        onSelectionChanged: (s) {
                          setState(() => role = s.first);
                          Repo.I.updateMyProfile({'lastRole': s.first});
                        },
                      ),
                      if (!me.hasCar)
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text('Have a car? Turn on "I have a car" in Settings to offer rides.', style: TextStyle(fontSize: 12)),
                        ),
                      const SectionTitle('Going'),
                      SegmentedButton<Direction>(
                        segments: const [
                          ButtonSegment(value: Direction.toPlant, icon: Icon(Icons.factory), label: Text('To Plant')),
                          ButtonSegment(value: Direction.toTownship, icon: Icon(Icons.home), label: Text('To Township')),
                        ],
                        selected: {direction!},
                        onSelectionChanged: (s) => setState(() => direction = s.first),
                      ),
                      _SlotStrip(clock: clock),
                      _Board(direction: direction!, role: role!, mine: mine),
                    ],
                  ),
              ),
              floatingActionButton: !canPost
                  ? null
                  : FloatingActionButton.extended(
                      onPressed: () => showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => TbScope(me: me, site: scope.site, child: PostSheet(direction: direction!, role: role!)),
                      ),
                      icon: Icon(role == 'driver' ? Icons.directions_car : Icons.hail),
                      label: Text(role == 'driver' ? 'Offer seats' : 'I need a ride'),
                    ),
            );
          },
        );
      },
    );
  }
}

/// The four decided slots as information: which one is running, when the next starts.
class _SlotStrip extends StatelessWidget {
  const _SlotStrip({required this.clock});
  final SiteClock clock;
  @override
  Widget build(BuildContext context) {
    final windows = clock.site.windows.where((w) => w.active).toList()..sort((a, b) => a.order.compareTo(b.order));
    if (windows.isEmpty) return const SizedBox.shrink();
    final running = clock.running()?.window.id;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final w in windows)
            Chip(
              visualDensity: VisualDensity.compact,
              backgroundColor: w.id == running ? cs.primaryContainer : null,
              label: Text('${w.name} ${w.start}', style: TextStyle(fontSize: 12, fontWeight: w.id == running ? FontWeight.bold : null)),
              avatar: Icon(w.from == Side.township ? Icons.factory : Icons.home, size: 14),
            ),
        ]),
        const Text('Reminder slots — book any time, up to 1 hour ahead. Set slot reminders in Settings.', style: TextStyle(fontSize: 11)),
      ]),
    );
  }
}

class _ActiveRideCard extends StatelessWidget {
  const _ActiveRideCard(this.ride);
  final Ride ride;
  @override
  Widget build(BuildContext context) {
    final scope = TbScope.of(context);
    final site = scope.site;
    final isDriver = ride.isDriver(scope.me.uid);
    final who = isDriver
        ? 'With ${ride.passengers.values.map((p) => p.name).join(', ')}'
        : 'With ${ride.driverName} (driver)';
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: ListTile(
        leading: Icon(isDriver ? Icons.directions_car : Icons.hail),
        title: Text('${scope.clock.hhmm(ride.departAt)} · ${ride.direction.label}', style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('$who\n${site.place(ride.fromPlaceId)?.name ?? ''} → ${site.place(ride.toPlaceId)?.name ?? ''}'),
        isThreeLine: true,
        trailing: rideStatusPill(ride.status),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TbScope(me: scope.me, site: site, child: RideScreen(ride.id)))),
      ),
    );
  }
}

/// Open posts for the chosen direction in the next hour: for a driver, requests to accept; for a passenger, cars to join.
class _Board extends StatelessWidget {
  const _Board({required this.direction, required this.role, required this.mine});
  final Direction direction;
  final String role;
  final List<Post> mine;

  @override
  Widget build(BuildContext context) {
    final scope = TbScope.of(context);
    final me = scope.me;
    return StreamBuilder<List<Post>>(
      stream: Repo.I.boardPosts(me.siteId, direction),
      builder: (context, snap) {
        if (snap.hasError) return ErrorNote(Repo.friendly(snap.error!));
        if (!snap.hasData) return const Loading();
        final posts = snap.data!;
        final offers = posts.where((p) => p.isOffer && p.userId != me.uid).toList();
        final requests = posts.where((p) => !p.isOffer && p.userId != me.uid).toList();
        final myOffer = mine.where((p) => p.isOffer && p.direction == direction).firstOrNull;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (role == 'driver') ...[
            SectionTitle('Passengers waiting · next hour (${requests.length})'),
            if (requests.isEmpty) const EmptyNote('Nobody is waiting yet. Offer seats and matching passengers will be notified.'),
            for (final r in requests) _RequestCard(r, myOffer: myOffer),
            if (offers.isNotEmpty) _OthersLine('Other drivers: ${offers.map((o) => '${o.userName} ${scope.clock.hhmm(o.departAt)}').join(', ')}'),
          ] else ...[
            SectionTitle('Cars offering seats · next hour (${offers.length})'),
            if (offers.isEmpty) const EmptyNote('No cars yet. Post "I need a ride" and drivers going your way will be notified.'),
            for (final o in offers) _OfferCard(o),
            if (requests.isNotEmpty) _OthersLine('Also waiting: ${requests.map((r) => '${r.userName} ${scope.clock.hhmm(r.departAt)}').join(', ')}'),
          ],
        ]);
      },
    );
  }
}

class _OthersLine extends StatelessWidget {
  const _OthersLine(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(top: 6), child: Text(text, style: const TextStyle(fontSize: 12)));
}

class _MyPostCard extends StatelessWidget {
  const _MyPostCard(this.p);
  final Post p;
  @override
  Widget build(BuildContext context) {
    final scope = TbScope.of(context);
    final site = scope.site;
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p.isOffer
              ? (p.seatsLeft > 0 ? '🚗 You are offering ${p.seatsLeft} of ${p.seats} seat(s)' : '🚗 Your car is full (${p.seats} seats)')
              : '🙋 You are waiting for a ride',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('${scope.clock.hhmm(p.departAt)} · ${p.direction.label}\n${site.place(p.fromPlaceId)?.name ?? ''} → ${site.place(p.toPlaceId)?.name ?? ''}'),
          Row(children: [
            if (p.isOffer)
              Expanded(
                child: SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Auto-accept joiners', style: TextStyle(fontSize: 13)),
                  value: p.autoAccept,
                  onChanged: (v) => Repo.I.setAutoAccept(p.id, v),
                ),
              )
            else
              const Spacer(),
            TextButton(
              onPressed: () async {
                final reason = await askReason(context, 'Cancel this post?', 'Cancel post', required: false);
                if (reason != null && context.mounted) {
                  runAction(context, () => Repo.I.cancelPost(p.id, reason: reason), done: 'Post cancelled');
                }
              },
              child: const Text('Cancel'),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard(this.r, {required this.myOffer});
  final Post r;
  final Post? myOffer;
  @override
  Widget build(BuildContext context) {
    final scope = TbScope.of(context);
    final site = scope.site;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('🙋 ${r.userName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
            Text(scope.clock.hhmm(r.departAt), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ]),
          Text('Pickup ${site.place(r.fromPlaceId)?.name ?? ''} → ${site.place(r.toPlaceId)?.name ?? ''}'),
          if (r.note.isNotEmpty) Text('“${r.note}”', style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            FilledButton(
              onPressed: myOffer == null || myOffer!.seatsLeft < 1
                  ? null
                  : () => runAction(context, () async {
                        final id = await Repo.I.acceptRequest(myOffer!.id, r.id);
                        if (context.mounted) {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => TbScope(me: scope.me, site: site, child: RideScreen(id))));
                        }
                      }, done: '${r.userName} is locked into your ride'),
              child: const Text('Accept'),
            ),
            CallButton(r.userPhone),
          ]),
          if (myOffer == null)
            const Padding(padding: EdgeInsets.only(top: 4), child: Text('Tap "Offer seats" first to accept passengers.', style: TextStyle(fontSize: 12)))
          else if (myOffer!.seatsLeft < 1)
            const Padding(padding: EdgeInsets.only(top: 4), child: Text('Your car is full.', style: TextStyle(fontSize: 12))),
        ]),
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard(this.o);
  final Post o;
  @override
  Widget build(BuildContext context) {
    final scope = TbScope.of(context);
    final site = scope.site;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('🚗 ${o.userName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
            Text(scope.clock.hhmm(o.departAt), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ]),
          Text('${o.seatsLeft} seat(s) · from ${site.place(o.fromPlaceId)?.name ?? ''} → ${site.place(o.toPlaceId)?.name ?? ''}'),
          if (o.note.isNotEmpty) Text('“${o.note}”', style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            FilledButton(
              onPressed: () => _join(context, o),
              child: Text(o.autoAccept ? 'Join' : 'Ask to join'),
            ),
            CallButton(o.userPhone),
          ]),
        ]),
      ),
    );
  }

  Future<void> _join(BuildContext context, Post o) async {
    final scope = TbScope.of(context);
    final site = scope.site;
    final pickups = site.placesOn(o.direction.from);
    final drops = site.placesOn(o.direction.to);
    String pickup = pickups.any((p) => p.id == o.fromPlaceId) ? o.fromPlaceId : (pickups.firstOrNull?.id ?? '');
    String drop = drops.any((p) => p.id == o.toPlaceId) ? o.toPlaceId : (drops.firstOrNull?.id ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: Text('Join ${o.userName}?'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: pickup,
              decoration: const InputDecoration(labelText: 'Pick me up at'),
              items: [for (final p in pickups) DropdownMenuItem(value: p.id, child: Text(p.name))],
              onChanged: (v) => setState(() => pickup = v ?? pickup),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: drop,
              decoration: const InputDecoration(labelText: 'Drop me at'),
              items: [for (final p in drops) DropdownMenuItem(value: p.id, child: Text(p.name))],
              onChanged: (v) => setState(() => drop = v ?? drop),
            ),
            const SizedBox(height: 8),
            Text(o.autoAccept ? 'The seat is yours as soon as you tap Join.' : 'The driver will be asked to accept you.',
                style: const TextStyle(fontSize: 12)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Back')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(o.autoAccept ? 'Join' : 'Ask')),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    await runAction(context, () async {
      final r = await Repo.I.joinOffer(o.id, pickup, drop);
      if (!context.mounted) return;
      if (r['locked'] == true) {
        toast(context, 'Ride locked ✅');
        Navigator.push(context, MaterialPageRoute(builder: (_) => TbScope(me: scope.me, site: site, child: RideScreen(r['rideId'] as String))));
      } else {
        toast(context, 'Request sent. ${o.userName} will accept or decline.');
      }
    });
  }
}

/// Bottom sheet: offer seats (driver) or ask for a ride (passenger). Leaving time: now … +60 min.
/// Shows who is already posted around the chosen time ("who's around").
class PostSheet extends StatefulWidget {
  const PostSheet({super.key, required this.direction, required this.role});
  final Direction direction;
  final String role;
  @override
  State<PostSheet> createState() => _PostSheetState();
}

class _PostSheetState extends State<PostSheet> {
  late Direction direction = widget.direction;
  List<DateTime> choices = const [];
  DateTime? departAt;
  String? from, to;
  int seats = 3;
  bool autoAccept = true, busy = false;
  final note = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final scope = TbScope.of(context);
    final site = scope.site;
    final clock = scope.clock;
    if (choices.isEmpty) {
      choices = clock.leavingChoices();
      departAt = choices.first;
    }
    final froms = site.placesOn(direction.from), tos = site.placesOn(direction.to);
    if (from == null || !froms.any((p) => p.id == from)) from = froms.firstOrNull?.id;
    if (to == null || !tos.any((p) => p.id == to)) to = tos.firstOrNull?.id;
    final driver = widget.role == 'driver';
    final idx = choices.indexOf(departAt!);
    final tol = Duration(minutes: site.matchMinutes);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: MaxWidth(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(20),
          children: [
            Text(driver ? 'Offer seats' : 'I need a ride', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SegmentedButton<Direction>(
              segments: const [
                ButtonSegment(value: Direction.toPlant, label: Text('To Plant')),
                ButtonSegment(value: Direction.toTownship, label: Text('To Township')),
              ],
              selected: {direction},
              onSelectionChanged: (s) => setState(() => direction = s.first),
            ),
            const SizedBox(height: 8),
            Row(children: [
              const Expanded(child: Text('Leaving at')),
              IconButton(onPressed: idx > 0 ? () => setState(() => departAt = choices[idx - 1]) : null, icon: const Icon(Icons.remove)),
              Text(clock.hhmm(departAt!), style: Theme.of(context).textTheme.titleLarge),
              IconButton(onPressed: idx >= 0 && idx < choices.length - 1 ? () => setState(() => departAt = choices[idx + 1]) : null, icon: const Icon(Icons.add)),
            ]),
            const Text('Real-time booking: now to 1 hour ahead, in 5-minute steps.', style: TextStyle(fontSize: 11)),
            DropdownButtonFormField<String>(
              key: ValueKey('from-${direction.name}'),
              initialValue: from,
              decoration: InputDecoration(labelText: driver ? 'Starting from' : 'Pick me up at'),
              items: [for (final p in froms) DropdownMenuItem(value: p.id, child: Text(p.name))],
              onChanged: (v) => setState(() => from = v),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: ValueKey('to-${direction.name}'),
              initialValue: to,
              decoration: InputDecoration(labelText: driver ? 'Going to' : 'Drop me at'),
              items: [for (final p in tos) DropdownMenuItem(value: p.id, child: Text(p.name))],
              onChanged: (v) => setState(() => to = v),
            ),
            if (driver) ...[
              const SizedBox(height: 8),
              Row(children: [
                const Expanded(child: Text('Seats available')),
                IconButton(onPressed: seats > 1 ? () => setState(() => seats--) : null, icon: const Icon(Icons.remove)),
                Text('$seats', style: Theme.of(context).textTheme.titleLarge),
                IconButton(onPressed: seats < 4 ? () => setState(() => seats++) : null, icon: const Icon(Icons.add)),
              ]),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Auto-accept passengers who join'),
                subtitle: const Text('Off = you accept each one by hand'),
                value: autoAccept,
                onChanged: (v) => setState(() => autoAccept = v),
              ),
            ],
            TextField(controller: note, maxLength: 100, decoration: const InputDecoration(labelText: 'Note (optional)')),
            // Who's around: everyone posted for this direction within ± matchMinutes of my time.
            StreamBuilder<List<Post>>(
              stream: Repo.I.boardPosts(scope.me.siteId, direction),
              builder: (context, snap) {
                final around = (snap.data ?? const <Post>[])
                    .where((p) => p.userId != scope.me.uid && (p.departAt.difference(departAt!)).abs() <= tol)
                    .toList();
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text("Who's around ${clock.hhmm(departAt!)} (±${site.matchMinutes} min)", style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (around.isEmpty) const Text('Nobody posted yet — you may be the first.', style: TextStyle(fontSize: 12)),
                  for (final p in around)
                    Text('${p.isOffer ? '🚗' : '🙋'} ${p.userName} · ${clock.hhmm(p.departAt)} · ${site.place(p.fromPlaceId)?.name ?? ''}'
                        '${p.isOffer ? ' · ${p.seatsLeft} seat(s)' : ''}', style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 8),
                ]);
              },
            ),
            FilledButton(
              onPressed: busy || from == null || to == null
                  ? null
                  : () async {
                      setState(() => busy = true);
                      final ok = await runAction(context, () => Repo.I.createPost(
                            me: scope.me,
                            kind: driver ? PostKind.offer : PostKind.request,
                            direction: direction,
                            date: clock.dateKey(clock.toLocal(departAt!)),
                            departAt: departAt!,
                            fromPlaceId: from!,
                            toPlaceId: to!,
                            seats: seats,
                            autoAccept: autoAccept,
                            note: note.text,
                          ), done: driver ? 'Seats offered. Matching passengers are notified.' : 'Request posted. Drivers going your way are notified.');
                      if (mounted) setState(() => busy = false);
                      if (ok && context.mounted) Navigator.pop(context);
                    },
              child: Text(driver ? 'Offer seats' : 'Post request'),
            ),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ],
        ),
      ),
    );
  }
}
