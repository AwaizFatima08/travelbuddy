// Theme (the Android app's palette, Color.kt) and small shared widgets.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const primaryDark = Color(0xFF0C543D);
const primary = Color(0xFF126847);
const primaryLight = Color(0xFFDDEFE6);
const primaryVeryLight = Color(0xFFF0F8F4);
const bgColor = Color(0xFFF7F9F7);
const textPrimary = Color(0xFF13231D);
const textSecondary = Color(0xFF64716C);
const textTertiary = Color(0xFF8A9691);
const successColor = Color(0xFF198754);
const warningColor = Color(0xFFCB8B22);
const errorColor = Color(0xFFB54848);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: primary, primary: primary, surface: Colors.white);
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: bgColor,
    useMaterial3: true,
    cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero, color: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16)), side: BorderSide(color: Color(0xFFDCE5E0)))),
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), isDense: true),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(64, 46), textStyle: const TextStyle(fontWeight: FontWeight.bold))),
    appBarTheme: const AppBarTheme(backgroundColor: bgColor, foregroundColor: textPrimary, elevation: 0, scrolledUnderElevation: 0),
  );
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

Future<void> dial(String phone) async {
  if (phone.trim().isEmpty) return;
  try {
    await launchUrl(Uri(scheme: 'tel', path: phone.trim()));
  } catch (_) {}
}

/// Phone-width column on a laptop screen.
class MaxWidth extends StatelessWidget {
  const MaxWidth({super.key, required this.child, this.width = 620});
  final Widget child;
  final double width;
  @override
  Widget build(BuildContext context) => Center(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: width), child: child));
}

class Loading extends StatelessWidget {
  const Loading({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
}

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: primaryDark, letterSpacing: 0.6));
}

class Muted extends StatelessWidget {
  const Muted(this.text, {super.key, this.center = false, this.size = 13.5});
  final String text;
  final bool center;
  final double size;
  @override
  Widget build(BuildContext context) => Text(text, textAlign: center ? TextAlign.center : null, style: TextStyle(color: textSecondary, fontSize: size));
}

class ErrorNote extends StatelessWidget {
  const ErrorNote(this.text, {super.key});
  final String? text;
  @override
  Widget build(BuildContext context) => (text == null || text!.isEmpty)
      ? const SizedBox.shrink()
      : Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(text!, style: const TextStyle(color: errorColor)));
}

class Pad extends StatelessWidget {
  const Pad({super.key, required this.child, this.all = 16});
  final Widget child;
  final double all;
  @override
  Widget build(BuildContext context) => Padding(padding: EdgeInsets.all(all), child: child);
}

class TbCard extends StatelessWidget {
  const TbCard({super.key, required this.child, this.tint});
  final Widget child;
  final Color? tint;
  @override
  Widget build(BuildContext context) => Card(color: tint, child: Padding(padding: const EdgeInsets.all(16), child: child));
}

/// Dropdown over a fixed list of strings.
class Pick extends StatelessWidget {
  const Pick({super.key, required this.label, required this.value, required this.items, required this.onChanged});
  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
        initialValue: items.contains(value) ? value : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [for (final i in items) DropdownMenuItem(value: i, child: Text(i, overflow: TextOverflow.ellipsis))],
        onChanged: (v) => v == null ? null : onChanged(v),
      );
}

/// Pickup area chooser: Township areas, Plant areas, Other (PickupAreaSelector.kt).
class PickupPicker extends StatelessWidget {
  const PickupPicker({super.key, required this.value, required this.onChanged, this.label = 'Pickup area'});
  final String value;
  final String label;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) {
    const other = 'Other / Different Location';
    final items = <DropdownMenuItem<String>>[
      const DropdownMenuItem(enabled: false, value: '_t', child: Text('TOWNSHIP', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: primaryDark))),
      for (final t in const ['D-Type — Blocks A–K/L', 'C-Type', 'MOQs', 'EMs', 'BOQs', 'Guest Houses', 'Single Staff']) DropdownMenuItem(value: t, child: Text(t)),
      const DropdownMenuItem(enabled: false, value: '_p', child: Text('PLANT', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: primaryDark))),
      for (final p in const ['FFL Plant Main Gate', 'HSE Building', 'Warehouse', 'L&DC Building', 'Main Workshop', 'Laboratory', 'CCR-1', 'MCR', 'Maintenance South Workshop', 'Maintenance North Workshop']) DropdownMenuItem(value: p, child: Text(p)),
      const DropdownMenuItem(value: other, child: Text(other)),
    ];
    final valid = items.any((i) => i.value == value && i.enabled);
    return DropdownButtonFormField<String>(
      initialValue: valid ? value : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: items,
      onChanged: (v) => v == null ? null : onChanged(v),
    );
  }
}

String fmtDateTime(int ms) {
  if (ms <= 0) return '—';
  final k = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).add(const Duration(hours: 5)); // Pakistan time
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final h = k.hour % 12 == 0 ? 12 : k.hour % 12;
  final ap = k.hour < 12 ? 'AM' : 'PM';
  return '${k.day} ${months[k.month - 1]} ${k.year}, $h:${k.minute.toString().padLeft(2, '0')} $ap';
}

String fmtDate(String iso) {
  final p = iso.split('-');
  if (p.length != 3) return iso;
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final m = int.tryParse(p[1]) ?? 1;
  return '${int.tryParse(p[2]) ?? p[2]} ${months[(m - 1).clamp(0, 11)]} ${p[0]}';
}

String kg(double v) => '${v.toStringAsFixed(v >= 10 ? 1 : 2)} kg';

Future<bool> confirm(BuildContext context, String title, String body, {String yes = 'Confirm', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: errorColor) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(yes),
        ),
      ],
    ),
  );
  return r == true;
}

Future<String?> askText(BuildContext context, String title, {String hint = '', bool required = false}) async {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(controller: c, maxLength: 140, decoration: InputDecoration(hintText: hint), autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () {
          if (required && c.text.trim().isEmpty) return;
          Navigator.pop(ctx, c.text.trim());
        }, child: const Text('OK')),
      ],
    ),
  );
}
