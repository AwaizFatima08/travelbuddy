// Sign-in (email + Google), registration, consent, pending / blocked / missing-profile screens.
import 'package:flutter/material.dart';

import '../../app/widgets.dart';
import '../../core/models.dart';
import '../../core/repo.dart';

enum _Page { login, register, consent, forgot }

/// Shown when nobody is signed in. [needsProfile] = a Google user who hasn't registered yet.
class AuthFlow extends StatefulWidget {
  const AuthFlow({super.key, this.notice, this.needsProfile = false, this.googleEmail, this.googleName});
  final String? notice;
  final bool needsProfile;
  final String? googleEmail;
  final String? googleName;

  @override
  State<AuthFlow> createState() => _AuthFlowState();
}

class _AuthFlowState extends State<AuthFlow> {
  late _Page page = widget.needsProfile ? _Page.register : _Page.login;
  RegisterForm? form;

  @override
  Widget build(BuildContext context) {
    final body = switch (page) {
      _Page.login => _Login(
          notice: widget.notice,
          onRegister: () => setState(() => page = _Page.register),
          onForgot: () => setState(() => page = _Page.forgot),
        ),
      _Page.register => _Register(
          initial: form,
          googleEmail: widget.googleEmail,
          googleName: widget.googleName,
          onBack: widget.needsProfile ? null : () => setState(() => page = _Page.login),
          onNext: (f) => setState(() {
            form = f;
            page = _Page.consent;
          }),
        ),
      _Page.consent => _Consent(form: form!, google: widget.needsProfile, onBack: () => setState(() => page = _Page.register)),
      _Page.forgot => _Forgot(onBack: () => setState(() => page = _Page.login)),
    };
    return PopScope(
      canPop: page == _Page.login,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => page = page == _Page.consent ? _Page.register : _Page.login);
      },
      child: Scaffold(body: SafeArea(child: MaxWidth(child: body))),
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(24),
        children: [for (final c in children) Padding(padding: const EdgeInsets.only(bottom: 12), child: c)],
      );
}

class _Logo extends StatelessWidget {
  const _Logo();
  @override
  Widget build(BuildContext context) => Column(children: [
        Image.asset('assets/images/logo.png', width: 96, height: 96),
        const SizedBox(height: 8),
        Text('TravelBuddy',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
        const Text('Township ⇄ Plant carpool for the FFL community', textAlign: TextAlign.center),
      ]);
}

class _PasswordField extends StatefulWidget {
  const _PasswordField({required this.controller, this.label = 'Password'});
  final TextEditingController controller;
  final String label;
  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool show = false;
  @override
  Widget build(BuildContext context) => TextField(
        controller: widget.controller,
        obscureText: !show,
        decoration: InputDecoration(
          labelText: widget.label,
          suffixIcon: IconButton(icon: Icon(show ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => show = !show)),
        ),
      );
}

class _Login extends StatefulWidget {
  const _Login({this.notice, required this.onRegister, required this.onForgot});
  final String? notice;
  final VoidCallback onRegister, onForgot;
  @override
  State<_Login> createState() => _LoginState();
}

class _LoginState extends State<_Login> {
  final email = TextEditingController(), password = TextEditingController();
  bool busy = false;
  String? error;

  Future<void> _go(Future<void> Function() f) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await f();
    } catch (e) {
      setState(() => error = Repo.friendly(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _Column(children: [
        const SizedBox(height: 16),
        const _Logo(),
        if (widget.notice != null) Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(widget.notice!))),
        TextField(controller: email, keyboardType: TextInputType.emailAddress, autocorrect: false, decoration: const InputDecoration(labelText: 'Email')),
        _PasswordField(controller: password),
        ErrorNote(error),
        FilledButton(
          onPressed: busy ? null : () => _go(() => Repo.I.signInEmail(email.text, password.text)),
          child: busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Log in'),
        ),
        OutlinedButton.icon(
          onPressed: busy ? null : () => _go(() => Repo.I.signInGoogle()),
          icon: const Icon(Icons.g_mobiledata, size: 28),
          label: const Text('Continue with Google'),
        ),
        Align(alignment: Alignment.centerRight, child: TextButton(onPressed: widget.onForgot, child: const Text('Forgot password?'))),
        OutlinedButton(onPressed: widget.onRegister, child: const Text('New here? Register')),
      ]);
}

class _Register extends StatefulWidget {
  const _Register({this.initial, this.googleEmail, this.googleName, this.onBack, required this.onNext});
  final RegisterForm? initial;
  final String? googleEmail, googleName;
  final VoidCallback? onBack;
  final void Function(RegisterForm) onNext;
  @override
  State<_Register> createState() => _RegisterState();
}

class _RegisterState extends State<_Register> {
  late final name = TextEditingController(text: widget.initial?.name ?? widget.googleName ?? '');
  late final email = TextEditingController(text: widget.initial?.email ?? widget.googleEmail ?? '');
  final password = TextEditingController(), password2 = TextEditingController();
  late final employeeId = TextEditingController(text: widget.initial?.employeeId ?? '');
  late final department = TextEditingController(text: widget.initial?.department ?? '');
  late final phone = TextEditingController(text: widget.initial?.phone ?? '');
  late final township = TextEditingController(text: widget.initial?.townshipLocation ?? '');
  late bool hasCar = widget.initial?.hasCar ?? false;
  String? error;

  bool get google => widget.googleEmail != null;

  String? _validate() {
    final digits = phone.text.replaceAll(RegExp(r'\D'), '');
    if (name.text.trim().length < 3) return 'Please enter your full name.';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.text.trim())) return 'Please enter a valid email address.';
    if (!google && password.text.length < 8) return 'Password must be at least 8 characters.';
    if (!google && password.text != password2.text) return "The two passwords don't match.";
    if (employeeId.text.trim().isEmpty) return 'Please enter your employee ID.';
    if (department.text.trim().isEmpty) return 'Please enter your department.';
    if (digits.length < 10 || digits.length > 13) return 'Please enter a valid mobile number, e.g. 03001234567.';
    if (township.text.trim().isEmpty) return 'Please enter your township location (house / block).';
    return null;
  }

  @override
  Widget build(BuildContext context) => _Column(children: [
        Text('Register', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const Text('An admin will approve your account. Your phone number is visible to approved members so rides can be arranged.'),
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Full name')),
        TextField(controller: email, enabled: !google, keyboardType: TextInputType.emailAddress, autocorrect: false,
            decoration: const InputDecoration(labelText: 'Email (personal or official)')),
        if (!google) _PasswordField(controller: password, label: 'Password (min 8 characters)'),
        if (!google) _PasswordField(controller: password2, label: 'Repeat password'),
        TextField(controller: employeeId, decoration: const InputDecoration(labelText: 'Employee ID')),
        TextField(controller: department, decoration: const InputDecoration(labelText: 'Department')),
        TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Mobile number')),
        TextField(controller: township, decoration: const InputDecoration(labelText: 'Township location (house / block)')),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('I have a car and can drive colleagues'),
          subtitle: const Text('You can change this later in Settings.'),
          value: hasCar,
          onChanged: (v) => setState(() => hasCar = v),
        ),
        ErrorNote(error),
        FilledButton(
          onPressed: () {
            final e = _validate();
            setState(() => error = e);
            if (e == null) {
              widget.onNext(RegisterForm(
                name: name.text, email: email.text, password: password.text, employeeId: employeeId.text,
                department: department.text, phone: phone.text, townshipLocation: township.text, hasCar: hasCar,
              ));
            }
          },
          child: const Text('Next'),
        ),
        if (widget.onBack != null) OutlinedButton(onPressed: widget.onBack, child: const Text('Back'))
        else OutlinedButton(onPressed: () => Repo.I.signOut(), child: const Text('Cancel and sign out')),
      ]);
}

class _Consent extends StatefulWidget {
  const _Consent({required this.form, required this.google, required this.onBack});
  final RegisterForm form;
  final bool google;
  final VoidCallback onBack;
  @override
  State<_Consent> createState() => _ConsentState();
}

class _ConsentState extends State<_Consent> {
  bool agreed = false, busy = false;
  String? error;

  @override
  Widget build(BuildContext context) => _Column(children: [
        Text('Before you join', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('1. TravelBuddy is a free, volunteer carpool between colleagues. No money is involved; each ride is a private arrangement.'),
              SizedBox(height: 10),
              Text('2. Your name, phone, employee ID and department are visible to approved members so rides can be arranged.'),
              SizedBox(height: 10),
              Text('3. Once a ride is locked, your position is shared only with the other people in that ride until pickup. Ride history is deleted after 30 days.'),
            ]),
          ),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: agreed,
          onChanged: (v) => setState(() => agreed = v ?? false),
          title: const Text('I understand and agree'),
        ),
        ErrorNote(error),
        FilledButton(
          onPressed: agreed && !busy
              ? () async {
                  setState(() {
                    busy = true;
                    error = null;
                  });
                  try {
                    if (widget.google) {
                      await Repo.I.createProfile(widget.form);
                    } else {
                      await Repo.I.registerEmail(widget.form);
                    }
                  } catch (e) {
                    setState(() => error = Repo.friendly(e));
                  } finally {
                    if (mounted) setState(() => busy = false);
                  }
                }
              : null,
          child: busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Agree & register'),
        ),
        OutlinedButton(onPressed: busy ? null : widget.onBack, child: const Text('Back')),
      ]);
}

class _Forgot extends StatefulWidget {
  const _Forgot({required this.onBack});
  final VoidCallback onBack;
  @override
  State<_Forgot> createState() => _ForgotState();
}

class _ForgotState extends State<_Forgot> {
  final email = TextEditingController();
  bool sent = false, busy = false;
  String? error;
  @override
  Widget build(BuildContext context) => _Column(children: [
        Text('Reset password', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const Text("We'll email you a link to choose a new password. Check your spam folder too."),
        TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
        ErrorNote(error),
        if (sent) Text('If an account exists for ${email.text.trim()}, a reset email is on its way.', style: const TextStyle(color: tbGreen)),
        FilledButton(
          onPressed: busy
              ? null
              : () async {
                  setState(() => busy = true);
                  try {
                    await Repo.I.sendPasswordReset(email.text);
                    setState(() => sent = true);
                  } catch (e) {
                    setState(() => error = Repo.friendly(e));
                  } finally {
                    if (mounted) setState(() => busy = false);
                  }
                },
          child: const Text('Send reset email'),
        ),
        OutlinedButton(onPressed: widget.onBack, child: const Text('Back to login')),
      ]);
}

// ---------------------------------------------------------------- account states

class PendingScreen extends StatelessWidget {
  const PendingScreen(this.profile, {super.key});
  final UserProfile profile;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: MaxWidth(
            child: ListView(padding: const EdgeInsets.all(24), children: [
              const SizedBox(height: 24),
              const Icon(Icons.hourglass_top, size: 64, color: tbGreen),
              const SizedBox(height: 12),
              Text('Waiting for approval', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text("An admin will check your details. This screen updates by itself as soon as you're approved — you can close the app meanwhile.", textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    LabeledValue('Name', profile.name),
                    LabeledValue('Email', profile.email),
                    LabeledValue('Employee ID', profile.employeeId),
                    LabeledValue('Department', profile.department),
                    LabeledValue('Phone', profile.phone),
                    LabeledValue('Township', profile.townshipLocation),
                    LabeledValue('Has a car', profile.hasCar ? 'Yes' : 'No'),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: () => Repo.I.signOut(), child: const Text('Log out')),
              const DeleteAccountLink(),
            ]),
          ),
        ),
      );
}

class BlockedScreen extends StatelessWidget {
  const BlockedScreen(this.profile, {super.key});
  final UserProfile profile;
  @override
  Widget build(BuildContext context) {
    AuditEntry? last;
    for (final a in profile.audit) {
      if (a.action == 'BLOCKED') last = a;
    }
    return Scaffold(
      body: SafeArea(
        child: MaxWidth(
          child: ListView(padding: const EdgeInsets.all(24), children: [
            const SizedBox(height: 40),
            Icon(Icons.block, size: 64, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text('Account blocked', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Your TravelBuddy account has been blocked by an admin.'
              '${last != null && last.reason.isNotEmpty ? '\n\nReason: ${last.reason}' : ''}'
              '\n\nPlease contact the TravelBuddy admin if you think this is a mistake.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: () => Repo.I.signOut(), child: const Text('Log out')),
            const DeleteAccountLink(),
          ]),
        ),
      ),
    );
  }
}

class DeleteAccountLink extends StatelessWidget {
  const DeleteAccountLink({super.key});
  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: () => showDialog(context: context, builder: (_) => const DeleteAccountDialog()),
        child: Text('Delete my account', style: TextStyle(color: Theme.of(context).colorScheme.error)),
      );
}

class DeleteAccountDialog extends StatefulWidget {
  const DeleteAccountDialog({super.key});
  @override
  State<DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<DeleteAccountDialog> {
  final password = TextEditingController();
  bool busy = false;
  String? error;
  bool get isGoogle => Repo.I.currentUser?.providerData.any((p) => p.providerId == 'google.com') ?? false;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Delete my account?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text("This permanently deletes your TravelBuddy profile and sign-in. Your open rides are cancelled. Past rides are removed automatically within 30 days. This can't be undone."),
          if (!isGoogle) Padding(padding: const EdgeInsets.only(top: 12), child: _PasswordField(controller: password, label: 'Your password')),
          if (isGoogle) const Padding(padding: EdgeInsets.only(top: 12), child: Text("You'll be asked to confirm with Google.")),
          ErrorNote(error),
        ]),
        actions: [
          TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Keep my account')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: busy || (!isGoogle && password.text.isEmpty)
                ? null
                : () async {
                    setState(() {
                      busy = true;
                      error = null;
                    });
                    try {
                      await Repo.I.deleteAccount(password: password.text);
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      setState(() => error = Repo.friendly(e));
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  },
            child: Text(busy ? 'Deleting…' : 'Delete forever'),
          ),
        ],
      );
}
