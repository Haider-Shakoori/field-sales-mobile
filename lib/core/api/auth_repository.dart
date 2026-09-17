import 'package:device_info_plus/device_info_plus.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../models/session.dart';
import '../storage/secret_store.dart';

/// Backend authentication gateway: login, refresh and logout against the
/// Sanctum `api/v1/auth/*` endpoints.
class AuthRepository {
  AuthRepository({
    required ApiClient apiClient,
    required SecretStore secureStorage,
    Future<String> Function()? deviceModelProvider,
  }) : _apiClient = apiClient,
       _secretStore = secureStorage,
       _deviceModelProvider = deviceModelProvider;

  final ApiClient _apiClient;
  final SecretStore _secretStore;
  final Future<String> Function()? _deviceModelProvider;

  /// Exchanges email/password (plus device metadata) for a Sanctum session.
  ///
  /// The issued token is persisted in encrypted storage, allowing later app
  /// starts to restore the session without prompting.
  Future<Session> login({
    required String email,
    required String password,
    required String pushToken,
  }) async {
    final body = <String, dynamic>{
      'email': email,
      'password': password,
      'device_uuid': (await _secretStore.readInstallationUuid()),
      'device_model': await _resolveDeviceModel(),
      'manufacturer': 'unknown',
      'android_version': '14',
      'app_version': _apiClient.appVersion,
      'push_token': pushToken,
    };

    final data = await _apiClient.request(
      method: 'POST',
      path: '/auth/login',
      body: body,
    );

    final session = Session.fromJson(data as Map<String, dynamic>);
    await _secretStore.writeToken(session.token);
    await _secretStore.writeCachedEmail(email);
    return session;
  }

  Future<String> _resolveDeviceModel() {
    final provider = _deviceModelProvider;
    if (provider != null) {
      return provider();
    }
    return _deviceModel();
  }

  /// Rotates the current bearer token. The old token is invalidated server
  /// side and the fresh one replaces it in storage on success.
  Future<String> refresh() async {
    final data = await _apiClient.request(
      method: 'POST',
      path: '/auth/refresh',
    );
    final token = (data as Map<String, dynamic>)['token']?.toString() ?? '';
    if (token.isNotEmpty) {
      await _secretStore.writeToken(token);
    }
    return token;
  }

  /// Revokes the current token server side and clears local secrets.
  Future<void> logout() async {
    try {
      await _apiClient.request(method: 'POST', path: '/auth/logout');
    } on ApiException catch (_) {
      // Token is cleared regardless; the server may already have revoked it.
    }
    await _secretStore.clearToken();
  }

  Future<String> _deviceModel() async {
    final info = DeviceInfoPlugin();
    final androidInfo = await info.androidInfo;
    return androidInfo.model;
  }
}
