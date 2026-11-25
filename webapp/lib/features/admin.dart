// Admin: approvals, members, today's rides, management report, audit log, sustainability settings
// (the parts of AdminDashboardScreen.kt that make sense on a laptop; the global-reset tools stay on the phone).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/widgets.dart';
import '../core/models.dart';
import '../core/repo.dart';

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key, required this.me});
  final AppUser me;
  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 5,
        child: Column(children: [
          const TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [Tab(text: 'Approvals'), Tab(text: 'Members'), Tab(text: 'Today'), Tab(text: 'Reports'), Tab(text: 'Audit')]),
          Expanded(child: TabBarView(children: [_Approvals(me: me), _Members(me: me), const _Today(), _Reports(me: me), const _Audit()])),
        ]),
      );
}

class _Approvals extends StatelessWidget {
  const _Approvals({required this.me});
  final AppUser me;
  @override
  Widget build(BuildContext context) => StreamBuilder<List<AppUser>>(
        stream: Repo.I.pendingUsers(),
        builder: (context, s) {
          if (s.hasError) return Center(child: Pad(child: Text(Repo.friendly(s.error!))));
          if (!s.hasData) return const Loading();
          final list = s.data!;
          if (list.isEmpty) return const Center(child: Muted('No pending access requests.'));
          return MaxWidth(
            child: ListView(padding: const EdgeInsets.all(16), children: [
              for (final u in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TbCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(u.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Muted('${u.email} · ${u.employeeId.isEmpty ? 'no employee ID' : u.employeeId} · ${u.department}'),
                      Muted('Township: ${u.townshipLocation} · Prefers ${u.defaultRolePreference.toLowerCase()} · Requested ${fmtDateTime(u.approvalRequestedAt > 0 ? u.approvalRequestedAt : u.createdAt)}'),
                      const SizedBox(height: 8),
                      Row(children: [
                        FilledButton.icon(onPressed: () => _do(context, () => Repo.I.approveUser(me, u), '${u.name} approved.'), icon: const Icon(Icons.check), label: const Text('APPROVE')),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(foregroundColor: errorColor),
                          onPressed: () async {
                            final reason = await askText(context, 'Reject ${u.name}?', hint: 'Reason (shown in the audit log)');
                            if (reason == null || !context.mounted) return;
                            await _do(context, () => Repo.I.removeMember(me, u, reason), '${u.name} rejected.');
                          },
                          child: const Text('REJECT'),
                        ),
                      ]),
                    ]),
                  ),
                ),
            ]),
          );
        },
      );
}

Future<void> _do(BuildContext context, Future<void> Function() f, String ok) async {
  try {
    await f();
    if (context.mounted) toast(context, ok);
  } catch (e) {
    if (context.mounted) toast(context, Repo.friendly(e));
  }
}

class _Members extends StatefulWidget {
  const _Members({required this.me});
  final AppUser me;
  @override
  State<_Members> createState() => _MembersState();
}

class _MembersState extends State<_Members> {
  var q = '';
  var filter = 'ALL';
  @override
  Widget build(BuildContext context) => StreamBuilder<List<AppUser>>(
        stream: Repo.I.members(),
        builder: (context, s) {
          if (s.hasError) return Center(child: Pad(child: Text(Repo.friendly(s.error!))));
          if (!s.hasData) return const Loading();
          final all = s.data!;
          final list = all.where((u) {
            final okF = filter == 'ALL' || u.accountStatus == filter;
            final t = q.toLowerCase();
            final okQ = t.isEmpty || u.name.toLowerCase().contains(t) || u.email.toLowerCase().contains(t) || u.employeeId.toLowerCase().contains(t) || u.department.toLowerCase().contains(t);
            return okF && okQ;
          }).toList();
          return MaxWidth(
            width: 760,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(children: [
                  Expanded(child: TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search name, email, employee ID, department'), onChanged: (v) => setState(() => q = v))),
                  const SizedBox(width: 8),
                  DropdownButton<String>(value: filter, items: const [DropdownMenuItem(value: 'ALL', child: Text('All')), DropdownMenuItem(value: 'ACTIVE', child: Text('Active')), DropdownMenuItem(value: 'PENDING_APPROVAL', child: Text('Pending')), DropdownMenuItem(value: 'BLOCKED', child: Text('Blocked')), DropdownMenuItem(value: 'REMOVED', child: Text('Removed'))], onChanged: (v) => setState(() => filter = v ?? 'ALL')),
                ]),
              ),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Align(alignment: Alignment.centerLeft, child: Muted('${list.length} of ${all.length} members', size: 12))),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final u = list[i];
                    final isMe = u.uid == widget.me.uid;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(backgroundColor: u.isActive ? primaryLight : const Color(0xFFFCE9E7), child: Text(u.name.isEmpty ? '?' : u.name[0].toUpperCase(), style: const TextStyle(color: textPrimary))),
                        title: Row(children: [Expanded(child: Text(u.name.isEmpty ? '(no name)' : u.name)), if (u.isAdmin) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.admin_panel_settings, size: 18, color: primaryDark))]),
                        subtitle: Text('${u.email}\n${u.employeeId.isEmpty ? 'no ID' : u.employeeId} · ${u.department} · ${u.accountStatus}${u.isBlocked && u.blockReason.isNotEmpty ? ' (${u.blockReason})' : ''} · ${kg(u.totalCo2SavedKg)} · ${u.totalCompletedRides} rides'),
                        isThreeLine: true,
                        trailing: isMe
                            ? const Chip(label: Text('you'), visualDensity: VisualDensity.compact)
                            : PopupMenuButton<String>(
                                onSelected: (a) => _action(context, u, a),
                                itemBuilder: (_) => [
                                  if (u.isPending) const PopupMenuItem(value: 'approve', child: Text('Approve')),
                                  if (u.isActive) const PopupMenuItem(value: 'block', child: Text('Block')),
                                  if (u.isBlocked) const PopupMenuItem(value: 'unblock', child: Text('Unblock')),
                                  if (!u.isRemoved) const PopupMenuItem(value: 'remove', child: Text('Remove (deactivate)')),
                                  PopupMenuItem(value: 'role', child: Text(u.isAdmin ? 'Make member' : 'Make admin')),
                                  if (u.phone.isNotEmpty) PopupMenuItem(value: 'call', child: Text('Call ${u.phone}')),
                                ],
                              ),
                      ),
                    );
                  },
                ),
              ),
            ]),
          );
        },
      );

  Future<void> _action(BuildContext context, AppUser u, String a) async {
    final me = widget.me;
    switch (a) {
      case 'approve':
        await _do(context, () => Repo.I.approveUser(me, u), '${u.name} approved.');
      case 'block':
        final reason = await askText(context, 'Block ${u.name}?', hint: 'Reason');
        if (reason == null || !context.mounted) return;
        await _do(context, () => Repo.I.blockMember(me, u, reason), '${u.name} blocked.');
      case 'unblock':
        await _do(context, () => Repo.I.unblockMember(me, u), '${u.name} unblocked.');
      case 'remove':
        final reason = await askText(context, 'Remove ${u.name}?', hint: 'Reason. Rides and CO₂ history are kept.');
        if (reason == null || !context.mounted) return;
        await _do(context, () => Repo.I.removeMember(me, u, reason), '${u.name} removed.');
      case 'role':
        if (await confirm(context, u.isAdmin ? 'Make ${u.name} a normal member?' : 'Make ${u.name} an admin?', u.isAdmin ? 'They lose access to this admin area.' : 'They can approve, block and remove members and see reports.')) {
          if (!context.mounted) return;
          await _do(context, () => Repo.I.setRole(me, u, !u.isAdmin), 'Role updated.');
        }
      case 'call':
        await dial(u.phone);
    }
  }
}

class _Today extends StatelessWidget {
  const _Today();
  @override
  Widget build(BuildContext context) {
    final today = todayKarachi();
    return StreamBuilder<List<Ride>>(
      stream: Repo.I.todayRides(today),
      builder: (context, s) {
        if (s.hasError) return Center(child: Pad(child: Text(Repo.friendly(s.error!))));
        if (!s.hasData) return const Loading();
        final rides = s.data!..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return MaxWidth(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Text('Rides on ${fmtDate(today)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Muted('${rides.where((r) => r.isActive).length} active · ${rides.where((r) => r.status == RideStatus.completed).length} completed · ${rides.where((r) => r.status == RideStatus.cancelled).length} cancelled'),
            const SizedBox(height: 12),
            if (rides.isEmpty) const TbCard(child: Muted('No rides today yet.', center: true)),
            for (final r in rides)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TbCard(
                  child: Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${r.driverName} · ${r.displayPickup} (${PickupSide.label(r.pickupSide)})', style: const TextStyle(fontWeight: FontWeight.bold)),
                      Muted('${r.acceptedPassengerIds.length} / ${r.totalSeats} seats · ${r.completedPassengerIds.length} confirmed · published ${fmtDateTime(r.createdAt)}'),
                    ])),
                    Chip(label: Text(r.status.replaceAll('_', ' '), style: const TextStyle(fontSize: 11)), visualDensity: VisualDensity.compact),
                  ]),
                ),
              ),
          ]),
        );
      },
    );
  }
}

class _Reports extends StatefulWidget {
  const _Reports({required this.me});
  final AppUser me;
  @override
  State<_Reports> createState() => _ReportsState();
}

class _ReportsState extends State<_Reports> {
  var busy = false;

  Future<void> _refresh() async {
    setState(() => busy = true);
    try {
      await Repo.I.recalculateReport();
      if (mounted) toast(context, 'Report recalculated from all completed rides.');
    } catch (e) {
      if (mounted) toast(context, Repo.friendly(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _copyCsv(ManagementReport r) async {
    final b = StringBuffer('serial,name,kg_co2,rides_as_driver,rides_as_passenger\n');
    for (final row in r.rows) {
      b.writeln('${row.serialNumber},"${row.personName.replaceAll('"', '""')}",${row.co2Saved.toStringAsFixed(2)},${row.ridesAsDriver},${row.ridesAsPassenger}');
    }
    await Clipboard.setData(ClipboardData(text: b.toString()));
    if (mounted) toast(context, 'CSV copied to the clipboard. Paste it into a spreadsheet.');
  }

  Future<void> _editSustainability() async {
    final c = await Repo.I.sustainability();
    final km = TextEditingController(text: c.baselineDistanceKm.toString());
    final f = TextEditingController(text: c.co2FactorKgPerKm.toString());
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('CO₂ calculation'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: km, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Baseline distance per avoided trip (km)')),
          const SizedBox(height: 12),
          TextField(controller: f, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'CO₂ factor (kg per km)')),
          const SizedBox(height: 8),
          const Muted('Used by both the phone app and the web app for every new completed ride.', size: 12),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save'))],
      ),
    );
    if (ok != true || !mounted) return;
    await _do(context, () => Repo.I.updateSustainability(double.tryParse(km.text) ?? 0, double.tryParse(f.text) ?? 0), 'Saved.');
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<ManagementReport>(
        stream: Repo.I.managementReport(),
        builder: (context, s) {
          if (s.hasError) return Center(child: Pad(child: Text(Repo.friendly(s.error!))));
          if (!s.hasData) return const Loading();
          final r = s.data!;
          return MaxWidth(
            width: 760,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Row(children: [
                const Expanded(child: Text('Management report', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                IconButton(tooltip: 'CO₂ settings', onPressed: _editSustainability, icon: const Icon(Icons.tune)),
                OutlinedButton.icon(onPressed: r.rows.isEmpty ? null : () => _copyCsv(r), icon: const Icon(Icons.copy), label: const Text('CSV')),
                const SizedBox(width: 8),
                FilledButton.icon(onPressed: busy ? null : _refresh, icon: const Icon(Icons.refresh), label: const Text('REFRESH')),
              ]),
              Muted('Last updated: ${fmtDateTime(r.updatedAt)}. Refresh reads every member and completed ride, so use it when needed, not constantly.', size: 12),
              const SizedBox(height: 12),
              Row(children: [
                _tile('Members', '${r.totalMembers}'),
                _tile('CO₂ saved', kg(r.totalCo2Saved)),
                _tile('Driver rides', '${r.totalDriverRides}'),
                _tile('Passenger trips', '${r.totalPassengerRides}'),
              ]),
              const SizedBox(height: 12),
              if (r.rows.isEmpty)
                const TbCard(child: Muted('No report yet. Press REFRESH to build it.', center: true))
              else
                Card(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columnSpacing: 20,
                      columns: const [DataColumn(label: Text('#')), DataColumn(label: Text('Name')), DataColumn(label: Text('kg CO₂'), numeric: true), DataColumn(label: Text('As driver'), numeric: true), DataColumn(label: Text('As passenger'), numeric: true)],
                      rows: [for (final row in r.rows) DataRow(cells: [DataCell(Text('${row.serialNumber}')), DataCell(Text(row.personName)), DataCell(Text(row.co2Saved.toStringAsFixed(2))), DataCell(Text('${row.ridesAsDriver}')), DataCell(Text('${row.ridesAsPassenger}'))])],
                    ),
                  ),
                ),
            ]),
          );
        },
      );

  Widget _tile(String k, String v) => Expanded(child: Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [Text(v, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryDark)), Muted(k, size: 12)]))));
}

class _Audit extends StatelessWidget {
  const _Audit();
  @override
  Widget build(BuildContext context) => StreamBuilder<List<AuditLog>>(
        stream: Repo.I.auditLogs(),
        builder: (context, s) {
          if (s.hasError) return Center(child: Pad(child: Text(Repo.friendly(s.error!))));
          if (!s.hasData) return const Loading();
          final logs = s.data!;
          if (logs.isEmpty) return const Center(child: Muted('No admin actions recorded yet.'));
          return MaxWidth(
            width: 760,
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: logs.length,
              itemBuilder: (context, i) {
                final l = logs[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.history),
                    title: Text('${l.action.replaceAll('_', ' ')} · ${l.targetName.isEmpty ? l.targetUid : l.targetName}'),
                    subtitle: Text('${l.reason.isEmpty ? '' : '${l.reason}\n'}by ${l.adminName.isEmpty ? l.adminEmail : l.adminName} · ${fmtDateTime(l.timestamp)}'),
                    isThreeLine: l.reason.isNotEmpty,
                  ),
                );
              },
            ),
          );
        },
      );
}
