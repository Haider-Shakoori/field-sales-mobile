import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

class SecretStore {
  static const _storage = FlutterSecureStorage();
  Future<String?> get token => _storage.read(key: 'token');
  Future<void> setToken(String value) =>
      _storage.write(key: 'token', value: value);
  Future<void> clearToken() => _storage.delete(key: 'token');
  Future<String> installationUuid() => _stableUuid('installation_uuid');
  Future<String> deviceUuid() => _stableUuid('device_uuid');
  Future<String> _stableUuid(String key) async {
    var v = await _storage.read(key: key);
    if (v == null || v.isEmpty) {
      v = const Uuid().v4();
      await _storage.write(key: key, value: v);
    }
    return v;
  }

  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  Future<String?> read(String key) => _storage.read(key: key);
}
