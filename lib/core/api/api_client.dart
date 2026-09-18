import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';

import '../config.dart';
import '../storage/secret_store.dart';
import 'api_exception.dart';

class ApiEnvelope {
  const ApiEnvelope({required this.data, this.meta = const {}});

  final dynamic data;
  final Map<String, dynamic> meta;

  factory ApiEnvelope.fromBody(dynamic body) {
    if (body is! Map || body['success'] != true) {
      throw ApiException(
        status: null,
        message: 'Invalid server response.',
      );
    }

    return ApiEnvelope(
      data: body['data'],
      meta: body['meta'] is Map
          ? Map<String, dynamic>.from(body['meta'] as Map)
          : const {},
    );
  }
}

abstract interface class ApiGateway {
  Future<dynamic> get(String path, {Map<String, dynamic>? query});

  Future<ApiEnvelope> getEnvelope(
    String path, {
    Map<String, dynamic>? query,
  });

  Future<dynamic> post(
    String path, {
    Object? data,
    Map<String, String>? headers,
  });
}

class ApiClient implements ApiGateway {
  ApiClient(
    this.secrets, {
    Dio? dio,
  }) : dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: AppConfig.apiBaseUrl,
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 20),
              ),
            ) {
    this.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await secrets.token;
          final install = await secrets.installationUuid();
          final device = await secrets.deviceUuid();
          final info = await DeviceInfoPlugin().androidInfo;

          if (token != null) {
            options.headers['Authorization'] = 'Bearer ' + token;
          }

          options.headers.addAll({
            'Accept': 'application/json',
            'X-Installation-UUID': install,
            'X-Device-UUID': device,
            'X-App-Version': AppConfig.appVersion,
            'X-Platform': 'android',
            'X-OS-Version': info.version.release,
          });

          handler.next(options);
        },
      ),
    );
  }

  final SecretStore secrets;
  final Dio dio;

  void Function()? onAuthRevoked;

  static String joinBaseUrl(String baseUrl, String rawPath) {
    final base = baseUrl.replaceFirst(RegExp(r'/+$'), '');
    final clean = rawPath.replaceFirst(RegExp(r'^/+'), '');
    return base + '/' + clean;
  }

  String path(String raw) => joinBaseUrl(dio.options.baseUrl, raw);

  @override
  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final envelope = await getEnvelope(path, query: query);
    return envelope.data;
  }

  @override
  Future<ApiEnvelope> getEnvelope(
    String path, {
    Map<String, dynamic>? query,
  }) {
    final uri = Uri.parse(this.path(path)).replace(
      queryParameters: query?.map(
        (key, value) => MapEntry(key, value.toString()),
      ),
    );

    return _sendEnvelope(() => dio.getUri(uri));
  }

  @override
  Future<dynamic> post(
    String path, {
    Object? data,
    Map<String, String>? headers,
  }) async {
    final envelope = await _sendEnvelope(
      () => dio.postUri(
        Uri.parse(this.path(path)),
        data: data,
        options: Options(headers: headers),
      ),
    );

    return envelope.data;
  }

  Future<ApiEnvelope> _sendEnvelope(
    Future<Response<dynamic>> Function() call,
  ) async {
    try {
      final response = await call();
      return ApiEnvelope.fromBody(response.data);
    } on ApiException {
      rethrow;
    } on DioException catch (exception) {
      final body = exception.response?.data;
      final error = body is Map ? body['error'] : null;
      final details = error is Map ? error['details'] : null;
      final fields = <String, List<String>>{};

      if (details is Map) {
        for (final entry in details.entries) {
          final value = entry.value;
          fields[entry.key.toString()] = (value is List ? value : [value])
              .map((item) => item.toString())
              .toList();
        }
      }

      final code = error is Map ? error['code']?.toString() : null;
      final message = error is Map
          ? error['message']?.toString()
          : (exception.error is SocketException
              ? 'No internet connection.'
              : 'Request failed.');
      final status = exception.response?.statusCode;

      if (status == 401 || code == 'DEVICE_REVOKED') {
        onAuthRevoked?.call();
      }

      throw ApiException(
        status: status,
        message: message ?? 'Request failed.',
        code: code,
        fieldErrors: fields,
        retryable: status == null || status >= 500,
      );
    }
  }
}
