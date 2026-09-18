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

    test(
      'parses real Laravel UUID public ids without losing identity',
      () async {
        api.onRequest = (method, path, body) async => {
          'token': 'tok-uuid',
          'user': {
            'id': '01a0b06e-cb99-71e0-baf6-0d305b07693a',
            'name': 'Salesman',
            'email': 'salesman@demo.test',
            'role': 'salesman',
            'branch_id': null,
          },
          'tenant': {
            'id': '01a0b06e-c5b0-73c0-a8b6-2f44977f916e',
            'name': 'Demo Distributors',
            'slug': 'demo-distributors',
          },
          'permissions': <String>[],
          'device': {
            'id': '01a0b06e-d0ea-7188-829a-c98934555250',
            'uuid': 'dev-1',
            'status': 'active',
          },
        };

        final session = await auth.login(
          email: 'salesman@demo.test',
          password: 'secret',
          pushToken: '',
        );

        expect(session.user.id, 0);
        expect(session.user.key, '01a0b06e-cb99-71e0-baf6-0d305b07693a');
        expect(session.tenant.key, '01a0b06e-c5b0-73c0-a8b6-2f44977f916e');
        expect(session.device!.uuid, 'dev-1');
      },
    );

    test(
      'generates and persists an installation uuid for a fresh install',
      () async {
        final freshStore = FakeSecretStore(installationUuid: '');
        final freshApi = _AuthApi(freshStore);
        final freshAuth = AuthRepository(
          apiClient: freshApi,
          secureStorage: freshStore,
          deviceModelProvider: () async => 'TestPatch',
        );
        Object? capturedBody;
        freshApi.onRequest = (method, path, body) async {
          capturedBody = body;
          return {
            'token': 'tok-fresh',
            'user': {'id': 'u-1', 'name': 'A', 'email': 'a@b.c'},
            'tenant': {'id': 't-1', 'name': 'T'},
            'permissions': <String>[],
          };
        };

        await freshAuth.login(
          email: 'a@b.c',
          password: 'secret',
          pushToken: '',
        );

        final deviceUuid = (capturedBody! as Map)['device_uuid'] as String;
        expect(deviceUuid, isNotEmpty);
        expect(deviceUuid.length, greaterThan(20));
        expect(await freshStore.readInstallationUuid(), deviceUuid);
      },
    );

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
