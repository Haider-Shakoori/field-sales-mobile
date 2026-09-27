import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../../core/api/api_client.dart';

@pragma('vm:entry-point')
Future<void> fieldPulseFirebaseBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp();
  }
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
  final _opened = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get opened => _opened.stream;
  final ApiClient api;
  StreamSubscription<String>? _tokenSubscription;

  Future<void> initialize() async {
    if (Firebase.apps.isEmpty) {
      if (Platform.isAndroid) {
        await Firebase.initializeApp();
      } else if (FieldPulseFirebaseOptions.configured) {
        await Firebase.initializeApp(options: FieldPulseFirebaseOptions.current);
      } else {
        return;
      }
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
    if (Firebase.apps.isEmpty) return;

    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await registerToken(token);
      }
    } catch (_) {
      // Firebase/Play Services can be temporarily unavailable. Token refresh
      // or the next app start will retry without blocking FieldPulse.
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
  }
}
