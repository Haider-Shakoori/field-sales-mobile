import 'package:field_sales_mobile/core/api/api_client.dart';
import 'package:field_sales_mobile/core/api/api_exception.dart';
import 'package:field_sales_mobile/core/api/auth_repository.dart';
import 'package:field_sales_mobile/core/storage/secret_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_harness.dart';

void main() {
  late FakeSecretStore store;
  late _AuthApi api;
  late AuthRepository auth;

  setUp(() async {
    await initTestDatabase();
    store = FakeSecretStore(installationUuid: 'dev-1');
    api = _AuthApi(store);
    auth = AuthRepository(
      apiClient: api,
      secureStorage: store,
      deviceModelProvider: () async => 'TestPatch',
    );
  });

  tearDown(tearDownDatabase);

  group('AUTH — login', () {
    test('sends device metadata and persists the issued token', () async {
      api.onRequest = (method, path, body) async {
        expect(method, 'POST');
        expect(path, '/auth/login');
        final map = body as Map<String, dynamic>;
        expect(map['email'], 'sales@shop.test');
        expect(map['device_uuid'], 'dev-1');
        expect(map['device_model'], 'TestPatch');
        expect(map['push_token'], 'fcm-1');
        return {
          'token': 'tok-abc',
          'user': {
            'id': 7,
            'name': 'Salesman Seven',
            'email': 'sales@shop.test',
            'role': 'salesman',
          },
          'tenant': {'id': 3, 'name': 'Shop Three', 'slug': 'shop-three'},
          'permissions': ['customers:read', 'products:read'],
          'device': {'id': 9, 'uuid': 'dev-1', 'status': 'active'},
        };
      };

      final session = await auth.login(
        email: 'sales@shop.test',
        password: 'secret',
        pushToken: 'fcm-1',
      );

      expect(session.token, 'tok-abc');
      expect(session.user.name, 'Salesman Seven');
      expect(session.tenant.name, 'Shop Three');
      expect(await store.readToken(), 'tok-abc');
      expect(await store.readCachedEmail(), 'sales@shop.test');
    });

    test('propagates invalid-credentials without persisting a token', () async {
      api.onRequest = (method, path, body) async {
        throw ApiException(
          status: 401,
          message: 'Invalid credentials',
          code: 'INVALID_CREDENTIALS',
        );
      };

      await expectLater(
        auth.login(email: 'bad@x.test', password: 'nope', pushToken: ''),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'INVALID_CREDENTIALS')
              .having((e) => e.isUnauthenticated, 'isUnauthenticated', true),
        ),
      );
      expect(await store.readToken(), isNull);
    });
  });

  group('AUTH — refresh + logout', () {
    test('refresh rotates and persists a fresh token', () async {
      store.token = 'old';
      api.onRequest = (method, path, body) async {
        expect(path, '/auth/refresh');
        return {'token': 'new-token'};
      };

      final token = await auth.refresh();
      expect(token, 'new-token');
      expect(await store.readToken(), 'new-token');
    });

    test('logout clears the token even when the server call fails', () async {
      store.token = 'tok-abc';
      api.onRequest = (method, path, body) async {
        throw ApiException(status: 500, message: 'server down');
      };

      await auth.logout();
      expect(await store.readToken(), isNull);
    });
  });

  group('AUTH — error mapping', () {
    test('envelope errors surfaces mapping exception', () async {
      api.onEnvelope = (path, query) async {
        throw ApiException(
          status: 422,
          message: 'The given data was invalid.',
          fieldErrors: {
            'email': ['The email field is required.'],
          },
        );
      };

      await expectLater(
        api.requestEnvelope(method: 'POST', path: '/auth/login'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.status, 'status', 422)
              .having((e) => e.isValidation, 'isValidation', true)
              .having((e) => e.fieldErrors['email'], 'email errors', [
                'The email field is required.',
              ]),
        ),
      );
    });

    test('upgrade-required detection from status 426', () {
      final upgrade = ApiException(status: 426, message: 'Update app');
      expect(upgrade.isUpgradeRequired, isTrue);

      final revoked = ApiException(
        status: 401,
        message: 'Dead',
        code: 'DEVICE_REVOKED',
      );
      expect(revoked.isDeviceRevoked, isTrue);
      expect(revoked.isUnauthenticated, isTrue);

      final conflict = ApiException(status: 409, message: 'stale');
      expect(conflict.isConflict, isTrue);
    });
  });
}

class _AuthApi extends ApiClient {
  _AuthApi(SecretStore store) : super(secureStorage: store);

  Future<dynamic> Function(String method, String path, Object? body)? onRequest;
  Future<ApiEnvelope> Function(String path, Map<String, dynamic>? query)?
  onEnvelope;

  @override
  Future<dynamic> request({
    required String method,
    required String path,
    Map<String, dynamic>? query,
    Object? body,
    String? idempotencyKey,
  }) async {
    final handler = onRequest;
    if (handler != null) {
      return handler(method, path, body);
    }
    throw StateError('unhandled $method $path');
  }

  @override
  Future<ApiEnvelope> requestEnvelope({
    required String method,
    required String path,
    Map<String, dynamic>? query,
    Object? body,
    String? idempotencyKey,
  }) async {
    final handler = onEnvelope;
    if (handler != null) {
      return handler(path, query);
    }
    throw StateError('unhandled envelope $path');
  }
}
