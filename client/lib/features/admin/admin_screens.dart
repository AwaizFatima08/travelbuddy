// Admin: approvals, members & audit, places editor, windows editor, disputes, reports, site setup.
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../app/widgets.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../more/more_screens.dart' show ymOf;
import '../../services/live_share.dart';

class AdminHome extends StatelessWidget {
  const AdminHome({super.key});
  @override
  Widget build(BuildContext context) {
    final scope = TbScope.of(context);
    Widget go(String title, IconData icon, Widget screen) => ListTile(
          leading: Icon(icon),
          title: Text(title),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TbScope(me: scope.me, site: scope.site, child: screen))),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Admin')),
      body: MaxWidth(
        child: ListView(padding: const EdgeInsets.all(8), children: [
          go('Members & audit', Icons.people, const MembersScreen()),
          go('Pickup places', Icons.place, const PlacesEditor()),
          go('Commute windows', Icons.schedule, const WindowsEditor()),
          go('No-show disputes', Icons.gavel, const DisputesScreen()),
          go('Reports', Icons.bar_chart, const ReportsScreen()),
          const SectionTitle('Waiting for approval'),
          StreamBuilder<List<UserProfile>>(
            stream: Repo.I.pendingUsers(),
            builder: (context, snap) {
              if (snap.hasError) return ErrorNote(Repo.friendly(snap.error!));
              if (!snap.hasData) return const Loading();
              if (snap.data!.isEmpty) return const EmptyNote('No one is waiting. 🎉');
              return Column(children: [for (final u in snap.data!) MemberCard(u)]);
            },
          ),
        ]),
      ),
    );
  }
}

class MemberCard extends StatefulWidget {
  const MemberCard(this.user, {super.key, this.onChanged});
  final UserProfile user;
  final VoidCallback? onChanged;
  @override
  State<MemberCard> createState() => _MemberCardState();
}

class _MemberCardState extends State<MemberCard> {
  bool showAudit = false, busy = false;

  Future<void> _do(String action) async {
    final u = widget.user;
    final title = {'APPROVED': 'Approve ${u.name}?', 'BLOCKED': 'Block ${u.name}?', 'UNBLOCKED': 'Unblock ${u.name}?'}[action]!;
    final label = {'APPROVED': 'Approve', 'BLOCKED': 'Block', 'UNBLOCKED': 'Unblock'}[action]!;
    final reason = await askReason(context, title, label, required: action != 'APPROVED');
    if (reason == null || !mounted) return;
    setState(() => busy = true);
    await runAction(context, () => Repo.I.adminAction(u.uid, action, reason, TbScope.of(context).me), done: '${u.name}: ${action.toLowerCase()}');
    widget.onChanged?.call();
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    final me = TbScope.of(context).me;
    final color = switch (u.status) {
      AccountStatus.active => tbGreen,
      AccountStatus.pending => const Color(0xFFC77700),
      AccountStatus.blocked => Theme.of(context).colorScheme.error,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(u.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
            Pill(u.role == 'ADMIN' ? '${u.status.name.toUpperCase()} · ADMIN' : u.status.name.toUpperCase(), color: color),
          ]),
          LabeledValue('Email', u.email),
          LabeledValue('Employee ID', u.employeeId),
          LabeledValue('Department', u.department),
          LabeledValue('Phone', u.phone),
          LabeledValue('Township', u.townshipLocation),
          LabeledValue('Car', u.hasCar ? 'Yes' : 'No'),
          LabeledValue('Points', '${u.points} · ${u.noShows} no-show(s)'),
          if (u.audit.isNotEmpty) TextButton(onPressed: () => setState(() => showAudit = !showAudit), child: Text(showAudit ? 'Hide audit trail' : 'Audit trail (${u.audit.length})')),
          if (showAudit)
            for (final a in u.audit.reversed)
              Text('• ${a.action} by ${a.byName}${a.at != null ? ' · ${a.at!.toLocal().toString().substring(0, 16)}' : ''}${a.reason.isNotEmpty ? '\n   “${a.reason}”' : ''}', style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 6),
          if (u.uid != me.uid)
            Wrap(spacing: 8, children: [
              if (u.status == AccountStatus.pending) FilledButton(onPressed: busy ? null : () => _do('APPROVED'), child: const Text('Approve')),
              if (u.status != AccountStatus.blocked)
                OutlinedButton(onPressed: busy ? null : () => _do('BLOCKED'), style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error), child: const Text('Block')),
              if (u.status == AccountStatus.blocked) FilledButton(onPressed: busy ? null : () => _do('UNBLOCKED'), child: const Text('Unblock')),
              CallButton(u.phone),
            ]),
        ]),
      ),
    );
  }
}

class MembersScreen extends StatefulWidget {
  const MembersScreen({super.key});
  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  List<UserProfile>? recent, found;
  final q = TextEditingController();
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Repo.I.recentAdminActions();
      setState(() => recent = r);
    } catch (e) {
      setState(() => error = Repo.friendly(e));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Members & audit')),
        body: MaxWidth(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            const SectionTitle('Find a member'),
            Row(children: [
              Expanded(child: TextField(controller: q, decoration: const InputDecoration(labelText: 'Email or employee ID'))),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () async {
                  try {
                    final f = await Repo.I.findUsers(q.text);
                    setState(() => found = f);
                  } catch (e) {
                    setState(() => error = Repo.friendly(e));
                  }
                },
                child: const Text('Find'),
              ),
            ]),
            if (found != null && found!.isEmpty) const Text('No member found.'),
            for (final u in found ?? const <UserProfile>[]) MemberCard(u, onChanged: () async => setState(() => found = null)),
            ErrorNote(error),
            const SectionTitle('Recent admin actions (last 30)'),
            if (recent == null) const Loading() else if (recent!.isEmpty) const EmptyNote('No admin actions yet.'),
            for (final u in recent ?? const <UserProfile>[]) MemberCard(u, onChanged: _load),
          ]),
        ),
      );
}

class PlacesEditor extends StatefulWidget {
  const PlacesEditor({super.key});
  @override
  State<PlacesEditor> createState() => _PlacesEditorState();
}

class _PlacesEditorState extends State<PlacesEditor> {
  late List<Place> places = List.of(TbScope.of(context).site.places);
  bool dirty = false, saving = false;

  Future<void> _save() async {
    final site = TbScope.of(context).site;
    setState(() => saving = true);
    final ordered = <Place>[];
    var i = 0;
    for (final side in Side.values) {
      for (final p in places.where((p) => p.side == side)) {
        ordered.add(p.copyWith(order: i++));
      }
    }
    final ok = await runAction(context, () => Repo.I.saveSite(Site(
          id: site.id, name: site.name, timezone: site.timezone, places: ordered, windows: site.windows,
          legKm: site.legKm, co2PerKm: site.co2PerKm, matchMinutes: site.matchMinutes,
        )), done: 'Places saved');
    if (ok) dirty = false;
    if (mounted) setState(() => saving = false);
  }

  void _move(Place p, int dir) {
    final sameSide = places.where((x) => x.side == p.side).toList();
    final i = sameSide.indexOf(p);
    final j = i + dir;
    if (j < 0 || j >= sameSide.length) return;
    final other = sameSide[j];
    final a = places.indexOf(p), b = places.indexOf(other);
    setState(() {
      places[a] = other;
      places[b] = p;
      dirty = true;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Pickup places'), actions: [TextButton(onPressed: dirty && !saving ? _save : null, child: const Text('SAVE'))]),
        body: MaxWidth(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            const Text('Stand at the place and tap "Use my GPS" to capture its point. Neighbours = places close enough to share a pickup. Tap SAVE when done.', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            FilledButton.tonal(onPressed: () => _editDialog(null), child: const Text('Add place')),
            for (final side in Side.values) ...[
              SectionTitle(side == Side.township ? 'Township' : 'Plant'),
              for (final p in places.where((p) => p.side == side))
                Card(
                  color: p.active ? null : Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: ListTile(
                    title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${p.hasPoint ? '${p.lat.toStringAsFixed(5)}, ${p.lng.toStringAsFixed(5)}' : '⚠ no map point'}'
                        '${p.neighbours.isNotEmpty ? ' · near: ${p.neighbours.map((n) => places.where((x) => x.id == n).firstOrNull?.name ?? n).join(', ')}' : ''}'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Switch(value: p.active, onChanged: (v) => setState(() {
                            places[places.indexOf(p)] = p.copyWith(active: v);
                            dirty = true;
                          })),
                      IconButton(onPressed: () => _editDialog(p), icon: const Icon(Icons.edit)),
                      IconButton(onPressed: () => _move(p, -1), icon: const Icon(Icons.arrow_upward)),
                      IconButton(onPressed: () => _move(p, 1), icon: const Icon(Icons.arrow_downward)),
                    ]),
                  ),
                ),
            ],
          ]),
        ),
      );

  Future<void> _editDialog(Place? existing) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final lat = TextEditingController(text: existing != null && existing.hasPoint ? existing.lat.toString() : '');
    final lng = TextEditingController(text: existing != null && existing.hasPoint ? existing.lng.toString() : '');
    var side = existing?.side ?? Side.township;
    var neighbours = List<String>.of(existing?.neighbours ?? const []);
    var locating = false;
    final result = await showDialog<Place>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text(existing == null ? 'Add place' : 'Edit place'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
              SegmentedButton<Side>(
                segments: const [ButtonSegment(value: Side.township, label: Text('Township')), ButtonSegment(value: Side.plant, label: Text('Plant'))],
                selected: {side},
                onSelectionChanged: (s) => setD(() => side = s.first),
              ),
              TextField(controller: lat, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Latitude')),
              TextField(controller: lng, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Longitude')),
              OutlinedButton.icon(
                onPressed: locating
                    ? null
                    : () async {
                        setD(() => locating = true);
                        try {
                          if (!await LiveShare.ensurePermission()) throw AppError('Allow location for TravelBuddy first.');
                          final p = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.best));
                          lat.text = p.latitude.toStringAsFixed(6);
                          lng.text = p.longitude.toStringAsFixed(6);
                          if (c.mounted) toast(c, 'Captured (±${p.accuracy.toInt()} m)');
                        } catch (e) {
                          if (c.mounted) toast(c, "Couldn't get a GPS fix. Go outside and try again.");
                        }
                        setD(() => locating = false);
                      },
                icon: const Icon(Icons.my_location),
                label: Text(locating ? 'Getting GPS…' : 'Use my GPS'),
              ),
              const SizedBox(height: 8),
              const Align(alignment: Alignment.centerLeft, child: Text('Neighbours (share pickups):')),
              Wrap(spacing: 6, children: [
                for (final p in places.where((p) => p.id != existing?.id && p.side == side))
                  FilterChip(
                    label: Text(p.name),
                    selected: neighbours.contains(p.id),
                    onSelected: (v) => setD(() => v ? neighbours.add(p.id) : neighbours.remove(p.id)),
                  ),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            FilledButton(
              onPressed: name.text.trim().isEmpty
                  ? null
                  : () {
                      final la = double.tryParse(lat.text) ?? 0, lo = double.tryParse(lng.text) ?? 0;
                      if (la.abs() > 90 || lo.abs() > 180) return;
                      final id = existing?.id ?? name.text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
                      Navigator.pop(c, Place(id: id, name: name.text.trim(), side: side, lat: la, lng: lo, active: existing?.active ?? true, order: existing?.order ?? 99, neighbours: neighbours));
                    },
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    setState(() {
      final i = places.indexWhere((p) => p.id == result.id);
      if (i >= 0) {
        places[i] = result;
      } else {
        places.add(result);
      }
      dirty = true;
    });
  }
}

class WindowsEditor extends StatefulWidget {
  const WindowsEditor({super.key});
  @override
  State<WindowsEditor> createState() => _WindowsEditorState();
}

class _WindowsEditorState extends State<WindowsEditor> {
  late List<CommuteWindow> windows = List.of(TbScope.of(context).site.windows);
  bool dirty = false;

  @override
  Widget build(BuildContext context) {
    final site = TbScope.of(context).site;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Commute windows'),
        actions: [
          TextButton(
            onPressed: dirty
                ? () async {
                    final ok = await runAction(context, () => Repo.I.saveSite(Site(
                          id: site.id, name: site.name, timezone: site.timezone, places: site.places,
                          windows: [for (var i = 0; i < windows.length; i++) CommuteWindow(id: windows[i].id, name: windows[i].name, from: windows[i].from, to: windows[i].to, start: windows[i].start, end: windows[i].end, active: windows[i].active, order: i)],
                          legKm: site.legKm, co2PerKm: site.co2PerKm, matchMinutes: site.matchMinutes,
                        )), done: 'Windows saved');
                    if (ok) setState(() => dirty = false);
                  }
                : null,
            child: const Text('SAVE'),
          ),
        ],
      ),
      body: MaxWidth(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('Times are 24-hour, site-local. Add shift windows here later (e.g. 06:00 / 14:00 / 22:00).', style: TextStyle(fontSize: 12)),
          FilledButton.tonal(onPressed: () => _edit(null), child: const Text('Add window')),
          for (final w in windows)
            Card(
              child: ListTile(
                title: Text('${w.name} ${w.start}–${w.end}'),
                subtitle: Text(w.directionLabel),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Switch(value: w.active, onChanged: (v) => setState(() {
                        windows[windows.indexOf(w)] = CommuteWindow(id: w.id, name: w.name, from: w.from, to: w.to, start: w.start, end: w.end, active: v, order: w.order);
                        dirty = true;
                      })),
                  IconButton(onPressed: () => _edit(w), icon: const Icon(Icons.edit)),
                ]),
              ),
            ),
        ]),
      ),
    );
  }

  Future<void> _edit(CommuteWindow? w) async {
    final name = TextEditingController(text: w?.name ?? '');
    final start = TextEditingController(text: w?.start ?? '07:00');
    final end = TextEditingController(text: w?.end ?? '07:40');
    var from = w?.from ?? Side.township;
    final re = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');
    final r = await showDialog<CommuteWindow>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text(w == null ? 'Add window' : 'Edit window'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
            SegmentedButton<Side>(
              segments: const [ButtonSegment(value: Side.township, label: Text('To Plant')), ButtonSegment(value: Side.plant, label: Text('To Township'))],
              selected: {from},
              onSelectionChanged: (s) => setD(() => from = s.first),
            ),
            TextField(controller: start, decoration: const InputDecoration(labelText: 'Start (HH:mm)')),
            TextField(controller: end, decoration: const InputDecoration(labelText: 'End (HH:mm)')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty || !re.hasMatch(start.text) || !re.hasMatch(end.text)) return;
                Navigator.pop(c, CommuteWindow(
                  id: w?.id ?? name.text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_'),
                  name: name.text.trim(), from: from, to: from == Side.township ? Side.plant : Side.township,
                  start: start.text, end: end.text, active: w?.active ?? true, order: w?.order ?? windows.length,
                ));
              },
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
    if (r == null) return;
    setState(() {
      final i = windows.indexWhere((x) => x.id == r.id);
      if (i >= 0) {
        windows[i] = r;
      } else {
        windows.add(r);
      }
      dirty = true;
    });
  }
}

class DisputesScreen extends StatefulWidget {
  const DisputesScreen({super.key});
  @override
  State<DisputesScreen> createState() => _DisputesScreenState();
}

class _DisputesScreenState extends State<DisputesScreen> {
  List<Ride>? rides;
  String? error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    try {
      final r = await Repo.I.ridesWithOpenDisputes(TbScope.of(context).me.siteId);
      setState(() => rides = r);
    } catch (e) {
      setState(() => error = Repo.friendly(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final site = TbScope.of(context).site;
    return Scaffold(
      appBar: AppBar(title: const Text('No-show disputes')),
      body: MaxWidth(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          ErrorNote(error),
          if (rides == null) const Loading() else if (rides!.isEmpty) const EmptyNote('No open disputes.'),
          for (final r in rides ?? const <Ride>[])
            for (final e in r.noShowReports.entries)
              if ((e.value as Map)['disputed'] == true && (e.value as Map)['resolved'] != true)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${windowLabelFor(site, r.windowId, r.date)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text('Reported: ${e.key == r.driverId ? r.driverName : (r.passengers[e.key]?.name ?? e.key)}'),
                      Text('By: ${(e.value as Map)['byName'] ?? ''}'),
                      Text('Driver ${r.driverName} · passengers ${r.passengers.values.map((p) => p.name).join(', ')}'),
                      const SizedBox(height: 6),
                      Wrap(spacing: 8, children: [
                        FilledButton(onPressed: () => runAction(context, () => Repo.I.resolveNoShow(r.id, e.key, true), done: 'Upheld').then((_) => _load()), child: const Text('Uphold')),
                        OutlinedButton(onPressed: () => runAction(context, () => Repo.I.resolveNoShow(r.id, e.key, false), done: 'Cancelled — points restored').then((_) => _load()), child: const Text('Cancel report')),
                        CallButton(e.key == r.driverId ? r.driverPhone : (r.passengers[e.key]?.phone ?? '')),
                      ]),
                    ]),
                  ),
                ),
        ]),
      ),
    );
  }
}

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late String ym = ymOf(DateTime.now());
  Map<String, dynamic>? report;
  bool loading = false;
  String? error;

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final r = await Repo.I.adminReport(TbScope.of(context).me.siteId, ym);
      setState(() => report = r);
    } catch (e) {
      setState(() => error = Repo.friendly(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final site = TbScope.of(context).site;
    final r = report;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          IconButton(onPressed: () => setState(() => ym = _shift(ym, -1)), icon: const Icon(Icons.chevron_left)),
          Center(child: Text(ym, style: const TextStyle(fontWeight: FontWeight.bold))),
          IconButton(onPressed: () => setState(() => ym = _shift(ym, 1)), icon: const Icon(Icons.chevron_right)),
        ],
      ),
      body: MaxWidth(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('Loaded only when you tap the button.', style: TextStyle(fontSize: 12)),
          FilledButton(onPressed: loading ? null : _load, child: Text(r == null ? 'Load report' : 'Reload')),
          if (loading) const Loading(),
          ErrorNote(error),
          if (r != null) ...[
            SectionTitle('Month ${r['month']}'),
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
              LabeledValue('Rides', '${r['rides']}'),
              LabeledValue('Seats shared', '${r['seats']}'),
              LabeledValue('CO₂ saved', '${((r['totals']?['kgSaved'] ?? 0) as num).toStringAsFixed(1)} kg'),
              for (final e in (r['byStatus'] as Map).entries) LabeledValue('  ${e.key}', '${e.value}'),
            ]))),
            const SectionTitle('Completed by window'),
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
              for (final e in (r['byWindow'] as Map).entries) LabeledValue(site.window(e.key as String)?.name ?? e.key as String, '${e.value}'),
              if ((r['byWindow'] as Map).isEmpty) const Text('—'),
            ]))),
            const SectionTitle('By department'),
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
              for (final e in (r['byDept'] as Map).entries)
                LabeledValue('${e.key}', '${(e.value as Map)['points']} pts · ${(e.value as Map)['legs']} legs · ${((e.value as Map)['kgSaved'] as num).toStringAsFixed(1)} kg'),
              if ((r['byDept'] as Map).isEmpty) const Text('—'),
            ]))),
            const SectionTitle('Members'),
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
              for (final e in (r['members'] as Map).entries) LabeledValue('${e.key}', '${e.value}'),
            ]))),
            const SectionTitle('Top 20 members'),
            ...(() {
              final users = (r['users'] as Map).entries.map((e) => MonthlyRow.fromMap(e.key as String, Map<String, dynamic>.from(e.value as Map))).toList()
                ..sort((a, b) => b.points.compareTo(a.points));
              return [for (final u in users.take(20)) ListTile(dense: true, title: Text(u.name), subtitle: Text(u.department), trailing: Text('${u.points} pts · ${u.driverLegs}D/${u.passengerLegs}P'))];
            })(),
          ],
        ]),
      ),
    );
  }

  String _shift(String ym, int m) {
    final p = ym.split('-').map(int.parse).toList();
    return ymOf(DateTime(p[0], p[1] + m));
  }
}

/// Shown to an admin when no site exists yet.
class CreateSiteScreen extends StatelessWidget {
  const CreateSiteScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: MaxWidth(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.location_city, size: 64, color: tbGreen),
                const SizedBox(height: 12),
                Text('Set up the FFL site', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('This creates the Township and Plant places and the four commute windows. You can edit them afterwards in Admin.', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: () => runAction(context, () => Repo.I.createDefaultSite(), done: 'Site created'), child: const Text('Create FFL site')),
                TextButton(onPressed: () => Repo.I.signOut(), child: const Text('Log out')),
              ]),
            ),
          ),
        ),
      );
}
