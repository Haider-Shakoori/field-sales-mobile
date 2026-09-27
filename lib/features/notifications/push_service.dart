import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../../core/api/api_client.dart';

@pragma('vm:entry-point')
Future<void> fieldPulseFirebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class PushService {
  PushService(this.api);
  final _opened = StreamController<Map<String, dynamic>>.broadcast();
  final _received = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get opened => _opened.stream;
  Stream<Map<String, dynamic>> get received => _received.stream;
  final ApiClient api;
  StreamSubscription<String>? _tokenSubscription;
  bool _initialized = false;

  Future<void> initialize() async {
    try {
      await Firebase.initializeApp();
      _initialized = true;
    } catch (_) {
      return;
    }
    FirebaseMessaging.onBackgroundMessage(fieldPulseFirebaseBackgroundHandler);

    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    _tokenSubscription = FirebaseMessaging.instance.onTokenRefresh.listen(
      (token) => unawaited(registerToken(token)),
    );

    FirebaseMessaging.onMessage.listen((message) {
      _received.add(Map<String, dynamic>.from(message.data));
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _opened.add(Map<String, dynamic>.from(message.data));
    });

    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      scheduleMicrotask(
        () => _opened.add(Map<String, dynamic>.from(initialMessage.data)),
      );
    }
  }

  Future<void> registerCurrentToken() async {
    if (!_initialized) return;

    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await registerToken(token);
      }
    } catch (_) {
      // Firebase/token availability must never block normal field work.
    }
  }

  Future<void> registerToken(String token) async {
    try {
      await api.put('device/push-token', data: {'push_token': token});
    } catch (_) {
      // Login/connection may not be ready. The next app start/token refresh retries.
    }
  }

  Future<void> dispose() async {
    await _tokenSubscription?.cancel();
    await _opened.close();
    await _received.close();
  }
}
