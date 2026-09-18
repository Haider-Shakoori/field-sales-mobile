import 'dart:convert';

/// Server envelope error, mirroring the Laravel JSON envelope:
/// `{ "success": false, "data": ..., "meta": ..., "error": {...} }`.
///
/// [code] holds the machine-readable error code (e.g. `DEVICE_REVOKED`,
/// `INVALID_CREDENTIALS`) and [fieldErrors] the validation errors keyed by
/// field name. [status] is the HTTP status code.
class ApiException implements Exception {
  ApiException({
    required this.status,
    required this.message,
    this.code,
    this.fieldErrors = const {},
    this.retryable = false,
  });

  final int status;
  final String message;
  final String? code;
  final Map<String, List<String>> fieldErrors;

  /// Whether the failure is transient (network, 429, 5xx) and safe to retry.
  final bool retryable;

  bool get isUnauthenticated => status == 401 || code == 'TOKEN_REVOKED';

  /// Device revocation.
  ///
  /// Laravel returns `403` with a human message ("This device has been
  /// revoked…") and no machine code from its device middleware, so the message
  /// is used as a compatibility fallback alongside the canonical code/status.
  bool get isDeviceRevoked =>
      code == 'DEVICE_REVOKED' ||
      status == 440 ||
      (status == 403 && message.toLowerCase().contains('revoked'));

  /// The minimum app version middleware (`EnforceMinimumAppVersion`) returns
  /// 426 with upgrade details when `X-App-Version` is below the threshold.
  bool get isUpgradeRequired => status == 426 || code == 'APP_VERSION_REQUIRED';
  bool get isConflict => status == 409 || code == 'SYNC_CONFLICT';
  bool get isValidation => status == 422;

  @override
  String toString() {
    final codePart = code == null ? '' : ' [$code]';
    final fields = fieldErrors.isEmpty ? '' : ' ${jsonEncode(fieldErrors)}';
    return 'ApiException($status$codePart): $message$fields';
  }
}
