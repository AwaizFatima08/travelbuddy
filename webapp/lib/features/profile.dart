// Profile: account details, editable personal info and travel preferences, password, sign out (ProfileScreen.kt).
import 'package:flutter/material.dart';

import '../app/widgets.dart';
import '../core/models.dart';
import '../core/repo.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.me});
  final AppUser me;
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final name = TextEditingController(text: widget.me.name);
  late final phone = TextEditingController(text: widget.me.phone);
  late String dept = widget.me.department;
  late String township = widget.me.townshipLocation;
  late String pref = widget.me.defaultRolePreference;
  late int seats = widget.me.defaultDriverSeats;
  var busy = false;

  Future<void> _save() async {
    setState(() => busy = true);
    try {
      await Repo.I.updateProfile(name: name.text, phone: phone.text, department: dept, townshipLocation: township, defaultRolePreference: pref, defaultDriverSeats: seats);
      if (mounted) toast(context, 'Profile saved.');
    } catch (e) {
      if (mounted) toast(context, Repo.friendly(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _changePassword() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change password'),
        content: TextField(controller: c, obscureText: true, decoration: const InputDecoration(labelText: 'New password (min 6 characters)')),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Change'))],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await Repo.I.changePassword(c.text);
      if (mounted) toast(context, 'Password changed.');
    } catch (e) {
      if (mounted) toast(context, Repo.friendly(e) == 'requires-recent-login' ? 'Please log out and in again, then change the password.' : Repo.friendly(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = widget.me;
    final deptItems = MasterData.departments.contains(dept) ? MasterData.departments : [...MasterData.departments, dept];
    final townItems = MasterData.townshipLocations.contains(township) ? MasterData.townshipLocations : [...MasterData.townshipLocations, township];
    return MaxWidth(
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          CircleAvatar(radius: 28, backgroundColor: primaryLight, child: Text(me.name.isEmpty ? '?' : me.name[0].toUpperCase(), style: const TextStyle(fontSize: 24, color: primaryDark, fontWeight: FontWeight.bold))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(me.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Muted('${me.employeeId.isEmpty ? 'N/A' : me.employeeId} • ${me.department}'),
            if (me.isAdmin) const Muted('Administrator'),
          ])),
        ]),
        const SizedBox(height: 16),
        TbCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Eyebrow('Account'),
            const SizedBox(height: 8),
            _kv('Email Address', me.email),
            _kv('Employee ID', me.employeeId.isEmpty ? 'N/A' : me.employeeId),
            _kv('Member since', fmtDateTime(me.createdAt)),
            _kv('Status', me.accountStatus),
          ]),
        ),
        const SizedBox(height: 12),
        TbCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Eyebrow('Personal information'),
            const SizedBox(height: 12),
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Full Name')),
            const SizedBox(height: 12),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone Number')),
            const SizedBox(height: 12),
            Pick(label: 'Department', value: dept, items: deptItems, onChanged: (v) => setState(() => dept = v)),
            const SizedBox(height: 12),
            Pick(label: 'Township Location', value: township, items: townItems, onChanged: (v) => setState(() => township = v)),
            const SizedBox(height: 16),
            const Eyebrow('Travel preferences'),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [ButtonSegment(value: AppUser.modePassenger, label: Text('Passenger')), ButtonSegment(value: AppUser.modeDriver, label: Text('Driver'))],
              selected: {pref},
              onSelectionChanged: (s) => setState(() => pref = s.first),
            ),
            const SizedBox(height: 12),
            Row(children: [
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Default Driver Seats'), Muted('Used when you publish a ride', size: 12)])),
              IconButton.outlined(onPressed: seats > 1 ? () => setState(() => seats--) : null, icon: const Icon(Icons.remove)),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('$seats', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
              IconButton.outlined(onPressed: seats < 8 ? () => setState(() => seats++) : null, icon: const Icon(Icons.add)),
            ]),
            const SizedBox(height: 12),
            FilledButton(onPressed: busy ? null : _save, child: const Text('SAVE CHANGES')),
          ]),
        ),
        const SizedBox(height: 12),
        TbCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Eyebrow('Settings & options'),
            ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.lock_outline), title: const Text('Change password'), onTap: _changePassword),
            const ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.notifications_none), title: Text('Commute reminders'), subtitle: Text('Reminders are set in the TravelBuddy Android app on your phone.')),
            ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.logout, color: errorColor), title: const Text('Sign Out', style: TextStyle(color: errorColor, fontWeight: FontWeight.w600)), onTap: () => Repo.I.signOut()),
          ]),
        ),
        const SizedBox(height: 24),
        const Muted('TravelBuddy web 6.0 · HomiLabs · shares its data with the TravelBuddy Android app', center: true, size: 12),
      ]),
    );
  }

  Widget _kv(String k, String v) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [Expanded(child: Muted(k)), Text(v, style: const TextStyle(fontWeight: FontWeight.w600))]));
}
