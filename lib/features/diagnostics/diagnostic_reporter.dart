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
      final sanitizedMessage = message.trim().replaceAll(
        RegExp(r'Bearer\s+[A-Za-z0-9._~+\-/=]+', caseSensitive: false),
        'Bearer [redacted]',
      );

      await api.post(
        'mobile/diagnostics',
        data: {
          'severity': severity,
          'area': area,
          if (code != null && code.trim().isNotEmpty) 'code': code.trim(),
          'message': sanitizedMessage.length > 2000
              ? sanitizedMessage.substring(0, 2000)
              : sanitizedMessage,
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
      // Diagnostic delivery is always best-effort. It must never cause a
      // second user-visible failure or block the operation being reported.
    }
  }
}
