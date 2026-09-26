import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../../core/api/api_client.dart';

@pragma('vm:entry-point')
Future<void> fieldPulseFirebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: FieldPulseFirebaseOptions.current);
}

class FieldPulseFirebaseOptions {
  static const apiKey = String.fromEnvironment('FCM_API_KEY');
  static const appId = String.fromEnvironment('FCM_APP_ID');
  static const senderId = String.fromEnvironment('FCM_MESSAGING_SENDER_ID');
  static const projectId = String.fromEnvironment('FCM_PROJECT_ID');

  static bool get configured =>
      apiKey.isNotEmpty &&
      appId.isNotEmpty &&
      senderId.isNotEmpty &&
      projectId.isNotEmpty;

  static FirebaseOptions get current => const FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: senderId,
    projectId: projectId,
  );
}

class PushService {
  PushService(this.api);
  final ApiClient api;
  StreamSubscription<String>? _tokenSubscription;

  Future<void> initialize() async {
    if (!FieldPulseFirebaseOptions.configured) return;

    await Firebase.initializeApp(options: FieldPulseFirebaseOptions.current);
    FirebaseMessaging.onBackgroundMessage(fieldPulseFirebaseBackgroundHandler);

    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    _tokenSubscription = FirebaseMessaging.instance.onTokenRefresh.listen(
      (token) => unawaited(registerToken(token)),
    );
  }

  Future<void> registerCurrentToken() async {
    if (!FieldPulseFirebaseOptions.configured) return;
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null && token.isNotEmpty) {
      await registerToken(token);
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
  }
}
