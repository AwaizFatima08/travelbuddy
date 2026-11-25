// Login, registration, Google profile completion, pending approval — same fields and consent text
// as the Android app's LoginScreen / RegisterScreen / CompleteProfileScreen / PendingApprovalScreen.
import 'package:flutter/material.dart';

import '../app/widgets.dart';
import '../core/models.dart';
import '../core/repo.dart';

class AuthFlow extends StatefulWidget {
  const AuthFlow({super.key});
  @override
  State<AuthFlow> createState() => _AuthFlowState();
}

class _AuthFlowState extends State<AuthFlow> {
  var page = 0; // 0 login, 1 register
  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: MaxWidth(
            width: 480,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                const SizedBox(height: 24),
                const _Logo(),
                const SizedBox(height: 24),
                page == 0 ? _Login(onRegister: () => setState(() => page = 1)) : _Register(onLogin: () => setState(() => page = 0)),
                const SizedBox(height: 24),
                const Muted('For FFL employees only. Approved by the TravelBuddy administrator.', center: true, size: 12),
                const Muted('A HomiLabs web app sharing data with the TravelBuddy Android app.', center: true, size: 12),
              ]),
            ),
          ),
        ),
      );
}

class _Logo extends StatelessWidget {
  const _Logo();
  @override
  Widget build(BuildContext context) => Column(children: [
        Container(width: 72, height: 72, decoration: BoxDecoration(color: primary, borderRadius: BorderRadius.circular(20)), child: const Icon(Icons.directions_car_filled, color: Colors.white, size: 40)),
        const SizedBox(height: 12),
        const Text('TravelBuddy', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: primaryDark)),
        const Muted('FFL community carpool · Township ⇄ Plant'),
      ]);
}

class _PasswordField extends StatefulWidget {
  const _PasswordField(this.controller);
  final String label = 'Password';
  final TextEditingController controller;

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  var hide = true;
  @override
  Widget build(BuildContext context) => TextField(
        controller: widget.controller,
        obscureText: hide,
        decoration: InputDecoration(labelText: widget.label, suffixIcon: IconButton(icon: Icon(hide ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => hide = !hide))),
      );
}

class _Login extends StatefulWidget {
  const _Login({required this.onRegister});
  final VoidCallback onRegister;
  @override
  State<_Login> createState() => _LoginState();
}

class _LoginState extends State<_Login> {
  final email = TextEditingController(), pw = TextEditingController();
  var busy = false;
  String? err;

  Future<void> _run(Future<void> Function() f) async {
    setState(() { busy = true; err = null; });
    try {
      await f();
    } catch (e, st) {
      debugPrint('login failed: $e\n$st');
      if (mounted) setState(() => err = Repo.friendly(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _forgot() async {
    final c = TextEditingController(text: email.text.trim());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Password'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Enter your registered employee email to receive a password reset link.'),
          const SizedBox(height: 12),
          TextField(controller: c, decoration: const InputDecoration(labelText: 'Email Address')),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send Link'))],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(() async {
      await Repo.I.resetPassword(c.text);
      if (mounted) toast(context, 'Password reset email sent to ${c.text.trim()}.');
    });
  }

  @override
  Widget build(BuildContext context) => TbCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Welcome back', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const Muted('Sign in with your employee account.'),
          const SizedBox(height: 16),
          TextField(controller: email, keyboardType: TextInputType.emailAddress, autofillHints: const [AutofillHints.email], decoration: const InputDecoration(labelText: 'Email Address')),
          const SizedBox(height: 12),
          _PasswordField(pw),
          ErrorNote(err),
          const SizedBox(height: 12),
          FilledButton(onPressed: busy ? null : () => _run(() => Repo.I.signIn(email.text, pw.text)), child: busy ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('LOG IN')),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: busy ? null : () => _run(() => Repo.I.signInWithGoogle()),
            icon: const Icon(Icons.g_mobiledata, size: 28),
            label: const Text('Continue with Google'),
          ),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            TextButton(onPressed: widget.onRegister, child: const Text('Create Account')),
            TextButton(onPressed: _forgot, child: const Text('Forgot Password?', style: TextStyle(color: textSecondary))),
          ]),
        ]),
      );
}

const consentText = 'I have reviewed and agree to the TravelBuddy workplace commute policies and consent to the app services described above.';

class _ConsentBlock extends StatelessWidget {
  const _ConsentBlock({required this.accepted, required this.onChanged});
  final bool accepted;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: primaryVeryLight, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Eyebrow('App permissions & user consent'),
          const SizedBox(height: 8),
          const Text('Workplace Community Privacy', style: TextStyle(fontWeight: FontWeight.bold)),
          const Muted('Your profile information (Name, Employee ID, Department, Township) is visible exclusively to registered company colleagues for commute coordination.', size: 12.5),
          const SizedBox(height: 6),
          const Text('Commute & Ride Notifications', style: TextStyle(fontWeight: FontWeight.bold)),
          const Muted('The phone app reminds you of commute times and ride updates. On the web, open the app to see your rides.', size: 12.5),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: accepted,
            onChanged: (v) => onChanged(v ?? false),
            title: const Text(consentText, style: TextStyle(fontSize: 13)),
          ),
        ]),
      );
}

class _Register extends StatefulWidget {
  const _Register({required this.onLogin});
  final VoidCallback onLogin;
  @override
  State<_Register> createState() => _RegisterState();
}

class _RegisterState extends State<_Register> {
  final name = TextEditingController(), email = TextEditingController(), pw = TextEditingController(), emp = TextEditingController();
  var dept = MasterData.departments.first;
  var township = MasterData.townshipLocations.first;
  var mode = AppUser.modePassenger;
  var seats = 3;
  var consent = false;
  var busy = false;
  String? err;

  Future<void> _submit() async {
    if (!consent) {
      setState(() => err = 'Please accept the consent statement to continue.');
      return;
    }
    setState(() { busy = true; err = null; });
    try {
      await Repo.I.register(name: name.text, email: email.text, password: pw.text, employeeId: emp.text, department: dept, townshipLocation: township, mode: mode, defaultSeats: seats);
    } catch (e) {
      if (mounted) setState(() => err = Repo.friendly(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => TbCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Employee Registration', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const Muted('Your request goes to the administrator for approval.'),
          const SizedBox(height: 16),
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Full Name')),
          const SizedBox(height: 12),
          TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email Address')),
          const SizedBox(height: 12),
          _PasswordField(pw),
          const SizedBox(height: 12),
          TextField(controller: emp, decoration: const InputDecoration(labelText: 'Employee ID (e.g. FFL-01981)')),
          const SizedBox(height: 12),
          Pick(label: 'Department', value: dept, items: MasterData.departments, onChanged: (v) => setState(() => dept = v)),
          const SizedBox(height: 12),
          Pick(label: 'Township Location', value: township, items: MasterData.townshipLocations, onChanged: (v) => setState(() => township = v)),
          const SizedBox(height: 16),
          const Text('Default Mode Preference', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: AppUser.modePassenger, label: Text('Passenger'), icon: Icon(Icons.hail)), ButtonSegment(value: AppUser.modeDriver, label: Text('Driver'), icon: Icon(Icons.directions_car))],
            selected: {mode},
            onSelectionChanged: (s) => setState(() => mode = s.first),
          ),
          if (mode == AppUser.modeDriver) ...[
            const SizedBox(height: 12),
            _SeatRow(seats: seats, onChanged: (v) => setState(() => seats = v), label: 'Default Passenger Seats'),
          ],
          const SizedBox(height: 16),
          _ConsentBlock(accepted: consent, onChanged: (v) => setState(() => consent = v)),
          ErrorNote(err),
          const SizedBox(height: 12),
          FilledButton(onPressed: busy ? null : _submit, child: busy ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('SUBMIT ACCESS REQUEST')),
          TextButton(onPressed: widget.onLogin, child: const Text('Already have an account? Log in')),
        ]),
      );
}

class _SeatRow extends StatelessWidget {
  const _SeatRow({required this.seats, required this.onChanged, required this.label});
  final int seats;
  final ValueChanged<int> onChanged;
  final String label;
  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500))),
        IconButton.outlined(onPressed: seats > 1 ? () => onChanged(seats - 1) : null, icon: const Icon(Icons.remove)),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('$seats', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
        IconButton.outlined(onPressed: seats < 8 ? () => onChanged(seats + 1) : null, icon: const Icon(Icons.add)),
      ]);
}

/// Signed in with Google but no profile yet (CompleteProfileScreen).
class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key, required this.email, required this.displayName});
  final String email, displayName;
  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final emp = TextEditingController(), phone = TextEditingController();
  var dept = MasterData.departments.first;
  var township = MasterData.townshipLocations.first;
  var mode = AppUser.modePassenger;
  var seats = 3;
  var consent = false;
  var busy = false;
  String? err;

  Future<void> _submit() async {
    if (!consent) {
      setState(() => err = 'Please accept the consent statement to continue.');
      return;
    }
    setState(() { busy = true; err = null; });
    try {
      await Repo.I.completeProfile(employeeId: emp.text, department: dept, townshipLocation: township, mode: mode, defaultSeats: seats, phone: phone.text);
    } catch (e) {
      if (mounted) setState(() => err = Repo.friendly(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: MaxWidth(
            width: 480,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: TbCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Text('Complete Profile', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  Muted('Welcome ${widget.displayName.isEmpty ? 'colleague' : widget.displayName}! Enter your employee details to continue.'),
                  const SizedBox(height: 16),
                  TextField(controller: TextEditingController(text: widget.email), readOnly: true, decoration: const InputDecoration(labelText: 'Email (Google)')),
                  const SizedBox(height: 12),
                  TextField(controller: emp, decoration: const InputDecoration(labelText: 'Employee ID (e.g. FFL-01981)')),
                  const SizedBox(height: 12),
                  TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone Number')),
                  const SizedBox(height: 12),
                  Pick(label: 'Department', value: dept, items: MasterData.departments, onChanged: (v) => setState(() => dept = v)),
                  const SizedBox(height: 12),
                  Pick(label: 'Township Location', value: township, items: MasterData.townshipLocations, onChanged: (v) => setState(() => township = v)),
                  const SizedBox(height: 16),
                  SegmentedButton<String>(
                    segments: const [ButtonSegment(value: AppUser.modePassenger, label: Text('Passenger'), icon: Icon(Icons.hail)), ButtonSegment(value: AppUser.modeDriver, label: Text('Driver'), icon: Icon(Icons.directions_car))],
                    selected: {mode},
                    onSelectionChanged: (s) => setState(() => mode = s.first),
                  ),
                  if (mode == AppUser.modeDriver) ...[const SizedBox(height: 12), _SeatRow(seats: seats, onChanged: (v) => setState(() => seats = v), label: 'Default Passenger Seats')],
                  const SizedBox(height: 16),
                  _ConsentBlock(accepted: consent, onChanged: (v) => setState(() => consent = v)),
                  ErrorNote(err),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: busy ? null : _submit, child: busy ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('SUBMIT ACCESS REQUEST')),
                  TextButton(onPressed: () => Repo.I.signOut(), child: const Text('Sign out')),
                ]),
              ),
            ),
          ),
        ),
      );
}

class PendingScreen extends StatelessWidget {
  const PendingScreen(this.me, {super.key});
  final AppUser me;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Account Verification'), actions: [TextButton(onPressed: () => Repo.I.signOut(), child: const Text('Sign Out'))]),
        body: MaxWidth(
          width: 520,
          child: ListView(padding: const EdgeInsets.all(24), children: [
            const Icon(Icons.hourglass_top, size: 64, color: warningColor),
            const SizedBox(height: 12),
            const Text('Awaiting administrator approval', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Muted('Your access request has been submitted. This page updates by itself the moment the administrator approves you.', center: true),
            const SizedBox(height: 20),
            TbCard(
              child: Column(children: [
                _kv('Name', me.name),
                _kv('Employee ID', me.employeeId.isEmpty ? 'N/A' : me.employeeId),
                _kv('Department', me.department),
                _kv('Submitted', fmtDateTime(me.approvalRequestedAt > 0 ? me.approvalRequestedAt : me.createdAt)),
                _kv('Consent Status', me.consentAcceptedAt > 0 ? 'Accepted (v${me.consentVersion})' : 'Pending'),
              ]),
            ),
            const SizedBox(height: 16),
            FutureBuilder<(String, String)>(
              future: Repo.I.approverInfo(),
              builder: (context, s) {
                final (n, e) = s.data ?? ('Administrator', '');
                return Muted('Approver: $n${e.isEmpty ? '' : ' · $e'}', center: true);
              },
            ),
          ]),
        ),
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [Expanded(child: Muted(k)), Text(v, style: const TextStyle(fontWeight: FontWeight.w600))]),
      );
}

class RestrictedScreen extends StatelessWidget {
  const RestrictedScreen(this.me, {super.key});
  final AppUser me;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Pad(
            all: 24,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.block, size: 64, color: errorColor),
              const SizedBox(height: 12),
              Text(me.isBlocked ? 'Your account has been blocked' : 'Your account has been removed', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Muted('Your account is currently restricted. Please contact the administrator.', center: true),
              if ((me.isBlocked ? me.blockReason : me.removeReason).isNotEmpty) Muted('Reason: ${me.isBlocked ? me.blockReason : me.removeReason}', center: true),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: () => Repo.I.signOut(), child: const Text('Log out')),
            ]),
          ),
        ),
      );
}
