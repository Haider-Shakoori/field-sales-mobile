/// Portable secret store abstraction used by the API/auth layer.
///
/// The production implementation is [SecureStorage] (Android Keystore-backed
/// encrypted storage). Tests inject an in-memory fake so auth flows can be
/// verified without platform plugins.
abstract class SecretStore {
  Future<String?> readToken();

  Future<void> writeToken(String token);

  Future<void> clearToken();

  Future<String> readInstallationUuid();

  Future<void> writeInstallationUuid(String uuid);

  Future<String?> readCachedEmail();

  Future<void> writeCachedEmail(String email);
}
