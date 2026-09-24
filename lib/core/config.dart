class AppConfig {
  static const _configuredApiBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const _configuredAppVersion = String.fromEnvironment('APP_VERSION');
  static const _configuredTileUrlTemplate = String.fromEnvironment(
    'TILE_URL_TEMPLATE',
  );
  static const _debugApiBaseUrl = 'http://10.0.2.2:8001/api/v1';
  static const _defaultTileUrlTemplate =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  static String get apiBaseUrl => _configuredApiBaseUrl.isNotEmpty
      ? _configuredApiBaseUrl
      : _debugApiBaseUrl;

  static String get appVersion =>
      _configuredAppVersion.isNotEmpty ? _configuredAppVersion : '1.0.0';

  static String get tileUrlTemplate => _configuredTileUrlTemplate.isNotEmpty
      ? _configuredTileUrlTemplate
      : _defaultTileUrlTemplate;

  static bool get tileSourceConfigured => _configuredTileUrlTemplate.isNotEmpty;

  static const privacyPolicyVersionFallback = '1';

  static void validateForStartup({
    bool productMode = const bool.fromEnvironment('dart.vm.product'),
  }) {
    final uri = Uri.tryParse(apiBaseUrl);

    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw StateError('API_BASE_URL must be a valid absolute URL.');
    }

    final normalizedPath = uri.path.replaceAll(RegExp(r'/+$'), '');

    if (!normalizedPath.endsWith('/api/v1')) {
      throw StateError(
        'API_BASE_URL must target the versioned /api/v1 endpoint.',
      );
    }

    final tileTemplate = tileUrlTemplate;
    if (!tileTemplate.contains('{z}') ||
        !tileTemplate.contains('{x}') ||
        !tileTemplate.contains('{y}')) {
      throw StateError(
        'TILE_URL_TEMPLATE must contain {z}, {x}, and {y} placeholders.',
      );
    }

    final tileUri = Uri.tryParse(
      tileTemplate
          .replaceAll('{z}', '0')
          .replaceAll('{x}', '0')
          .replaceAll('{y}', '0'),
    );

    if (tileUri == null || !tileUri.hasScheme || tileUri.host.isEmpty) {
      throw StateError('TILE_URL_TEMPLATE must be a valid absolute URL.');
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

      if (tileUri.scheme.toLowerCase() != 'https') {
        throw StateError('Release builds require an HTTPS TILE_URL_TEMPLATE.');
      }
    }
  }
}
