class AppConfig {
  static const _configuredApiBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const _configuredAppVersion = String.fromEnvironment('APP_VERSION');
  static const _debugApiBaseUrl = 'http://10.0.2.2:8000/api/v1';

  static String get apiBaseUrl =>
      _configuredApiBaseUrl.isNotEmpty ? _configuredApiBaseUrl : _debugApiBaseUrl;

  static String get appVersion =>
      _configuredAppVersion.isNotEmpty ? _configuredAppVersion : '1.0.0';

  static const privacyPolicyVersionFallback = '1';

  static void validateForStartup({
    bool productMode = bool.fromEnvironment('dart.vm.product'),
  }) {
    final uri = Uri.tryParse(apiBaseUrl);

    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw StateError('API_BASE_URL must be a valid absolute URL.');
    }

    final normalizedPath = uri.path.replaceAll(RegExp(r'/+$'), '');

    if (!normalizedPath.endsWith('/api/v1')) {
      throw StateError('API_BASE_URL must target the versioned /api/v1 endpoint.');
    }

    if (productMode) {
      if (_configuredApiBaseUrl.isEmpty) {
        throw StateError('Release builds require API_BASE_URL.');
      }

      if (uri.scheme.toLowerCase() != 'https') {
        throw StateError('Release builds require an HTTPS API_BASE_URL.');
      }

      if (_configuredAppVersion.isEmpty) {
        throw StateError('Release builds require APP_VERSION.');
      }
    }
  }
}
