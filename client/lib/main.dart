import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app/widgets.dart';
import 'core/models.dart';
import 'core/repo.dart';
import 'features/admin/admin_screens.dart';
import 'features/auth/auth_screens.dart';
import 'features/home/home_screen.dart';
import 'features/more/more_screens.dart';
import 'features/ride/ride_screen.dart';
import 'firebase_options.dart';
import 'services/push.dart';

final navKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);
  runApp(const TravelBuddyApp());
}

class TravelBuddyApp extends StatelessWidget {
  const TravelBuddyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'TravelBuddy',
        navigatorKey: navKey,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: tbGreen, brightness: Brightness.light),
        darkTheme: ThemeData(colorSchemeSeed: tbGreen, brightness: Brightness.dark),
        home: const AuthGate(),
      );
}

/// Signed out → AuthFlow. Signed in → profile state → site → main shell.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
        stream: Repo.I.authChanges(),
        initialData: Repo.I.currentUser,
        builder: (context, snap) {
          final user = snap.data;
          if (user == null) return const AuthFlow();
          return StreamBuilder<UserProfile?>(
            stream: Repo.I.userStream(user.uid),
            builder: (context, ps) {
              if (ps.hasError) {
                return Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(Repo.friendly(ps.error!), textAlign: TextAlign.center),
                  OutlinedButton(onPressed: () => Repo.I.signOut(), child: const Text('Log out')),
                ]))));
              }
              if (!ps.hasData && ps.connectionState == ConnectionState.waiting) return const Scaffold(body: Loading());
              final me = ps.data;
              if (me == null) {
                // Signed in (Google or an interrupted registration) but no profile yet.
                return AuthFlow(needsProfile: true, googleEmail: user.email, googleName: user.displayName);
              }
              return switch (me.status) {
                AccountStatus.pending => PendingScreen(me),
                AccountStatus.blocked => BlockedScreen(me),
                AccountStatus.active => _SiteGate(me),
              };
            },
          );
        },
      );
}

class _SiteGate extends StatelessWidget {
  const _SiteGate(this.me);
  final UserProfile me;
  @override
  Widget build(BuildContext context) => StreamBuilder<Site?>(
        stream: Repo.I.siteStream(me.siteId),
        builder: (context, snap) {
          if (!snap.hasData && snap.connectionState == ConnectionState.waiting) return const Scaffold(body: Loading());
          final site = snap.data;
          if (site == null) {
            return me.isAdmin
                ? const CreateSiteScreen()
                : Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text('TravelBuddy is not set up for your site yet. Please ask the admin.', textAlign: TextAlign.center),
                    OutlinedButton(onPressed: () => Repo.I.signOut(), child: const Text('Log out')),
                  ]))));
          }
          return TbScope(me: me, site: site, child: const MainShell());
        },
      );
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final scope = TbScope.of(context);
      await PushService.I.init(onOpen: ({rideId, postId}) {
        if (rideId != null) {
          navKey.currentState?.push(MaterialPageRoute(builder: (_) => TbScope(me: scope.me, site: scope.site, child: RideScreen(rideId))));
        } else if (mounted) {
          setState(() => tab = 0);
        }
      });
      await PushService.I.enable();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scope = TbScope.of(context);
    final me = scope.me;
    final pages = [
      const HomeScreen(),
      const HistoryScreen(),
      const LeaderboardScreen(),
      const NotificationsScreen(),
      SettingsScreen(
        adminTile: me.isAdmin
            ? ListTile(
                leading: const Icon(Icons.admin_panel_settings),
                title: const Text('Admin'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TbScope(me: me, site: scope.site, child: const AdminHome()))),
              )
            : null,
      ),
    ];
    return Scaffold(
      body: IndexedStack(index: tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.directions_car), label: 'Home'),
          const NavigationDestination(icon: Icon(Icons.history), label: 'Rides'),
          const NavigationDestination(icon: Icon(Icons.eco), label: 'Points'),
          NavigationDestination(
            icon: StreamBuilder<List<AppNotification>>(
              stream: Repo.I.notifications(me.uid),
              builder: (context, s) {
                final unread = (s.data ?? const []).where((n) => !n.read).length;
                return Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: const Icon(Icons.notifications));
              },
            ),
            label: 'Alerts',
          ),
          const NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
