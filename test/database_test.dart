import 'dart:io';

import 'package:field_sales_mobile/core/storage/app_database.dart';
import 'package:field_sales_mobile/core/storage/master_data_repository.dart';
import 'package:field_sales_mobile/core/storage/session_meta_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/test_harness.dart';

void main() {
  late MasterDataRepository repo;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    await initTestDatabase();
    repo = MasterDataRepository(apiClient: FakeApiClient());
  });

  tearDown(tearDownDatabase);

  group('DATABASE — schema init', () {
    test('v2 creates every master-data table', () async {
      final tables = <String>{};
      final rows = await DbAsserts.query(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );
      for (final row in rows) {
        tables.add(row['name']!.toString());
      }

      expect(
        tables,
        containsAll([
          'customers',
          'territories',
          'routes',
          'route_customers',
          'products',
          'price_lists',
          'price_list_items',
          'session_meta',
          'sync_queue',
          'local_products',
          'local_settings',
          'local_sync_log',
        ]),
      );
    });

    test('v1 database upgrades to v2 without data loss', () async {
      final dir = Directory.systemTemp.createTempSync('field_sales_v1');
      final dbPath = '${dir.path}${Platform.pathSeparator}upgrade.db';
      addTearDown(() => dir.deleteSync(recursive: true));

      final legacy = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(version: 1, onCreate: _v1Create),
      );
      await legacy.insert('local_settings', {'key': 'keep', 'value': 'me'});
      await legacy.close();

      final upgraded = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: AppDatabase.version,
          onCreate: AppDatabase.createSchema,
          onUpgrade: AppDatabase.upgradeSchema,
        ),
      );
      AppDatabase.overrideInstance(upgraded);

      final settings = await DbAsserts.query('SELECT * FROM local_settings');
      expect(settings, isNotEmpty);
      expect(settings.single['key'], 'keep');

      final tables = <String>{};
      final rows = await DbAsserts.query(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );
      for (final row in rows) {
        tables.add(row['name']!.toString());
      }
      expect(tables, contains('customers'));
      expect(tables, contains('products'));
      expect(tables, contains('session_meta'));
      await upgraded.close();
    });
  });

  group('DATABASE — customer upsert/read', () {
    test('insert then replace an existing row by id', () async {
      await _seedCustomer(id: 1, name: 'Alpha Shop');
      await _seedCustomer(id: 1, name: 'Alpha Renamed');

      final customers = await repo.localCustomers();
      expect(customers, hasLength(1));
      expect(customers.single.name, 'Alpha Renamed');

      await _seedCustomer(id: 2, name: 'Beta Shop');
      expect(await repo.localCustomers(), hasLength(2));
    });

    test('route filter returns only members of that route', () async {
      await _seedCustomer(id: 1, name: 'A', routeId: 10);
      await _seedCustomer(id: 2, name: 'B', routeId: 11);

      final onRoute10 = await repo.localCustomers(routeId: 10);
      expect(onRoute10, hasLength(1));
      expect(onRoute10.single.name, 'A');
    });
  });

  group('DATABASE — route + route-customer upsert/read', () {
    test('routes store territory lineage and membership', () async {
      await _seedRoute(id: 10, name: 'Route A', territoryId: 4);
      await _seedRoute(id: 11, name: 'Route B');
      await _seedRouteCustomer(routeId: 10, customerId: 1, order: 1);
      await _seedRouteCustomer(routeId: 10, customerId: 2, order: 2);

      final routes = await repo.localRoutes();
      expect(routes, hasLength(2));

      final a = routes.firstWhere((r) => r.id == 10);
      expect(a.name, 'Route A');
      expect(a.territoryId, 4);

      final members = await repo.localRouteCustomers(10);
      expect(members, hasLength(2));
      expect(members.first.visitOrder, 1);
    });
  });

  group('DATABASE — product + price-list upsert/read', () {
    test('products, price lists and items share lineage', () async {
      await _seedProduct(id: 100, name: 'Tea 500g', price: 2.5);
      await _seedProduct(id: 101, name: 'Rice 5kg', price: 8.0);
      await _seedPriceList(id: 1, name: 'Default', isDefault: true);
      await _seedPriceListItem(priceListId: 1, productId: 100, price: 2.3);

      final products = await repo.localProducts();
      expect(products, hasLength(2));
      expect(products.firstWhere((p) => p.id == 100).price, 2.5);

      final lists = await repo.localPriceLists();
      expect(lists.single.name, 'Default');
      expect(lists.single.isDefault, isTrue);

      final items = await DbAsserts.query('SELECT * FROM price_list_items');
      expect(items, hasLength(1));
    });
  });

  group('DATABASE — session meta', () {
    test(
      'persists and restores user/tenant metadata and permissions',
      () async {
        final store = SessionMetaStore();
        await store.save(sampleSession());

        final restored = await store.load();
        expect(restored.user.name, 'Salesman Seven');
        expect(restored.user.email, 'sales@shop.test');
        expect(restored.user.role, 'salesman');
        expect(restored.tenant.id, 3);
        expect(restored.tenant.name, 'Shop Three');
        expect(
          restored.permissions,
          containsAll(['customers:read', 'products:read']),
        );

        await store.clear();
        final cleared = await store.load();
        expect(cleared.user.id, 0);
        expect(cleared.tenant.name, '');
      },
    );
  });
}

Future<void> _v1Create(Database db, int version) async {
  await db.execute('''
    CREATE TABLE sync_queue (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      entity_type TEXT NOT NULL,
      entity_uuid TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE local_products (uuid TEXT PRIMARY KEY, name TEXT NOT NULL)
  ''');
  await db.execute('''
    CREATE TABLE local_settings (key TEXT PRIMARY KEY, value TEXT)
  ''');
  await db.execute('''
    CREATE TABLE local_sync_log (id INTEGER PRIMARY KEY AUTOINCREMENT)
  ''');
}

Future<void> _seedCustomer({
  required int id,
  required String name,
  int? routeId,
}) async {
  final db = await AppDatabase.instance;
  await db.insert('customers', {
    'id': id,
    'uuid': 'c-$id',
    'name': name,
    'business_name': name,
    'route_id': ?routeId,
    'is_active': 1,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}

Future<void> _seedRoute({
  required int id,
  required String name,
  int? territoryId,
}) async {
  final db = await AppDatabase.instance;
  await db.insert('routes', {
    'id': id,
    'uuid': 'r-$id',
    'name': name,
    'territory_id': ?territoryId,
    'is_active': 1,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}

Future<void> _seedRouteCustomer({
  required int routeId,
  required int customerId,
  required int order,
}) async {
  final db = await AppDatabase.instance;
  await db.insert('route_customers', {
    'route_id': routeId,
    'customer_id': customerId,
    'customer_name': 'Customer $customerId',
    'visit_order': order,
    'is_active': 1,
  });
}

Future<void> _seedProduct({
  required int id,
  required String name,
  required double price,
}) async {
  final db = await AppDatabase.instance;
  await db.insert('products', {
    'id': id,
    'uuid': 'p-$id',
    'name': name,
    'price': price,
    'is_active': 1,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}

Future<void> _seedPriceList({
  required int id,
  required String name,
  required bool isDefault,
}) async {
  final db = await AppDatabase.instance;
  await db.insert('price_lists', {
    'id': id,
    'uuid': 'pl-$id',
    'name': name,
    'is_default': isDefault ? 1 : 0,
    'is_active': 1,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}

Future<void> _seedPriceListItem({
  required int priceListId,
  required int productId,
  required double price,
}) async {
  final db = await AppDatabase.instance;
  await db.insert('price_list_items', {
    'price_list_id': priceListId,
    'product_id': productId,
    'price': price,
  });
}
