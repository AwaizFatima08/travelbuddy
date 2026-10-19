// Small shared widgets and helpers used by every screen.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/clock.dart';
import '../core/models.dart';

const tbGreen = Color(0xFF12704A);
const tbAmber = Color(0xFFF2A516);

/// The signed-in member, their site and the site clock — available to every screen below the shell.
class TbScope extends InheritedWidget {
  const TbScope({super.key, required this.me, required this.site, required super.child});
  final UserProfile me;
  final Site site;
  SiteClock get clock => SiteClock(site);

  static TbScope of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<TbScope>()!;

  @override
  bool updateShouldNotify(TbScope old) => old.me != me || old.site != site;
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

Future<void> dial(String phone) async {
  if (phone.trim().isEmpty) return;
  final uri = Uri(scheme: 'tel', path: phone.trim());
  try {
    await launchUrl(uri);
  } catch (_) {}
}

/// Keeps content phone-width on wide screens (web on a laptop).
class MaxWidth extends StatelessWidget {
  const MaxWidth({super.key, required this.child, this.width = 560});
  final Widget child;
  final double width;
  @override
  Widget build(BuildContext context) =>
      Center(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: width), child: child));
}

class Loading extends StatelessWidget {
  const Loading({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
}

class EmptyNote extends StatelessWidget {
  const EmptyNote(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(32),
        child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}

class ErrorNote extends StatelessWidget {
  const ErrorNote(this.text, {super.key});
  final String? text;
  @override
  Widget build(BuildContext context) => (text == null || text!.isEmpty)
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(text!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 6),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
      );
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, required this.color});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
      );
}

Widget rideStatusPill(RideStatus s) => switch (s) {
      RideStatus.locked => const Pill('LOCKED', color: Color(0xFF5B6CC2)),
      RideStatus.pickedUp => const Pill('ON THE WAY', color: Color(0xFFC77700)),
      RideStatus.completed => const Pill('COMPLETED', color: Color(0xFF546E7A)),
      RideStatus.cancelled => const Pill('CANCELLED', color: Color(0xFFB3261E)),
      RideStatus.noShow => const Pill('NO-SHOW', color: Color(0xFFB3261E)),
    };

class LabeledValue extends StatelessWidget {
  const LabeledValue(this.label, this.value, {super.key});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 120, child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
            Expanded(child: Text(value.isEmpty ? '—' : value)),
          ],
        ),
      );
}

class CallButton extends StatelessWidget {
  const CallButton(this.phone, {super.key, this.label = 'Call'});
  final String phone;
  final String label;
  @override
  Widget build(BuildContext context) => FilledButton.tonalIcon(
        onPressed: phone.isEmpty ? null : () => dial(phone),
        icon: const Icon(Icons.call, size: 18),
        label: Text(label),
      );
}

Future<bool> confirm(BuildContext context, String title, String text, {String yes = 'Yes', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(text),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Back')),
        TextButton(
          onPressed: () => Navigator.pop(c, true),
          style: danger ? TextButton.styleFrom(foregroundColor: Theme.of(c).colorScheme.error) : null,
          child: Text(yes),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Asks for a short reason. Returns null if cancelled.
Future<String?> askReason(BuildContext context, String title, String confirmLabel, {bool required = true}) {
  final ctl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctl,
          maxLength: 200,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: required ? 'Reason (required)' : 'Reason (optional)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Back')),
          TextButton(
            onPressed: (!required || ctl.text.trim().isNotEmpty) ? () => Navigator.pop(c, ctl.text.trim()) : null,
            child: Text(confirmLabel),
          ),
        ],
      ),
    ),
  );
}

/// Runs an async action, shows the result or the error as a toast.
Future<bool> runAction(BuildContext context, Future<void> Function() action, {String? done}) async {
  try {
    await action();
    if (context.mounted && done != null) toast(context, done);
    return true;
  } catch (e) {
    if (context.mounted) toast(context, e.toString());
    return false;
  }
}

/// Straight-line distance in metres.
double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  final dLat = _rad(lat2 - lat1), dLng = _rad(lng2 - lng1);
  final a = _sin2(dLat / 2) + _cos(_rad(lat1)) * _cos(_rad(lat2)) * _sin2(dLng / 2);
  return 2 * r * _asin(_sqrt(a));
}

double _rad(double d) => d * 3.141592653589793 / 180;
double _sin2(double x) {
  final s = _sin(x);
  return s * s;
}

double _sin(double x) => _taylorSin(x);
double _cos(double x) => _taylorSin(x + 1.5707963267948966);
double _asin(double x) => x.abs() >= 1 ? (x > 0 ? 1.5707963267948966 : -1.5707963267948966) : _atan(x / _sqrt(1 - x * x));
double _sqrt(double x) {
  if (x <= 0) return 0;
  var g = x;
  for (var i = 0; i < 30; i++) {
    g = (g + x / g) / 2;
  }
  return g;
}

double _taylorSin(double x) {
  x = x % (2 * 3.141592653589793);
  if (x > 3.141592653589793) x -= 2 * 3.141592653589793;
  if (x < -3.141592653589793) x += 2 * 3.141592653589793;
  double term = x, sum = x;
  for (var i = 1; i < 10; i++) {
    term *= -x * x / ((2 * i) * (2 * i + 1));
    sum += term;
  }
  return sum;
}

double _atan(double x) {
  if (x.abs() > 1) return (x > 0 ? 1.5707963267948966 : -1.5707963267948966) - _atan(1 / x);
  double term = x, sum = x;
  final x2 = x * x;
  for (var i = 1; i < 25; i++) {
    term *= -x2;
    sum += term / (2 * i + 1);
  }
  return sum;
}

/// "~1.2 km, ~3 min" at a walking-plus-driving pace suitable for a 2 km township.
String etaText(double meters) {
  final dist = meters < 1000 ? '~${(meters / 10).round() * 10} m' : '~${(meters / 1000).toStringAsFixed(1)} km';
  final min = (meters / 1000 / 25 * 60).ceil().clamp(1, 999);
  return '$dist, ~$min min';
}

const approachMeters = 300.0;
bool isApproaching(double meters) => meters < approachMeters;

String staleText(DateTime? at) {
  if (at == null) return '';
  final age = DateTime.now().difference(at);
  return age.inMinutes >= 2 ? 'last updated ${age.inMinutes} min ago' : '';
}

String windowLabelFor(Site site, String windowId, String date) {
  final w = site.window(windowId);
  return w == null ? prettyDate(date) : '${prettyDate(date)} · ${w.name} ${w.start}–${w.end}';
}

/// "Mon 20 Oct · Township → Plant" (+ slot name when the ride falls in a decided slot).
String rideWhen(Site site, String windowId, String date, Direction direction) {
  final w = site.window(windowId);
  return '${prettyDate(date)} · ${direction.label}${w == null ? '' : ' · ${w.name}'}';
}
