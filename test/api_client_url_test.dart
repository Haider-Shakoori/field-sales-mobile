import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:field_sales_mobile/core/api/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_harness.dart';

/// Regression coverage for the Batch 6 path bug that produced
/// `.../api/v1customers` instead of `.../api/v1/customers`.
void main() {
  group('ApiClient URL construction', () {
    test('normalizePath adds exactly one leading slash', () {
      expect(ApiClient.normalizePath('customers'), '/customers');
      expect(ApiClient.normalizePath('/customers'), '/customers');
      expect(
        ApiClient.normalizePath('routes/10/customers'),
        '/routes/10/customers',
      );
      expect(ApiClient.normalizePath(''), '/');
    });

    test('slashless Batch 6 master-data paths resolve correctly', () async {
      const baseUrl = 'https://example.test/api/v1';
      const masterDataPaths = [
        'customers',
        'territories',
        'routes',
        'products',
        'price-lists',
        'routes/10/customers',
      ];

      for (final path in masterDataPaths) {
        final adapter = _RecordingAdapter();
        final client = ApiClient(
          secureStorage: FakeSecretStore(installationUuid: 'url-device'),
          dio: Dio(BaseOptions(baseUrl: baseUrl))..httpClientAdapter = adapter,
        );

        await client.requestEnvelope(method: 'GET', path: path);

        expect(
          adapter.uris.single.toString(),
          '$baseUrl/$path',
          reason: 'path "$path" must not be concatenated without a separator',
        );
      }
    });

    test('leading-slash paths are not double-prefixed', () async {
      const baseUrl = 'https://example.test/api/v1';
      final adapter = _RecordingAdapter();
      final client = ApiClient(
        secureStorage: FakeSecretStore(installationUuid: 'url-device'),
        dio: Dio(BaseOptions(baseUrl: baseUrl))..httpClientAdapter = adapter,
      );

      await client.requestEnvelope(
        method: 'GET',
        path: '/settings/attendance-tracking',
      );
      await client.requestEnvelope(method: 'POST', path: '/gps/locations');

      expect(adapter.uris.map((uri) => uri.toString()), [
        '$baseUrl/settings/attendance-tracking',
        '$baseUrl/gps/locations',
      ]);
    });

    test('query parameters and version prefix are preserved', () async {
      const baseUrl = 'https://example.test/api/v1';
      final adapter = _RecordingAdapter();
      final client = ApiClient(
        secureStorage: FakeSecretStore(installationUuid: 'url-device'),
        dio: Dio(BaseOptions(baseUrl: baseUrl))..httpClientAdapter = adapter,
      );

      await client.requestEnvelope(
        method: 'GET',
        path: 'customers',
        query: {'page': 2},
      );

      expect(adapter.uris.single.path, '/api/v1/customers');
      expect(adapter.uris.single.queryParameters['page'], '2');
    });
  });
}

class _RecordingAdapter implements HttpClientAdapter {
  final List<Uri> uris = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    uris.add(options.uri);
    return ResponseBody.fromString(
      jsonEncode({'success': true, 'data': <String, dynamic>{}, 'meta': {}}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
