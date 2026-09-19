import 'package:field_sales_mobile/core/api/api_client.dart';
import 'package:field_sales_mobile/core/db/app_database.dart';
import 'package:field_sales_mobile/core/storage/secret_store.dart';
import 'package:field_sales_mobile/features/master_data/master_data_repository.dart';
import 'package:field_sales_mobile/features/master_data/master_data_source.dart';
import 'package:field_sales_mobile/features/orders/order_repository.dart';
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

      final repository = OrderRepository(
        api: ApiClient(SecretStore()),
        db: db,
        masterData: master,
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
}
