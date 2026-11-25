// TravelBuddy web (HomiLabs) for the FFL community carpool. It uses the Firestore project of the
// TravelBuddy Android app (gen-lang-client-0717949368), so members see the same rides on phone and web.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app/widgets.dart';
import 'core/models.dart';
import 'core/repo.dart';
import 'features/activity.dart';
import 'features/admin.dart';
import 'features/auth.dart';
import 'features/home.dart';
import 'features/profile.dart';
import 'firebase_options.dart';

/// `flutter run --dart-define=EMULATOR=1` points the app at the local Firebase emulators for testing.
const bool useEmulator = String.fromEnvironment('EMULATOR') == '1' || bool.fromEnvironment('EMULATOR');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: fflWebOptions);
  if (useEmulator) {
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9199);
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8185);
  }
  runApp(const TravelBuddyApp());
}

class TravelBuddyApp extends StatelessWidget {
  const TravelBuddyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'TravelBuddy',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const AuthGate(),
      );
}

/// Signed out → login. Signed in → profile state → main shell. Blocked/removed members are shown a notice.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
        stream: Repo.I.authChanges(),
        initialData: Repo.I.currentUser,
        builder: (context, snap) {
          final user = snap.data;
          if (user == null) return const AuthFlow();
          return StreamBuilder<AppUser?>(
            stream: Repo.I.userStream(user.uid),
            builder: (context, ps) {
              if (ps.hasError) {
                return Scaffold(body: Center(child: Pad(all: 24, child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(Repo.friendly(ps.error!), textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: () => Repo.I.signOut(), child: const Text('Log out')),
                ]))));
              }
              if (!ps.hasData && ps.connectionState == ConnectionState.waiting) return const Scaffold(body: Loading());
              final me = ps.data;
              if (me == null) {
                return StreamBuilder<bool>(
                  stream: Repo.I.registering.stream,
                  initialData: Repo.I.registering.value,
                  builder: (context, r) => (r.data ?? false)
                      ? const Scaffold(body: Loading())
                      : CompleteProfileScreen(email: user.email ?? '', displayName: user.displayName ?? ''),
                );
              }
              if (me.isBlocked || me.isRemoved) return RestrictedScreen(me);
              if (me.isPending) return PendingScreen(me);
              return MainShell(me: me);
            },
          );
        },
      );
}

class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.me});
  final AppUser me;
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  var tab = 0;
  @override
  Widget build(BuildContext context) {
    final me = widget.me;
    final pages = <Widget>[HomeScreen(me: me), ActivityScreen(me: me), if (me.isAdmin) AdminScreen(me: me), ProfileScreen(me: me)];
    final dests = <NavigationDestination>[
      const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
      const NavigationDestination(icon: Icon(Icons.history), label: 'Activity'),
      if (me.isAdmin)
        NavigationDestination(
          icon: StreamBuilder<List<AppUser>>(
            stream: Repo.I.pendingUsers(),
            builder: (context, s) {
              final n = (s.data ?? const []).length;
              return Badge(isLabelVisible: n > 0, label: Text('$n'), child: const Icon(Icons.admin_panel_settings_outlined));
            },
          ),
          label: 'Admin',
        ),
      const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
    ];
    if (tab >= pages.length) tab = 0;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      appBar: AppBar(
        title: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.directions_car_filled, color: primary), SizedBox(width: 8), Text('TravelBuddy', style: TextStyle(fontWeight: FontWeight.bold, color: primaryDark))]),
        centerTitle: true,
        actions: [if (kDebugMode && useEmulator) const Padding(padding: EdgeInsets.all(12), child: Text('EMULATOR', style: TextStyle(color: errorColor, fontWeight: FontWeight.bold)))],
      ),
      body: wide
          ? Row(children: [
              NavigationRail(
                selectedIndex: tab,
                onDestinationSelected: (i) => setState(() => tab = i),
                labelType: NavigationRailLabelType.all,
                destinations: [for (final d in dests) NavigationRailDestination(icon: d.icon, selectedIcon: d.selectedIcon, label: Text(d.label))],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: pages[tab]),
            ])
          : pages[tab],
      bottomNavigationBar: wide ? null : NavigationBar(selectedIndex: tab, onDestinationSelected: (i) => setState(() => tab = i), destinations: dests),
    );
  }
}
