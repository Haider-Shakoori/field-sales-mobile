import 'package:field_sales_mobile/core/api/api_client.dart';
import 'package:field_sales_mobile/core/storage/app_database.dart';
import 'package:field_sales_mobile/core/storage/master_data_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_harness.dart';

void main() {
  setUp(initTestDatabase);

  tearDown(tearDownDatabase);

  group('OFFLINE CACHE — all-pages refresh', () {
    test('pulls every page and upserts into SQLite', () async {
      var customersPageCalls = 0;
      final repo = MasterDataRepository(
        apiClient: _FakeApi((path, query) async {
          final page = (query?['page'] as num?)?.toInt() ?? 1;
          switch (path) {
            case 'customers':
              customersPageCalls++;
              if (page == 1) {
                return ApiEnvelope(
                  data: [_customerJson(1, 'Alpha'), _customerJson(2, 'Beta')],
                  meta: _meta(page: 1, lastPage: 2),
                );
              }
              return ApiEnvelope(
                data: [_customerJson(3, 'Gamma')],
                meta: _meta(page: 2, lastPage: 2),
              );
            case 'territories':
            case 'routes':
            case 'price-lists':
              return ApiEnvelope(data: <Object>[], meta: _meta(page: 1));
            case 'products':
              return ApiEnvelope(data: [_productJson(1)], meta: _meta(page: 1));
            default:
              throw StateError('unexpected path $path');
          }
        }),
      );

      await repo.refreshCustomers();

      expect(customersPageCalls, 2);
      expect(await repo.localCustomers(), hasLength(3));
    });

    test('refreshAll caches every domain the app reads offline', () async {
      final repo = MasterDataRepository(
        apiClient: _FakeApi((path, query) async {
          switch (path) {
            case 'customers':
              return ApiEnvelope(
                data: [_customerJson(1, 'Alpha')],
                meta: _meta(page: 1),
              );
            case 'territories':
              return ApiEnvelope(
                data: [_territoryJson(1, 'Central')],
                meta: _meta(page: 1),
              );
            case 'routes':
              return ApiEnvelope(
                data: [_routeJson(10, 'Route A')],
                meta: _meta(page: 1),
              );
            case 'products':
              return ApiEnvelope(data: [_productJson(1)], meta: _meta(page: 1));
            case 'price-lists':
              return ApiEnvelope(
                data: [_priceListJson(1, 'Default')],
                meta: _meta(page: 1),
              );
            case 'routes/10/customers':
              return ApiEnvelope(
                data: [_routeCustomerJson(1)],
                meta: _meta(page: 1),
              );
            default:
              throw StateError('unexpected path $path');
          }
        }),
      );

      await repo.refreshAll();

      expect(await repo.localCustomers(), hasLength(1));
      expect(await repo.localTerritories(), hasLength(1));
      expect(await repo.localRoutes(), hasLength(1));
      expect(await repo.localProducts(), hasLength(1));
      expect(await repo.localPriceLists(), hasLength(1));
      expect(await repo.localRouteCustomers(10), hasLength(1));
      expect((await repo.localCounts())['customers'], 1);
    });

    test(
      'a failed page refresh leaves prior cache intact (never clears)',
      () async {
        final good = MasterDataRepository(
          apiClient: _FakeApi((path, query) async {
            if (path == 'customers') {
              return ApiEnvelope(
                data: [_customerJson(1, 'Alpha')],
                meta: _meta(page: 1),
              );
            }
            return ApiEnvelope(data: <Object>[], meta: _meta(page: 1));
          }),
        );
        await good.refreshCustomers();
        expect(await good.localCustomers(), hasLength(1));

        final boom = Exception('boom');
        final failing = MasterDataRepository(
          apiClient: _FakeApi((path, query) async {
            if (path == 'customers') {
              throw boom;
            }
            return ApiEnvelope(data: <Object>[], meta: _meta(page: 1));
          }),
        );

        await expectLater(failing.refreshCustomers(), throwsA(boom));

        final customers = await good.localCustomers();
        expect(customers, hasLength(1));
        expect(customers.single.name, 'Alpha');
      },
    );
  });

  group('OFFLINE CACHE — offline reads', () {
    test('local getters never touch the network', () async {
      final repo = MasterDataRepository(apiClient: _ExplodingClient());

      await _seedCustomerRow(1, 'Offline Shop');
      await _seedProductRow(1, 'Salt', 0.5);
      await _seedRouteRow(1, 'Offline Route');

      final customers = await repo.localCustomers();
      final products = await repo.localProducts();
      final routes = await repo.localRoutes(territoryId: 1);

      expect(customers.single.name, 'Offline Shop');
      expect(products.single.name, 'Salt');
      expect(routes, isEmpty);
    });
  });
}

class _FakeApi extends ApiClient {
  _FakeApi(this.handler) : super(secureStorage: FakeSecretStore());

  final Future<ApiEnvelope> Function(String path, Map<String, dynamic>? query)
  handler;

  @override
  Future<ApiEnvelope> requestEnvelope({
    required String method,
    required String path,
    Map<String, dynamic>? query,
    Object? body,
    String? idempotencyKey,
  }) => handler(path, query);
}

class _ExplodingClient extends ApiClient {
  _ExplodingClient() : super(secureStorage: FakeSecretStore());

  @override
  Future<ApiEnvelope> requestEnvelope({
    required String method,
    required String path,
    Map<String, dynamic>? query,
    Object? body,
    String? idempotencyKey,
  }) => throw StateError('local reads must never call the network');
}

Map<String, dynamic> _meta({required int page, int lastPage = 1}) => {
  'page': page,
  'per_page': 100,
  'total': lastPage * 100,
  'last_page': lastPage,
};

Map<String, dynamic> _customerJson(int id, String name) => {
  'id': id,
  'uuid': 'c-$id',
  'offline_uuid': 'c-$id',
  'code': 'C$id',
  'name': name,
  'business_name': name,
  'contact_person': null,
  'phone': '555-$id',
  'address': 'Addr $id',
  'is_active': true,
  'credit_limit': 100.0,
  'outstanding_balance': 10.0,
};

Map<String, dynamic> _territoryJson(int id, String name) => {
  'id': id,
  'uuid': 't-$id',
  'code': 'T$id',
  'name': name,
  'is_active': true,
};

Map<String, dynamic> _routeJson(int id, String name) => {
  'id': id,
  'uuid': 'r-$id',
  'code': 'R$id',
  'name': name,
  'territory_id': 1,
  'territory': {'id': 1, 'name': 'Central'},
  'is_active': true,
};

Map<String, dynamic> _routeCustomerJson(int customerId) => {
  'id': customerId,
  'uuid': 'c-$customerId',
  'name': 'Customer $customerId',
  'business_name': 'Customer $customerId',
  'visit_order': 1,
  'route_customer_id': 900,
};

Map<String, dynamic> _productJson(int id) => {
  'id': id,
  'uuid': 'p-$id',
  'sku': 'SKU-$id',
  'name': 'Product $id',
  'category': 'cat',
  'unit': 'pcs',
  'price': 5.0,
  'is_active': true,
};

Map<String, dynamic> _priceListJson(int id, String name) => {
  'id': id,
  'uuid': 'pl-$id',
  'name': name,
  'is_default': true,
  'is_active': true,
};

Future<void> _seedCustomerRow(int id, String name) async {
  final db = await AppDatabase.instance;
  await db.insert('customers', {
    'id': id,
    'uuid': 'c-$id',
    'name': name,
    'business_name': name,
    'is_active': 1,
  });
}

Future<void> _seedProductRow(int id, String name, double price) async {
  final db = await AppDatabase.instance;
  await db.insert('products', {
    'id': id,
    'uuid': 'p-$id',
    'name': name,
    'price': price,
    'is_active': 1,
  });
}

Future<void> _seedRouteRow(int id, String name) async {
  final db = await AppDatabase.instance;
  await db.insert('routes', {
    'id': id,
    'uuid': 'r-$id',
    'name': name,
    'territory_id': null,
    'is_active': 1,
  });
}
