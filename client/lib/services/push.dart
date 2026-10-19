// Push (FCM) + local notifications. Android: channel "tb_alerts". Web: push needs a service
// worker and a VAPID key — wired in the web phase; until then web users see the in-app list.
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/repo.dart';

typedef OpenHandler = void Function({String? rideId, String? postId});

@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {
  // Android shows data+notification messages itself when the app is in the background.
}

class PushService {
  PushService._();
  static final PushService I = PushService._();

  final _local = FlutterLocalNotificationsPlugin();
  OpenHandler? _onOpen;
  bool _ready = false;

  static const channelId = 'tb_alerts';

  Future<void> init({required OpenHandler onOpen}) async {
    _onOpen = onOpen;
    if (_ready) return;
    _ready = true;
    if (!kIsWeb) {
      await _local.initialize(
        settings: const InitializationSettings(android: AndroidInitializationSettings('ic_stat_car')),
        onDidReceiveNotificationResponse: (r) => _route(r.payload),
      );
      await _local
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel(
            channelId, 'Ride alerts',
            description: 'Ride locked, driver approaching, reminders, cancellations',
            importance: Importance.high,
          ));
      FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);
    }
    final fm = FirebaseMessaging.instance;
    FirebaseMessaging.onMessage.listen((m) {
      final n = m.notification;
      if (n != null) show(n.title ?? 'TravelBuddy', n.body ?? '', payload: _payload(m.data));
    });
    FirebaseMessaging.onMessageOpenedApp.listen((m) => _route(_payload(m.data)));
    final initial = await fm.getInitialMessage();
    if (initial != null) _route(_payload(initial.data));
    // onRegistered gives the Firebase Installation ID; the server sends to FCM *tokens*,
    // so keep using the token APIs (deprecated in name only — still the server-send path).
    // ignore: deprecated_member_use
    fm.onTokenRefresh.listen((t) => Repo.I.saveFcmToken(t));
  }

  /// Current OS permission as a short label for Settings.
  Future<String> permissionStatus() async {
    try {
      final s = await FirebaseMessaging.instance.getNotificationSettings();
      return switch (s.authorizationStatus) {
        AuthorizationStatus.authorized => 'Allowed',
        AuthorizationStatus.provisional => 'Allowed (quiet)',
        AuthorizationStatus.denied => 'Blocked by the phone',
        AuthorizationStatus.notDetermined => 'Not asked yet',
        _ => 'Blocked by the phone',
      };
    } catch (_) {
      return 'Unknown';
    }
  }

  /// Ask for permission and register this device for push. Safe to call repeatedly.
  Future<void> enable() async {
    final fm = FirebaseMessaging.instance;
    final s = await fm.requestPermission();
    if (s.authorizationStatus == AuthorizationStatus.denied) return;
    // Web push is wired in the web phase (needs a VAPID key); Android gets its FCM token here.
    if (!kIsWeb) {
      // ignore: deprecated_member_use
      final t = await fm.getToken();
      if (t != null) await Repo.I.saveFcmToken(t);
    }
  }

  String _payload(Map<String, dynamic> data) => '${data['rideId'] ?? ''}|${data['postId'] ?? ''}';

  void _route(String? payload) {
    if (payload == null || _onOpen == null) return;
    final parts = payload.split('|');
    _onOpen!(rideId: parts.isNotEmpty && parts[0].isNotEmpty ? parts[0] : null,
        postId: parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null);
  }

  /// A local notification (approach alert etc.). No-op on web.
  Future<void> show(String title, String body, {String? payload, int id = 1}) async {
    if (kIsWeb) return;
    await _local.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(channelId, 'Ride alerts', importance: Importance.high, priority: Priority.high),
      ),
      payload: payload,
    );
  }

  Future<void> cancel(int id) async {
    if (!kIsWeb) await _local.cancel(id: id);
  }
}
