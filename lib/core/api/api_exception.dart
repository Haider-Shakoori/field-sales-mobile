class ApiException implements Exception {
  ApiException({required this.status, required this.message, this.code, this.fieldErrors = const {}, this.retryable = false});
  final int? status; final String message; final String? code; final Map<String, List<String>> fieldErrors; final bool retryable;
  @override String toString() => message;
}
