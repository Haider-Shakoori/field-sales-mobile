import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';

import '../config.dart';
import '../storage/secret_store.dart';
import 'api_exception.dart';

class ApiClient {
  ApiClient(this.secrets)
    : dio = Dio(
        BaseOptions(
          baseUrl: AppConfig.apiBaseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
        ),
      ) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await secrets.token;
          final install = await secrets.installationUuid();
          final device = await secrets.deviceUuid();
          final info = await DeviceInfoPlugin().androidInfo;

          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
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

  String path(String raw) {
    final base = dio.options.baseUrl.replaceFirst(RegExp(r'/+$'), '');
    final clean = raw.replaceFirst(RegExp(r'^/+'), '');

    return '$base/$clean';
  }

  Future<dynamic> get(String p, {Map<String, dynamic>? query}) =>
      _send(() => dio.getUri(_uri(p, query)));

  Future<ApiEnvelope> getEnvelope(String p, {Map<String, dynamic>? query}) =>
      _sendEnvelope(() => dio.getUri(_uri(p, query)));

  Future<dynamic> post(
    String p, {
    Object? data,
    Map<String, String>? headers,
  }) => _send(
    () => dio.postUri(
      Uri.parse(path(p)),
      data: data,
      options: Options(headers: headers),
    ),
  );

  Future<dynamic> postMultipart(
    String p, {
    required String filePath,
    String field = 'photo',
    Map<String, dynamic> fields = const {},
  }) => _send(() async {
    final filename = filePath.split(Platform.pathSeparator).last;
    final form = FormData.fromMap({
      ...fields,
      field: await MultipartFile.fromFile(filePath, filename: filename),
    });

    return dio.postUri(Uri.parse(path(p)), data: form);
  });

  Uri _uri(String p, Map<String, dynamic>? query) {
    final values = <String, String>{};

    for (final entry in query?.entries ?? const <MapEntry<String, dynamic>>[]) {
      if (entry.value == null) {
        continue;
      }

      values[entry.key] = '${entry.value}';
    }

    return Uri.parse(path(p))
        .replace(queryParameters: values.isEmpty ? null : values);
  }

  Future<dynamic> _send(Future<Response<dynamic>> Function() call) async {
    final envelope = await _request(call);

    return envelope.data;
  }

  Future<ApiEnvelope> _sendEnvelope(
    Future<Response<dynamic>> Function() call,
  ) => _request(call);

  Future<ApiEnvelope> _request(
    Future<Response<dynamic>> Function() call,
  ) async {
    try {
      final response = await call();
      final body = response.data;

      if (body is Map && body['success'] == true) {
        return ApiEnvelope(
          data: body['data'],
          meta: body['meta'] is Map
              ? Map<String, dynamic>.from(body['meta'] as Map)
              : const {},
        );
      }

      throw ApiException(
        status: response.statusCode,
        message: 'Invalid server response.',
      );
    } on DioException catch (error) {
      final body = error.response?.data;
      final rawError = body is Map ? body['error'] : null;
      final details = rawError is Map ? rawError['details'] : null;
      final fields = <String, List<String>>{};

      if (details is Map) {
        for (final entry in details.entries) {
          fields['${entry.key}'] =
              (entry.value is List ? entry.value : ['${entry.value}'])
                  .map((value) => '$value')
                  .toList();
        }
      }

      final code = rawError is Map ? rawError['code']?.toString() : null;
      final message = rawError is Map
          ? rawError['message']?.toString()
          : (error.error is SocketException
                ? 'No internet connection.'
                : 'Request failed.');
      final status = error.response?.statusCode;

      if (status == 401 || code == 'DEVICE_REVOKED') {
        onAuthRevoked?.call();
      }

      throw ApiException(
        status: status,
        message: message ?? 'Request failed.',
        code: code,
        fieldErrors: fields,
        retryable: status == null || status == 408 || status == 425 || status == 429 || status >= 500,
      );
    }
  }
}

class ApiEnvelope {
  const ApiEnvelope({required this.data, required this.meta});

  final dynamic data;
  final Map<String, dynamic> meta;
}
