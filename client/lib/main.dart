import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Keep the offline cache on (saves reads, works with weak signal).
  FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);
  runApp(const TravelBuddyApp());
}

const tbGreen = Color(0xFF12704A);

class TravelBuddyApp extends StatelessWidget {
  const TravelBuddyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TravelBuddy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: tbGreen, brightness: Brightness.light),
      darkTheme: ThemeData(colorSchemeSeed: tbGreen, brightness: Brightness.dark),
      home: const SkeletonCheckScreen(),
    );
  }
}

/// Step 1 only: proves the app starts on Android and web and reaches the Firebase project.
/// Replaced by the real sign-in flow in step 2.
class SkeletonCheckScreen extends StatefulWidget {
  const SkeletonCheckScreen({super.key});

  @override
  State<SkeletonCheckScreen> createState() => _SkeletonCheckScreenState();
}

class _SkeletonCheckScreenState extends State<SkeletonCheckScreen> {
  String _server = 'Checking…';

  @override
  void initState() {
    super.initState();
    _checkServer();
  }

  /// Not signed in, so the security rules must refuse this read. A "permission denied" answer
  /// proves the app reached the real Firestore server and the rules are on.
  Future<void> _checkServer() async {
    try {
      await FirebaseFirestore.instance
          .doc('settings/stops')
          .get(const GetOptions(source: Source.server));
      setState(() => _server = '⚠ Read was allowed — check the security rules');
    } on FirebaseException catch (e) {
      setState(() => _server = e.code == 'permission-denied'
          ? '✅ Connected — security rules are on'
          : '❌ ${e.code}: ${e.message}');
    } catch (e) {
      setState(() => _server = '❌ $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = Firebase.app().options;
    final platform = kIsWeb ? 'Web' : defaultTargetPlatform.name;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                Center(child: Image.asset('assets/images/logo.png', width: 96, height: 96)),
                const SizedBox(height: 12),
                Text('TravelBuddy v2',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                const Text('Step 1 — skeleton check', textAlign: TextAlign.center),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _row('Platform', platform),
                        _row('Firebase project', app.projectId),
                        _row('Signed in', FirebaseAuth.instance.currentUser == null ? 'No' : 'Yes'),
                        _row('Server', _server),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 130, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
            Expanded(child: Text(value)),
          ],
        ),
      );
}
