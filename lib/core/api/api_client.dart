import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import 'api_config.dart';
import 'api_exception.dart';
import '../storage/secret_store.dart';

/// The shared `{success, data, meta, error}` envelope returned by the API.
///
/// [data] holds the resource (or list), [meta] the pagination object
/// (`page`, `per_page`, `total`, `last_page`) when present.
class ApiEnvelope {
  const ApiEnvelope({this.data, this.meta = const {}});

  final dynamic data;
  final Map<String, dynamic> meta;

  int get lastPage => (meta['last_page'] as num?)?.toInt() ?? 1;
}

/// Typed wrapper over the Dio HTTP client used for all `api/v1` calls.
///
/// Every request carries the mandated device headers (`X-Device-UUID`,
/// `X-Installation-UUID`, `X-App-Version`, `X-Platform`, `X-OS-Version`) and,
/// when a token is stored, `Authorization: Bearer <token>`. Responses are
/// decoded into the shared envelope.
class ApiClient {
  ApiClient({required SecretStore secureStorage, Dio? dio})
    : _secretStore = secureStorage {
    _dio =
        dio ??
        Dio(
          BaseOptions(
            baseUrl: ApiConfig.baseUrl,
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 30),
            sendTimeout: const Duration(seconds: 15),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'X-Platform': ApiConfig.platform,
              'X-App-Version': ApiConfig.appVersion,
              'X-OS-Version': '',
              'X-Device-UUID': '',
              'X-Installation-UUID': '',
            },
          ),
        );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          await _applyDeviceHeaders(options);
          await _applyAuthToken(options);
          handler.next(options);
        },
      ),
    );
  }

  final SecretStore _secretStore;
  late final Dio _dio;

  String get appVersion => ApiConfig.appVersion;
  String get platform => ApiConfig.platform;

  Future<void> _applyAuthToken(RequestOptions options) async {
    final token = await _secretStore.readToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
  }

  Future<void> _applyDeviceHeaders(RequestOptions options) async {
    var uuid = await _secretStore.readInstallationUuid();
    if (uuid.isEmpty) {
      uuid = const Uuid().v4();
      await _secretStore.writeInstallationUuid(uuid);
    }
    options.headers['X-Installation-UUID'] = uuid;
    options.headers['X-Device-UUID'] = uuid;
  }

  /// Performs a JSON request and returns the full envelope (data + meta).
  Future<ApiEnvelope> requestEnvelope({
    required String method,
    required String path,
    Map<String, dynamic>? query,
    Object? body,
    String? idempotencyKey,
  }) async {
    try {
      final options = Options(
        method: method,
        headers: idempotencyKey == null
            ? null
            : {'X-Idempotency-Key': idempotencyKey},
      );
      final response = await _dio.request<Object?>(
        path,
        queryParameters: query,
        data: body,
        options: options,
      );

      final payload = response.data;
      if (payload is Map<String, dynamic>) {
        final ok = payload['success'] ?? false;
        if (ok == true) {
          final meta = payload['meta'];
          return ApiEnvelope(
            data: payload['data'],
            meta: meta is Map<String, dynamic> ? meta : const {},
          );
        }
        throw _envelopeException(payload, response.statusCode ?? 500);
      }
      return ApiEnvelope(data: payload);
    } on DioException catch (e) {
      throw _dioException(e);
    }
  }

  /// Returns `data` when the request succeeded, otherwise throws an
  /// [ApiException] built from the envelope's `error` section or the
  /// raw HTTP status.
  Future<dynamic> request({
    required String method,
    required String path,
    Map<String, dynamic>? query,
    Object? body,
    String? idempotencyKey,
  }) async {
    final envelope = await requestEnvelope(
      method: method,
      path: path,
      query: query,
      body: body,
      idempotencyKey: idempotencyKey,
    );
    return envelope.data;
  }

  ApiException _envelopeException(Map<String, dynamic> payload, int status) {
    final error = payload['error'];
    if (error is Map<String, dynamic>) {
      final code = error['code'];
      final messageSource = error['message'] ?? error['exception'];
      final message = messageSource is String
          ? messageSource
          : error['message']?.toString() ?? 'Request failed';

      final fields = <String, List<String>>{};
      dynamic errData = error['data'] ?? error['errors'];
      if (errData is Map<String, dynamic>) {
        errData.forEach((key, value) {
          if (value is List) {
            fields[key] = value.map((e) => e.toString()).toList();
          } else if (value != null) {
            fields[key] = [value.toString()];
          }
        });
      }

      return ApiException(
        status: status,
        message: message,
        code: code?.toString(),
        fieldErrors: fields,
        retryable: status == 429 || status >= 500,
      );
    }
    return ApiException(
      status: status,
      message: 'Request failed with status $status',
      retryable: status == 429 || status >= 500,
    );
  }

  ApiException _dioException(DioException e) {
    final status = e.response?.statusCode ?? 0;

    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return ApiException(
        status: 0,
        message: 'Network unreachable. Check your connection.',
        code: 'NETWORK',
        retryable: true,
      );
    }

    if (e.response != null) {
      final data = e.response!.data;
      if (data is Map<String, dynamic>) {
        return _envelopeException(data, status);
      }
      if (status == 401) {
        return ApiException(
          status: 401,
          message: 'Session expired. Please sign in again.',
          code: 'TOKEN_REVOKED',
        );
      }
    }
    return ApiException(
      status: status,
      message: e.message ?? 'Something went wrong',
      retryable: e.type == DioExceptionType.cancel,
    );
  }
}
