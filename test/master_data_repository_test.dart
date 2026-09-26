import 'package:field_sales_mobile/core/db/app_database.dart';
import 'package:field_sales_mobile/core/db/local_first_transaction.dart';
import 'package:field_sales_mobile/features/customers/customer_repository.dart';
import 'package:field_sales_mobile/features/master_data/master_data_repository.dart';
import 'package:field_sales_mobile/features/master_data/master_data_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeMasterDataSource implements MasterDataSource {
  final calls = <String>[];
  final posts = <Map<String, dynamic>>[];
  final patches = <Map<String, dynamic>>[];

  @override
  Future<MasterPage> fetchPage(
    String path, {
    int page = 1,
    int perPage = 100,
    String? updatedSince,
  }) async {
    calls.add('$path?page=$page&since=${updatedSince ?? ''}');

    if (path == 'products') {
      if (page == 1) {
        return const MasterPage(
          rows: [
            {
              'id': 'product-1',
              'sku': 'P1',
              'name': 'One',
              'base_price': 1,
              'currency': 'AFN',
            },
          ],
          hasMore: true,
          nextPage: 2,
        );
      }

      return const MasterPage(
        rows: [
          {
            'id': 'product-2',
            'sku': 'P2',
            'name': 'Two',
            'base_price': 2,
            'currency': 'AFN',
          },
        ],
        hasMore: false,
        nextPage: null,
      );
    }

    if (path == 'routes') {
      return const MasterPage(
        rows: [
          {
            'id': 'route-uuid',
            'code': 'R1',
            'name': 'Route',
            'weekdays': ['mon'],
          },
        ],
        hasMore: false,
        nextPage: null,
      );
    }

    if (path == 'price-lists') {
      return const MasterPage(
        rows: [
          {
            'id': 'price-list-uuid',
            'code': 'PL',
            'name': 'Retail',
            'currency': 'AFN',
          },
        ],
        hasMore: false,
        nextPage: null,
      );
    }

    if (path == 'routes/route-uuid/customers') {
      return const MasterPage(
        rows: [
          {'id': 'customer-1', 'name': 'Shop'},
        ],
        hasMore: false,
        nextPage: null,
      );
    }

    if (path == 'price-lists/price-list-uuid/items') {
      return const MasterPage(
        rows: [
          {
            'id': 'item-1',
            'price_list_id': 'price-list-uuid',
            'product_id': 'product-1',
            'min_quantity': 1,
            'price': 0.9,
          },
        ],
        hasMore: false,
        nextPage: null,
      );
    }

    return const MasterPage(rows: [], hasMore: false, nextPage: null);
  }

  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> payload,
  ) async {
    posts.add({'path': path, ...payload});

    return {'id': payload['offline_uuid'], ...payload, 'is_active': true};
  }

  @override
  Future<Map<String, dynamic>> patch(
    String path,
    Map<String, dynamic> payload,
  ) async {
    patches.add({'path': path, ...payload});
    final id = path.split('/').last;

    return {'id': id, ...payload, 'is_active': true};
  }
}

void main() {
  late AppDatabase database;
  late FakeMasterDataSource source;
  late MasterDataRepository masterData;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    final path = p.join(await getDatabasesPath(), 'field_sales.db');
    await deleteDatabase(path);

    database = AppDatabase();
    await database.open();
    source = FakeMasterDataSource();
    masterData = MasterDataRepository(database: database, source: source);
  });

  tearDown(() async {
    await database.db.close();
  });

  test('refresh caches every page and uses public UUID nested paths', () async {
    await masterData.refreshAll('tenant-a');

    final products = await masterData.list('products', 'tenant-a');
    final routeCustomers = await masterData.list('route_customers', 'tenant-a');
    final priceItems = await masterData.list('price_list_items', 'tenant-a');

    expect(products.map((row) => row['id']), ['product-1', 'product-2']);
    expect(routeCustomers.single['route_id'], 'route-uuid');
    expect(priceItems.single['product_id'], 'product-1');

    expect(
      source.calls.any(
        (call) => call.startsWith('routes/route-uuid/customers?'),
      ),
      isTrue,
    );
    expect(
      source.calls.any(
        (call) => call.startsWith('price-lists/price-list-uuid/items?'),
      ),
      isTrue,
    );
  });

  test('master cache is isolated by tenant', () async {
    await masterData.cacheServerRow(
      table: 'products',
      tenantId: 'tenant-a',
      row: {'id': 'a-product', 'name': 'A'},
    );
    await masterData.cacheServerRow(
      table: 'products',
      tenantId: 'tenant-b',
      row: {'id': 'b-product', 'name': 'B'},
    );

    expect(
      (await masterData.list('products', 'tenant-a')).single['id'],
      'a-product',
    );
    expect(
      (await masterData.list('products', 'tenant-b')).single['id'],
      'b-product',
    );
  });

  test(
    'offline customer and outbox are committed atomically then sync',
    () async {
      final customers = CustomerRepository(
        database: database,
        transactions: LocalFirstTransaction(database),
        masterData: masterData,
        source: source,
      );

      final local = await customers.createOffline(
        tenantId: 'tenant-a',
        name: 'Offline Shop',
        phone: '0700000000',
      );

      final cached = await masterData.list('customers', 'tenant-a');
      final queue = await database.db.query(
        'sync_queue',
        where: 'tenant_id = ?',
        whereArgs: ['tenant-a'],
      );

      expect(cached.single['id'], local['id']);
      expect(queue.single['status'], 'pending');

      final result = await customers.syncPending('tenant-a');

      expect(result.synced, 1);
      expect(result.failed, 0);
      expect(source.posts.single['path'], 'customers');

      final syncedQueue = await database.db.query(
        'sync_queue',
        where: 'tenant_id = ?',
        whereArgs: ['tenant-a'],
      );
      expect(syncedQueue.single['status'], 'done');
      expect(await masterData.pendingCount('tenant-a'), 0);
    },
  );

  test('offline customer edits are coalesced and sync with PATCH', () async {
    final customers = CustomerRepository(
      database: database,
      transactions: LocalFirstTransaction(database),
      masterData: masterData,
      source: source,
    );

    await masterData.cacheServerRow(
      table: 'customers',
      tenantId: 'tenant-a',
      row: {
        'id': 'customer-1',
        'name': 'Original Shop',
        'code': 'CUS-1',
        'latitude': 34.5,
        'longitude': 69.1,
        'geofence_radius_meters': 100,
        'is_active': true,
      },
    );

    await customers.updateOffline(
      tenantId: 'tenant-a',
      customerUuid: 'customer-1',
      name: 'Updated Shop',
      code: 'CUS-1',
      phone: '0700111222',
      address: 'New address',
      latitude: 34.55,
      longitude: 69.2,
    );

    await customers.updateOffline(
      tenantId: 'tenant-a',
      customerUuid: 'customer-1',
      name: 'Updated Shop Again',
      code: 'CUS-1',
      phone: '0700111222',
      address: 'Final address',
      latitude: 34.56,
      longitude: 69.21,
    );

    final queued = await database.db.query(
      'sync_queue',
      where: 'tenant_id=? AND entity_type=? AND entity_uuid=?',
      whereArgs: ['tenant-a', 'customer', 'customer-1'],
    );

    expect(queued, hasLength(1));
    expect(queued.single['action'], 'update');

    final result = await customers.syncPending('tenant-a');

    expect(result.synced, 1);
    expect(result.failed, 0);
    expect(source.patches, hasLength(1));
    expect(source.patches.single['path'], 'customers/customer-1');
    expect(source.patches.single['name'], 'Updated Shop Again');

    final cached = await masterData.list('customers', 'tenant-a');
    expect(cached.single['name'], 'Updated Shop Again');
    expect(cached.single['latitude'], 34.56);
  });

  test('delta refresh records a tenant-specific sync cursor', () async {
    await masterData.refreshAll('tenant-a');
    final firstProductCall = source.calls.firstWhere(
      (call) => call.startsWith('products?'),
    );
    expect(firstProductCall, contains('since='));

    source.calls.clear();
    await masterData.refreshAll('tenant-a');

    final secondProductCall = source.calls.firstWhere(
      (call) => call.startsWith('products?'),
    );
    expect(secondProductCall, isNot(endsWith('since=')));
  });
}
