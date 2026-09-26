import 'dart:convert';

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
    required this.role,
    this.permissions = const <String>[],
  });

  final String userId, tenantId, deviceId, name, role;
  final List<String> permissions;

  bool get isSalesman => role == 'salesman';
  bool get isSupervisor => role == 'supervisor';
  bool get isSalesManager => role == 'sales_manager';
  bool get isLeadership => isSupervisor || isSalesManager;

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'tenant_id': tenantId,
    'device_id': deviceId,
    'name': name,
    'role': role,
    'permissions': permissions,
  };

  factory AuthSession.fromJson(Map<String, dynamic> j) => AuthSession(
    userId: '${j['user_id']}',
    tenantId: '${j['tenant_id']}',
    deviceId: '${j['device_id']}',
    name: '${j['name']}',
    role: (j['role'] ?? 'salesman').toString(),
    permissions: j['permissions'] is List
        ? List<String>.from(
            (j['permissions'] as List).map((permission) => '$permission'),
          )
        : const <String>[],
  );
}

class AuthRepository {
  AuthRepository({required this.api, required this.secrets});
  final ApiClient api;
  final SecretStore secrets;
  Future<AuthSession> login(
    String email,
    String password, {
    String? tenantCode,
  }) async {
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
          if (tenantCode?.trim().isNotEmpty == true)
            'tenant': tenantCode!.trim(),
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
      role: (user['role'] ?? 'salesman').toString(),
      permissions: data['permissions'] is List
          ? List<String>.from(
              (data['permissions'] as List).map((permission) => '$permission'),
            )
          : const <String>[],
    );
    await secrets.write('session', jsonEncode(s.toJson()));
    return s;
  }

  Future<AuthSession?> restore() async {
    if (await secrets.token == null) return null;
    final raw = await secrets.read('session');
    if (raw == null) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return AuthSession.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {
      // Legacy pipe-delimited sessions are upgraded on the next login.
    }

    final p = raw.split('|');
    return p.length < 4
        ? null
        : AuthSession(
            userId: p[0],
            tenantId: p[1],
            deviceId: p[2],
            name: p.sublist(3).join('|'),
            role: 'salesman',
          );
  }

  Future<void> me() async {
    try {
      await api.get('auth/me');
    } catch (_) {}
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
