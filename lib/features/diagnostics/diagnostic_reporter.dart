import '../../core/api/api_client.dart';
import '../../core/config.dart';

class DiagnosticReporter {
  DiagnosticReporter(this.api);

  final ApiClient api;

  Future<void> report({
    required String area,
    required String message,
    String severity = 'error',
    String? code,
    String? screen,
    String? operation,
    String? entity,
    String? syncStatus,
    String? network,
  }) async {
    try {
      await api.post(
        'mobile/diagnostics',
        data: {
          'severity': severity,
          'area': area,
          if (code != null) 'code': code,
          'message': message.length > 2000
              ? message.substring(0, 2000)
              : message,
          'occurred_at': DateTime.now().toUtc().toIso8601String(),
          'context': {
            'app_version': AppConfig.appVersion,
            'platform': 'android',
            if (screen != null) 'screen': screen,
            if (operation != null) 'operation': operation,
            if (entity != null) 'entity': entity,
            if (syncStatus != null) 'sync_status': syncStatus,
            if (network != null) 'network': network,
          },
        },
      );
    } catch (_) {
      // Diagnostics are best-effort and must never create another user error.
    }
  }
}
