import 'package:field_sales_mobile/core/api/api_client.dart';
import 'package:field_sales_mobile/core/db/app_database.dart';
import 'package:field_sales_mobile/core/storage/secret_store.dart';
import 'package:field_sales_mobile/core/sync/sync_retry_store.dart';
import 'package:field_sales_mobile/features/master_data/master_data_repository.dart';
import 'package:field_sales_mobile/features/master_data/master_data_source.dart';
import 'package:field_sales_mobile/features/orders/order_repository.dart';
import 'package:field_sales_mobile/features/stock/stock_return_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _UnusedSource implements MasterDataSource {
  @override
  Future<MasterPage> fetchPage(
    String path, {
    int page = 1,
    int perPage = 100,
    String? updatedSince,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> payload) {
    throw UnimplementedError();
  }
}

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

    expect(
      tables,
      containsAll([
        'local_stock_balances',
        'local_sales_returns',
        'local_sales_return_items',
      ]),
    );

    await db.db.close();
  });

  test('offline customer return persists header and items', () async {
    final db = AppDatabase();
    await db.open();

    final repository = StockReturnRepository(
      api: ApiClient(SecretStore()),
      db: db,
      retry: SyncRetryStore(db),
    );

    const tenantId = 'return-tenant';
    final customer = {'id': 'customer-1', 'name': 'Ahmad Shop'};
    final product = {
      'id': 'product-1',
      'sku': 'SKU-1',
      'name': 'Juice',
      'unit': 'carton',
    };

    final uuid = await repository.createOffline(
      tenantId: tenantId,
      customer: customer,
      returnedAt: DateTime.utc(2026, 9, 23, 12),
      visitUuid: 'visit-1',
      notes: 'Customer return',
      items: [
        ReturnDraftLine(
          product: product,
          quantity: 2,
          condition: 'resalable',
          reason: 'Wrong quantity delivered',
        ),
        ReturnDraftLine(
          product: product,
          quantity: 1,
          condition: 'damaged',
          reason: 'Damaged carton',
        ),
      ],
    );

    final headers = await db.db.query(
      'local_sales_returns',
      where: 'tenant_id=? AND offline_uuid=?',
      whereArgs: [tenantId, uuid],
    );
    final items = await repository.items(tenantId, uuid);

    expect(headers, hasLength(1));
    expect(headers.single['sync_status'], 'pending');
    expect(headers.single['customer_name'], 'Ahmad Shop');
    expect(items, hasLength(2));
    expect(items.map((row) => row['condition']).toSet(), {
      'resalable',
      'damaged',
    });

    await db.db.close();
  });

  test('offline order cannot exceed cached sellable van stock', () async {
    final db = AppDatabase();
    await db.open();

    const tenantId = 'stock-order-tenant';
    await db.setting('salesman_stock_enabled:$tenantId', true);
    await db.db.insert('local_stock_balances', {
      'tenant_id': tenantId,
      'product_uuid': 'product-1',
      'sku': 'SKU-1',
      'name': 'Juice',
      'unit': 'carton',
      'sellable_qty': 5,
      'damaged_qty': 1,
      'cached_at': DateTime.now().toUtc().toIso8601String(),
    });

    final master = MasterDataRepository(database: db, source: _UnusedSource());

    await master.cacheServerRow(
      table: 'products',
      tenantId: tenantId,
      row: {
        'id': 'product-1',
        'sku': 'SKU-1',
        'name': 'Juice',
        'unit': 'carton',
        'base_price': 100,
        'currency': 'AFN',
        'is_active': true,
      },
    );

    final repository = OrderRepository(
      api: ApiClient(SecretStore()),
      db: db,
      masterData: master,
    );
    final customer = {'id': 'customer-1', 'name': 'Ahmad Shop'};
    final product = {
      'id': 'product-1',
      'sku': 'SKU-1',
      'name': 'Juice',
      'unit': 'carton',
      'base_price': 100,
      'currency': 'AFN',
    };

    await expectLater(
      repository.preview(
        tenantId: tenantId,
        customer: customer,
        orderedAt: DateTime(2026, 9, 23),
        lines: [
          OrderDraftLine(product: product, quantity: 6, discountPercent: 0),
        ],
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message.toString(),
          'message',
          contains('exceeds available van stock'),
        ),
      ),
    );

    final uuid = await repository.createOffline(
      tenantId: tenantId,
      customer: customer,
      orderedAt: DateTime.utc(2026, 9, 23, 12),
      paymentType: 'cash',
      lines: [
        OrderDraftLine(product: product, quantity: 3, discountPercent: 0),
      ],
    );

    expect(uuid, isNotEmpty);

    await expectLater(
      repository.preview(
        tenantId: tenantId,
        customer: customer,
        orderedAt: DateTime(2026, 9, 23),
        lines: [
          OrderDraftLine(product: product, quantity: 3, discountPercent: 0),
        ],
      ),
      throwsA(isA<StateError>()),
    );

    await db.db.close();
  });
}
