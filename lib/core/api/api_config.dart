/// Build-time API configuration.
///
/// Override at build/run time with:
///   flutter run --dart-define=API_BASE_URL=https://api.example.com
///
/// Defaults target the Android emulator loopback to the host machine
/// (10.0.2.2), where the Laravel Herd server listens during development.
class ApiConfig {
  ApiConfig._();

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000/api/v1',
  );

  static const String appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '1.0.0',
  );

  static const String platform = 'android';
}
