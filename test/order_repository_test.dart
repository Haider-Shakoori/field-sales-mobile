import 'package:field_sales_mobile/core/api/api_client.dart';
import 'package:field_sales_mobile/core/db/app_database.dart';
import 'package:field_sales_mobile/core/storage/secret_store.dart';
import 'package:field_sales_mobile/core/sync/connectivity_gate.dart';
import 'package:field_sales_mobile/features/master_data/master_data_repository.dart';
import 'package:field_sales_mobile/features/master_data/master_data_source.dart';
import 'package:field_sales_mobile/features/orders/order_repository.dart';
import 'package:field_sales_mobile/features/stock/stock_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';


class _OfflineGate extends ConnectivityGate {
  @override
  Future<bool> isOnline() async => false;

  @override
  Stream<bool> get statusChanges => const Stream.empty();
}

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
    ConnectivityGate.instance = ConnectivityGate();
  });

  tearDown(() {
    ConnectivityGate.instance = ConnectivityGate();
  });

  test(
    'offline order uses cached tier pricing and persists atomically',
    () async {
      final db = AppDatabase();
      await db.open();

      final master = MasterDataRepository(
        database: db,
        source: _UnusedSource(),
      );
      const tenantId = 'tenant-order-test';

      await master.cacheServerRow(
        table: 'products',
        tenantId: tenantId,
        row: {
          'id': 'product-1',
          'sku': 'SKU-1',
          'name': 'Product One',
          'unit': 'pcs',
          'base_price': 100,
          'currency': 'AFN',
          'is_active': true,
        },
      );

      await master.cacheServerRow(
        table: 'price_lists',
        tenantId: tenantId,
        row: {
          'id': 'price-list-1',
          'code': 'RETAIL',
          'name': 'Retail',
          'currency': 'AFN',
          'effective_from': '2026-09-01',
          'effective_to': null,
          'is_active': true,
        },
      );

      await master.cacheServerRow(
        table: 'price_list_items',
        tenantId: tenantId,
        row: {
          'id': 'tier-1',
          'price_list_id': 'price-list-1',
          'product_id': 'product-1',
          'min_quantity': 1,
          'price': 90,
        },
      );

      await master.cacheServerRow(
        table: 'price_list_items',
        tenantId: tenantId,
        row: {
          'id': 'tier-10',
          'price_list_id': 'price-list-1',
          'product_id': 'product-1',
          'min_quantity': 10,
          'price': 80,
        },
      );

      final customer = {
        'id': 'customer-1',
        'name': 'Customer One',
        'price_list_id': 'price-list-1',
      };
      final product = {
        'id': 'product-1',
        'sku': 'SKU-1',
        'name': 'Product One',
        'unit': 'pcs',
        'base_price': 100,
        'currency': 'AFN',
      };

      final api = ApiClient(SecretStore());
      final stock = StockRepository(api: api, db: db);
      final repository = OrderRepository(
        api: api,
        db: db,
        masterData: master,
        stock: stock,
      );

      final preview = await repository.preview(
        tenantId: tenantId,
        customer: customer,
        orderedAt: DateTime(2026, 9, 19, 12),
        lines: [
          OrderDraftLine(product: product, quantity: 10, discountPercent: 5),
        ],
      );

      expect(preview.subtotal, 800);
      expect(preview.discountTotal, 40);
      expect(preview.grandTotal, 760);
      expect(preview.lines.single.unitPrice, 80);

      final uuid = await repository.createOffline(
        tenantId: tenantId,
        customer: customer,
        orderedAt: DateTime.utc(2026, 9, 19, 6),
        paymentType: 'credit',
        lines: [
          OrderDraftLine(product: product, quantity: 10, discountPercent: 5),
        ],
        visitUuid: 'visit-1',
        notes: 'Offline order',
      );

      final orders = await db.db.query(
        'local_orders',
        where: 'tenant_id=? AND offline_uuid=?',
        whereArgs: [tenantId, uuid],
      );
      final items = await db.db.query(
        'local_order_items',
        where: 'tenant_id=? AND order_offline_uuid=?',
        whereArgs: [tenantId, uuid],
      );

      expect(orders, hasLength(1));
      expect(items, hasLength(1));
      expect(orders.single['grand_total'], 760.0);
      expect(orders.single['sync_status'], 'pending');
      expect(items.single['unit_price'], 80.0);

      await db.db.close();
    },
  );

  test('offline reorder recommendations use repeat approved order cadence', () async {
    ConnectivityGate.instance = _OfflineGate();
    final db = AppDatabase();
    await db.open();
    final master = MasterDataRepository(database: db, source: _UnusedSource());
    const tenantId = 'tenant-reorder-test';

    await master.cacheServerRow(
      table: 'products',
      tenantId: tenantId,
      row: {
        'id': 'product-r1',
        'sku': 'R-1',
        'name': 'Repeat Product',
        'unit': 'pcs',
        'base_price': 100,
        'currency': 'AFN',
        'is_active': true,
      },
    );

    for (final entry in [
      ('o1', DateTime.utc(2026, 6, 25), 10.0),
      ('o2', DateTime.utc(2026, 7, 25), 12.0),
      ('o3', DateTime.utc(2026, 8, 25), 14.0),
    ]) {
      await db.db.insert('local_orders', {
        'tenant_id': tenantId,
        'offline_uuid': entry.$1,
        'customer_uuid': 'customer-r1',
        'customer_name': 'Repeat Customer',
        'ordered_at': entry.$2.toIso8601String(),
        'payment_type': 'cash',
        'status': 'approved',
        'currency': 'AFN',
        'subtotal': entry.$3 * 100,
        'discount_total': 0,
        'grand_total': entry.$3 * 100,
        'client_estimated_total': entry.$3 * 100,
        'pricing_adjusted': 0,
        'sync_status': 'synced',
        'created_at': entry.$2.toIso8601String(),
        'updated_at': entry.$2.toIso8601String(),
      });
      await db.db.insert('local_order_items', {
        'tenant_id': tenantId,
        'order_offline_uuid': entry.$1,
        'product_uuid': 'product-r1',
        'product_sku': 'R-1',
        'product_name': 'Repeat Product',
        'unit': 'pcs',
        'quantity': entry.$3,
        'unit_price': 100,
        'discount_percent': 0,
        'discount_amount': 0,
        'line_total': entry.$3 * 100,
      });
    }

    final api = ApiClient(SecretStore());
    final stock = StockRepository(api: api, db: db);
    final repository = OrderRepository(
      api: api,
      db: db,
      masterData: master,
      stock: stock,
    );

    final rows = await repository.reorderRecommendations(
      tenantId,
      'customer-r1',
      asOf: DateTime.utc(2026, 9, 25),
    );

    expect(rows, hasLength(1));
    expect(rows.single['product_id'], 'product-r1');
    expect(rows.single['purchase_count'], 3);
    expect(rows.single['average_quantity'], 12.0);
    expect(rows.single['suggested_quantity'], 12.0);
    expect(rows.single['stock_enabled'], isFalse);
    expect(rows.single['typical_interval_days'], anyOf(30, 31));

    await db.db.close();
  });

}