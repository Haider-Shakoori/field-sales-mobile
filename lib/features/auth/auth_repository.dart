import 'package:device_info_plus/device_info_plus.dart';

import '../../core/api/api_client.dart';
import '../../core/config.dart';
import '../../core/storage/secret_store.dart';

class AuthSession {
  const AuthSession({
    required this.userId,
    required this.tenantId,
    required this.deviceId,
    required this.name,
  });
  final String userId, tenantId, deviceId, name;
  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'tenant_id': tenantId,
    'device_id': deviceId,
    'name': name,
  };
  factory AuthSession.fromJson(Map<String, dynamic> j) => AuthSession(
    userId: '${j['user_id']}',
    tenantId: '${j['tenant_id']}',
    deviceId: '${j['device_id']}',
    name: '${j['name']}',
  );
}

class AuthRepository {
  AuthRepository({required this.api, required this.secrets});
  final ApiClient api;
  final SecretStore secrets;
  Future<AuthSession> login(String email, String password) async {
    await secrets.installationUuid();
    final deviceUuid = await secrets.deviceUuid();
    var deviceModel = 'unknown';
    var manufacturer = 'unknown';
    var androidVersion = 'unknown';

    try {
      final info = await DeviceInfoPlugin().androidInfo;
      deviceModel = info.model;
      manufacturer = info.manufacturer;
      androidVersion = info.version.release;
    } catch (_) {
      // Device metadata is best-effort and must never block authentication.
    }

    final data = Map<String, dynamic>.from(
      await api.post(
        'auth/login',
        data: {
          'email': email,
          'password': password,
          'device_uuid': deviceUuid,
          'device_model': deviceModel,
          'manufacturer': manufacturer,
          'android_version': androidVersion,
          'app_version': AppConfig.appVersion,
          'push_token': null,
        },
      ),
    );
    await secrets.setToken('${data['token']}');
    final user = Map<String, dynamic>.from(data['user']);
    final tenant = Map<String, dynamic>.from(data['tenant']);
    final registeredDevice = Map<String, dynamic>.from(data['device']);
    final s = AuthSession(
      userId: '${user['id']}',
      tenantId: '${tenant['id']}',
      deviceId: '${registeredDevice['id']}',
      name: '${user['name']}',
    );
    await secrets.write(
      'session',
      '${s.userId}|${s.tenantId}|${s.deviceId}|${s.name}',
    );
    return s;
  }

  Future<AuthSession?> restore() async {
    if (await secrets.token == null) return null;
    final raw = await secrets.read('session');
    if (raw == null) return null;
    final p = raw.split('|');
    return p.length < 4
        ? null
        : AuthSession(
            userId: p[0],
            tenantId: p[1],
            deviceId: p[2],
            name: p.sublist(3).join('|'),
          );
  }

  Future<void> logout() async {
    try {
      await api.post('auth/logout');
    } catch (_) {}
    await clearLocalAuth();
  }

  Future<void> clearLocalAuth() async {
    await secrets.clearToken();
  }
}
