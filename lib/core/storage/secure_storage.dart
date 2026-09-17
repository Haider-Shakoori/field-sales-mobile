import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'secret_store.dart';

/// Key-value repository for secrets kept in Android Keystore-backed encrypted
/// storage (flutter_secure_storage). Used for the Sanctum bearer token and
/// persisted session identifiers so they survive app restarts.
class SecureStorage implements SecretStore {
  SecureStorage([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'sanctum_token';
  static const _installationKey = 'installation_uuid';
  static const _cachedEmailKey = 'cached_email';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> readToken() => _storage.read(key: _tokenKey);

  @override
  Future<void> writeToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  @override
  Future<void> clearToken() async {
    await _storage.delete(key: _tokenKey);
  }

  @override
  Future<String> readInstallationUuid() async =>
      await _storage.read(key: _installationKey) ?? '';

  @override
  Future<void> writeInstallationUuid(String uuid) =>
      _storage.write(key: _installationKey, value: uuid);

  @override
  Future<String?> readCachedEmail() => _storage.read(key: _cachedEmailKey);

  @override
  Future<void> writeCachedEmail(String email) =>
      _storage.write(key: _cachedEmailKey, value: email);
}
