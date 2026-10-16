// Leaderboard, history, notifications, settings.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/widgets.dart';
import '../../core/clock.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../services/push.dart';
import '../auth/auth_screens.dart';
import '../ride/ride_screen.dart';

const privacyUrl = 'https://travelbuddy.homilabs.org/privacy.html';

String ymOf(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});
  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  late String ym = ymOf(DateTime.now());
  (List<MonthlyRow>, Map<String, dynamic>)? data;
  List<PointsEntry>? mine;
  String? error;

  @override
  void initState() {
    super.initState();
    // TbScope is an inherited widget: it can only be read after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    final me = TbScope.of(context).me;
    setState(() {
      data = null;
      error = null;
    });
    try {
      final d = await Repo.I.monthly(me.siteId, ym);
      final p = await Repo.I.myPoints(me.uid);
      setState(() {
        data = d;
        mine = p;
      });
    } catch (e) {
      setState(() => error = Repo.friendly(e));
    }
  }

  void _shift(int months) {
    final parts = ym.split('-').map(int.parse).toList();
    final d = DateTime(parts[0], parts[1] + months);
    setState(() => ym = ymOf(d));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final me = TbScope.of(context).me;
    final rows = data?.$1 ?? const [];
    final totals = data?.$2 ?? const {};
    final drivers = rows.where((r) => r.driverLegs > 0).toList()..sort((a, b) => b.driverLegs.compareTo(a.driverLegs));
    final passengers = rows.where((r) => r.passengerLegs > 0).toList()..sort((a, b) => b.passengerLegs.compareTo(a.passengerLegs));
    final depts = <String, int>{};
    for (final r in rows) {
      depts[r.department] = (depts[r.department] ?? 0) + r.points;
    }
    final deptRows = depts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Green points'),
        actions: [
          IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
          Center(child: Text(ym, style: const TextStyle(fontWeight: FontWeight.bold))),
          IconButton(onPressed: ym == ymOf(DateTime.now()) ? null : () => _shift(1), icon: const Icon(Icons.chevron_right)),
        ],
      ),
      body: MaxWidth(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            ErrorNote(error),
            if (data == null && error == null) const Loading(),
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('You: ${me.points} points all-time', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text('Community this month: ${(totals['passengerLegs'] ?? 0)} shared seats · '
                      '${((totals['kgSaved'] ?? 0) as num).toStringAsFixed(1)} kg CO₂ saved'),
                  const Text('Driver +2 per ride with a passenger · passenger +1 · no-show −2 · late cancel −1', style: TextStyle(fontSize: 12)),
                ]),
              ),
            ),
            const SectionTitle('🏆 Top this month'),
            if (rows.isEmpty && data != null) const EmptyNote('No rides this month yet.'),
            for (var i = 0; i < rows.length && i < 10; i++)
              ListTile(
                dense: true,
                leading: CircleAvatar(radius: 14, child: Text('${i + 1}', style: const TextStyle(fontSize: 12))),
                title: Text(rows[i].name + (rows[i].uid == me.uid ? ' (you)' : '')),
                subtitle: Text('${rows[i].department} · ${rows[i].driverLegs} as driver, ${rows[i].passengerLegs} as passenger'),
                trailing: Text('${rows[i].points} pts', style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            if (drivers.isNotEmpty) const SectionTitle('🚗 Top drivers'),
            for (var i = 0; i < drivers.length && i < 5; i++)
              ListTile(dense: true, title: Text(drivers[i].name), trailing: Text('${drivers[i].driverLegs} rides')),
            if (passengers.isNotEmpty) const SectionTitle('🙋 Top passengers'),
            for (var i = 0; i < passengers.length && i < 5; i++)
              ListTile(dense: true, title: Text(passengers[i].name), trailing: Text('${passengers[i].passengerLegs} rides')),
            if (deptRows.isNotEmpty) const SectionTitle('🏢 Departments'),
            for (final d in deptRows.take(8)) ListTile(dense: true, title: Text(d.key.isEmpty ? '—' : d.key), trailing: Text('${d.value} pts')),
            const SectionTitle('Your recent points'),
            if (mine != null && mine!.isEmpty) const EmptyNote('No points yet. Share a ride to earn your first.'),
            for (final e in mine ?? const <PointsEntry>[])
              ListTile(
                dense: true,
                title: Text(_reason(e.reason)),
                subtitle: Text(e.at == null ? '' : '${prettyDate(e.at!.toIso8601String().substring(0, 10))} · ${minutesAgo(e.at)}'),
                trailing: Text('${e.delta > 0 ? '+' : ''}${e.delta}', style: TextStyle(fontWeight: FontWeight.bold, color: e.delta < 0 ? Theme.of(context).colorScheme.error : tbGreen)),
              ),
          ]),
        ),
      ),
    );
  }

  String _reason(String r) => switch (r) {
        'RIDE_LOCKED' => 'Ride locked',
        'RIDE_CANCELLED' => 'Ride cancelled',
        'RIDE_CANCELLED_BY_DRIVER' => 'Driver cancelled the ride',
        'LEFT_RIDE' => 'Left a ride',
        'RIDE_EMPTIED' => 'Passenger left (no one in the car)',
        'LATE_CANCEL' => 'Late cancellation',
        'NO_SHOW' => 'No-show',
        'NO_SHOW_RIDE_POINTS' => 'No-show: ride points removed',
        'NO_SHOW_REVERSED' => 'No-show cancelled by admin',
        'NO_SHOW_REVERSED_RIDE_POINTS' => 'Ride points restored',
        _ => r,
      };
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final rides = <Ride>[];
  DocumentSnapshot? cursor;
  bool more = true, loading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (loading || !more) return;
    setState(() => loading = true);
    try {
      final (page, last) = await Repo.I.history(TbScope.of(context).me.uid, cursor);
      setState(() {
        rides.addAll(page.where((r) => rides.every((x) => x.id != r.id)));
        cursor = last;
        more = page.length == 20;
      });
    } catch (e) {
      setState(() => error = Repo.friendly(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = TbScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('My rides')),
      body: MaxWidth(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          ErrorNote(error),
          const Text('Your rides from the last 30 days. Older rides are deleted automatically.', style: TextStyle(fontSize: 12)),
          if (rides.isEmpty && !loading) const EmptyNote('No rides yet.'),
          for (final r in rides)
            Card(
              child: ListTile(
                title: Text('${windowLabelFor(scope.site, r.windowId, r.date)} · ${scope.clock.hhmm(r.departAt)}'),
                subtitle: Text(r.isDriver(scope.me.uid)
                    ? 'You drove ${r.passengers.values.map((p) => p.name).join(', ')}'
                    : 'You rode with ${r.driverName}'),
                trailing: rideStatusPill(r.status),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TbScope(me: scope.me, site: scope.site, child: RideScreen(r.id)))),
              ),
            ),
          if (loading) const Loading() else if (more && rides.isNotEmpty) OutlinedButton(onPressed: _load, child: const Text('Load more')),
        ]),
      ),
    );
  }
}

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final scope = TbScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: MaxWidth(
        child: StreamBuilder<List<AppNotification>>(
          stream: Repo.I.notifications(scope.me.uid),
          builder: (context, snap) {
            if (snap.hasError) return ErrorNote(Repo.friendly(snap.error!));
            if (!snap.hasData) return const Loading();
            final items = snap.data!;
            if (items.isEmpty) return const EmptyNote('Nothing yet. Ride offers, requests and alerts appear here.');
            return ListView(padding: const EdgeInsets.all(8), children: [
              for (final n in items)
                ListTile(
                  leading: Icon(n.read ? Icons.notifications_none : Icons.notifications_active, color: n.read ? null : tbGreen),
                  title: Text(n.title, style: TextStyle(fontWeight: n.read ? FontWeight.normal : FontWeight.bold)),
                  subtitle: Text('${n.body}\n${minutesAgo(n.at)}'),
                  isThreeLine: true,
                  onTap: () {
                    Repo.I.markRead(scope.me.uid, n.id);
                    if (n.rideId != null) {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => TbScope(me: scope.me, site: scope.site, child: RideScreen(n.rideId!))));
                    } else {
                      Navigator.popUntil(context, (r) => r.isFirst);
                    }
                  },
                ),
            ]);
          },
        ),
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.adminTile});
  final Widget? adminTile;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final me = TbScope.of(context).me;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: MaxWidth(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(me.name, style: Theme.of(context).textTheme.titleMedium),
                LabeledValue('Email', me.email),
                LabeledValue('Phone', me.phone),
                LabeledValue('Employee ID', me.employeeId),
                LabeledValue('Department', me.department),
                LabeledValue('Township', me.townshipLocation),
                LabeledValue('Points', '${me.points} · ${me.noShows} no-show(s)'),
                if (me.isAdmin) const LabeledValue('Role', 'Admin'),
              ]),
            ),
          ),
          SwitchListTile(
            title: const Text('I have a car and can drive colleagues'),
            value: me.hasCar,
            onChanged: (v) => Repo.I.updateMyProfile({'hasCar': v, if (!v) 'lastRole': 'passenger'}),
          ),
          ListTile(leading: const Icon(Icons.edit), title: const Text('Edit phone / department / township'), onTap: () => _edit(me)),
          if (widget.adminTile != null) widget.adminTile!,
          const SectionTitle('Reliable alerts'),
          ListTile(
            leading: const Icon(Icons.notifications),
            title: const Text('Turn on notifications'),
            subtitle: const Text('Needed for ride offers, requests and the "driver is close" alert'),
            onTap: () => runAction(context, () => PushService.I.enable(), done: 'Notifications are on'),
          ),
          const ListTile(
            leading: Icon(Icons.battery_saver),
            title: Text('Battery settings'),
            subtitle: Text('Some phones (Xiaomi, Oppo, Vivo, Samsung) stop apps in the background. Set TravelBuddy to "Unrestricted" / "Don\'t optimise" in your phone\'s battery settings.'),
          ),
          const SectionTitle('About'),
          ListTile(leading: const Icon(Icons.privacy_tip), title: const Text('Privacy policy'), onTap: () => launchUrl(Uri.parse(privacyUrl), mode: LaunchMode.externalApplication)),
          const Text('TravelBuddy 2.0 · free volunteer carpool, no payments.', style: TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Image.asset('assets/images/logo.png', width: 36, height: 36),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('A HomiLabs app', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                ]),
                const SizedBox(height: 8),
                const Text('Designed and built by HomiLabs for the FFL community, to make car sharing between the Township and the Plant reliable and to cut the number of cars on the road.'),
                const SizedBox(height: 8),
                const Text('Acknowledgement', style: TextStyle(fontWeight: FontWeight.w600)),
                const Text('With thanks to Awaiz Fatima for her contribution to TravelBuddy.'),
                const SizedBox(height: 8),
                const Text('© HomiLabs · homilabs.smc@gmail.com', style: TextStyle(fontSize: 12)),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () async {
              if (await confirm(context, 'Log out?', "You'll need your email and password (or Google) to log in again.", yes: 'Log out')) {
                await Repo.I.signOut();
              }
            },
            child: const Text('Log out'),
          ),
          const DeleteAccountLink(),
        ]),
      ),
    );
  }

  Future<void> _edit(UserProfile me) async {
    final phone = TextEditingController(text: me.phone);
    final dept = TextEditingController(text: me.department);
    final town = TextEditingController(text: me.townshipLocation);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Edit profile'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Mobile number')),
          TextField(controller: dept, decoration: const InputDecoration(labelText: 'Department')),
          TextField(controller: town, decoration: const InputDecoration(labelText: 'Township location')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true && mounted) {
      runAction(context, () => Repo.I.updateMyProfile({'phone': phone.text.trim(), 'department': dept.text.trim(), 'townshipLocation': town.text.trim()}), done: 'Saved');
    }
  }
}
