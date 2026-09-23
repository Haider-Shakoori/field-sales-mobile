import 'package:field_sales_mobile/core/api/api_client.dart';
import 'package:field_sales_mobile/core/db/app_database.dart';
import 'package:field_sales_mobile/core/storage/secret_store.dart';
import 'package:field_sales_mobile/features/stock/stock_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<String> _databasePath() async =>
    p.join(await getDatabasesPath(), 'field_sales.db');

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    await deleteDatabase(await _databasePath());
  });

  test('database v13 creates stock and return tables', () async {
    final db = AppDatabase();
    await db.open();

    final tables = (await db.db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    )).map((row) => row['name']).toSet();
    final indexes = (await db.db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='index'",
    )).map((row) => row['name']).toSet();

    expect(
      tables,
      containsAll([
        'local_salesman_stock',
        'local_sales_returns',
        'local_sales_return_items',
      ]),
    );
    expect(
      indexes,
      containsAll([
        'idx_stock_tenant_product',
        'idx_returns_tenant_uuid',
        'idx_returns_sync',
        'idx_return_items_unique',
      ]),
    );

    await db.db.close();
  });

  test('pending local orders reserve cached salesman stock', () async {
    final db = AppDatabase();
    await db.open();
    const tenantId = 'stock-tenant';

    await db.setting('stock.enabled.$tenantId', true);
    await db.db.insert('local_salesman_stock', {
      'tenant_id': tenantId,
      'product_uuid': 'product-1',
      'sku': 'SKU-1',
      'name': 'Product One',
      'unit': 'pcs',
      'sellable_qty': 5,
      'damaged_qty': 0,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    await db.db.insert('local_orders', {
      'tenant_id': tenantId,
      'offline_uuid': 'order-1',
      'customer_uuid': 'customer-1',
      'customer_name': 'Customer One',
      'ordered_at': DateTime.now().toUtc().toIso8601String(),
      'payment_type': 'cash',
      'status': 'pending',
      'currency': 'AFN',
      'subtotal': 200,
      'discount_total': 0,
      'grand_total': 200,
      'client_estimated_total': 200,
      'pricing_adjusted': 0,
      'sync_status': 'pending',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    await db.db.insert('local_order_items', {
      'tenant_id': tenantId,
      'order_offline_uuid': 'order-1',
      'product_uuid': 'product-1',
      'product_sku': 'SKU-1',
      'product_name': 'Product One',
      'unit': 'pcs',
      'quantity': 2,
      'unit_price': 100,
      'discount_percent': 0,
      'discount_amount': 0,
      'line_total': 200,
    });

    final repository = StockRepository(api: ApiClient(SecretStore()), db: db);

    expect(await repository.availableForProduct(tenantId, 'product-1'), 3);

    await expectLater(
      repository.validateOrderLines(tenantId, [
        {'product_id': 'product-1', 'name': 'Product One', 'quantity': 4},
      ]),
      throwsA(isA<StateError>()),
    );

    await repository.validateOrderLines(tenantId, [
      {'product_id': 'product-1', 'name': 'Product One', 'quantity': 3},
    ]);

    await db.db.close();
  });

  test('stock control disabled does not restrict offline orders', () async {
    final db = AppDatabase();
    await db.open();
    const tenantId = 'legacy-tenant';

    final repository = StockRepository(api: ApiClient(SecretStore()), db: db);

    expect(
      await repository.availableForProduct(tenantId, 'missing-product'),
      double.infinity,
    );

    await repository.validateOrderLines(tenantId, [
      {
        'product_id': 'missing-product',
        'name': 'Legacy Product',
        'quantity': 99,
      },
    ]);

    await db.db.close();
  });

  test(
    'customer return is stored offline with resalable and damaged items',
    () async {
      final db = AppDatabase();
      await db.open();
      const tenantId = 'return-tenant';

      final repository = StockRepository(api: ApiClient(SecretStore()), db: db);

      final uuid = await repository.createReturnOffline(
        tenantId: tenantId,
        customer: {'id': 'customer-1', 'name': 'Customer One'},
        notes: 'Mixed return',
        items: [
          {
            'product_id': 'product-1',
            'sku': 'SKU-1',
            'name': 'Product One',
            'unit': 'pcs',
            'quantity': 2,
            'condition': 'resalable',
            'reason': 'Wrong item',
          },
          {
            'product_id': 'product-1',
            'sku': 'SKU-1',
            'name': 'Product One',
            'unit': 'pcs',
            'quantity': 1,
            'condition': 'damaged',
            'reason': 'Crushed',
          },
        ],
      );

      final returns = await db.db.query(
        'local_sales_returns',
        where: 'tenant_id=? AND offline_uuid=?',
        whereArgs: [tenantId, uuid],
      );
      final items = await db.db.query(
        'local_sales_return_items',
        where: 'tenant_id=? AND return_offline_uuid=?',
        whereArgs: [tenantId, uuid],
        orderBy: 'id ASC',
      );

      expect(returns, hasLength(1));
      expect(returns.single['sync_status'], 'pending');
      expect(items, hasLength(2));
      expect(items.map((row) => row['condition']).toSet(), {
        'resalable',
        'damaged',
      });

      await db.db.close();
    },
  );
}
