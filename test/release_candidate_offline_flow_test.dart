import 'package:field_sales_mobile/core/api/api_client.dart';
import 'package:field_sales_mobile/core/db/app_database.dart';
import 'package:field_sales_mobile/core/storage/secret_store.dart';
import 'package:field_sales_mobile/core/sync/local_dependency_guard.dart';
import 'package:field_sales_mobile/features/attendance/attendance_repository.dart';
import 'package:field_sales_mobile/features/collections/collection_repository.dart';
import 'package:field_sales_mobile/features/expenses/expense_repository.dart';
import 'package:field_sales_mobile/features/master_data/master_data_repository.dart';
import 'package:field_sales_mobile/features/master_data/master_data_source.dart';
import 'package:field_sales_mobile/features/orders/order_repository.dart';
import 'package:field_sales_mobile/features/stock/stock_repository.dart';
import 'package:field_sales_mobile/features/visits/visit_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _OfflineSource implements MasterDataSource {
  @override
  Future<MasterPage> fetchPage(
    String path, {
    int page = 1,
    int perPage = 100,
    String? updatedSince,
  }) {
    throw StateError('RC offline golden path must not use the network.');
  }

  @override
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> payload) {
    throw StateError('RC offline golden path must not use the network.');
  }

  @override
  Future<Map<String, dynamic>> patch(String path, Map<String, dynamic> payload) {
    throw StateError('RC offline golden path must not use the network.');
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

  test('RC offline workday survives restart with retry-safe pending state', () async {
    const tenantId = 'rc-tenant';
    const customerUuid = 'rc-customer';
    const visitStart = '2026-09-19T05:00:00.000Z';

    final db = AppDatabase();
    await db.open();

    final api = ApiClient(SecretStore());
    final master = MasterDataRepository(database: db, source: _OfflineSource());
    final attendance = AttendanceRepository(api: api, db: db);
    final visits = VisitRepository(api: api, db: db);
    final stock = StockRepository(api: api, db: db);
    final orders = OrderRepository(
      api: api,
      db: db,
      masterData: master,
      stock: stock,
    );
    final collections = CollectionRepository(api: api, db: db);
    final expenses = ExpenseRepository(api: api, db: db);

    await master.cacheServerRow(
      table: 'products',
      tenantId: tenantId,
      row: {
        'id': 'rc-product',
        'sku': 'RC-SKU-001',
        'name': 'RC Product',
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
        'id': 'rc-price-list',
        'code': 'RC-RETAIL',
        'name': 'RC Retail',
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
        'id': 'rc-tier-10',
        'price_list_id': 'rc-price-list',
        'product_id': 'rc-product',
        'min_quantity': 10,
        'price': 80,
      },
    );

    await db.db.insert('customers', {
      'tenant_id': tenantId,
      'uuid': customerUuid,
      'payload':
          '{"id":"$customerUuid","name":"RC Customer","price_list_id":"rc-price-list"}',
      'source': 'server',
      'sync_status': 'synced',
      'cached_at': DateTime.now().toUtc().toIso8601String(),
    });

    await db.db.insert('local_customer_balances', {
      'tenant_id': tenantId,
      'customer_uuid': customerUuid,
      'customer_name': 'RC Customer',
      'currency': 'AFN',
      'receivable_total': 760,
      'verified_collections': 0,
      'pending_collections': 0,
      'outstanding_balance': 760,
      'available_to_collect': 760,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });

    final attendanceUuid = await attendance.start(
      tenantId: tenantId,
      date: '2026-09-19',
      at: DateTime.utc(2026, 9, 19, 4, 30),
      lat: 34.5,
      lng: 69.2,
      accuracy: 8,
      source: 'manual',
    );

    await db.db.insert('local_gps_points', {
      'tenant_id': tenantId,
      'client_uuid': 'rc-gps-1',
      'latitude': 34.50001,
      'longitude': 69.20001,
      'accuracy': 7,
      'battery_level': 80,
      'is_charging': 0,
      'network_status': 'offline',
      'is_mock_location': 0,
      'provider': 'fused',
      'recorded_at': '2026-09-19T04:35:00.000Z',
      'sequence_number': 1,
      'sync_status': 'pending',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });

    final customer = {
      'id': customerUuid,
      'name': 'RC Customer',
      'price_list_id': 'rc-price-list',
    };

    final visitUuid = await visits.checkInLocal(
      tenantId: tenantId,
      customer: customer,
      at: DateTime.parse(visitStart),
      latitude: 34.50001,
      longitude: 69.20001,
      accuracy: 7,
    );

    final visit = (await visits.list(tenantId)).single;

    await visits.checkOutLocal(
      tenantId: tenantId,
      visit: visit,
      at: DateTime.utc(2026, 9, 19, 5, 10),
      latitude: 34.50002,
      longitude: 69.20002,
      accuracy: 7,
      outcome: 'order_placed',
      notes: 'RC offline golden path.',
    );

    final orderUuid = await orders.createOffline(
      tenantId: tenantId,
      customer: customer,
      orderedAt: DateTime.utc(2026, 9, 19, 5, 12),
      paymentType: 'credit',
      visitUuid: visitUuid,
      lines: [
        OrderDraftLine(
          product: const {
            'id': 'rc-product',
            'sku': 'RC-SKU-001',
            'name': 'RC Product',
            'unit': 'pcs',
            'base_price': 100,
            'currency': 'AFN',
          },
          quantity: 10,
          discountPercent: 5,
        ),
      ],
    );

    final collectionUuid = await collections.createOffline(
      tenantId: tenantId,
      customer: customer,
      collectedAt: DateTime.utc(2026, 9, 19, 5, 20),
      currency: 'AFN',
      amount: 200,
      paymentMethod: 'cash',
      latitude: 34.50002,
      longitude: 69.20002,
      accuracy: 7,
      visitUuid: visitUuid,
      notes: 'RC offline collection.',
    );

    final expenseUuid = await expenses.createOffline(
      tenantId: tenantId,
      spentAt: DateTime.utc(2026, 9, 19, 5, 30),
      category: 'fuel',
      currency: 'AFN',
      amount: 100,
      latitude: 34.50002,
      longitude: 69.20002,
      accuracy: 7,
      merchant: 'RC Fuel Station',
      referenceNumber: 'RC-FUEL-001',
    );

    final activeSession = await attendance.active(tenantId);
    expect(activeSession, isNotNull);

    await attendance.end(
      session: activeSession!,
      at: DateTime.utc(2026, 9, 19, 6),
      lat: 34.50003,
      lng: 69.20003,
      accuracy: 7,
    );

    await db.db.close();

    final reopened = AppDatabase();
    await reopened.open();

    final sessionRows = await reopened.db.query(
      'local_work_sessions',
      where: 'tenant_id=? AND offline_uuid=?',
      whereArgs: [tenantId, attendanceUuid],
    );
    final queueRows = await reopened.db.query(
      'sync_queue',
      where: 'tenant_id=? AND entity_uuid=?',
      whereArgs: [tenantId, attendanceUuid],
      orderBy: 'priority ASC',
    );
    final gpsRows = await reopened.db.query(
      'local_gps_points',
      where: 'tenant_id=? AND client_uuid=?',
      whereArgs: [tenantId, 'rc-gps-1'],
    );
    final visitRows = await reopened.db.query(
      'local_visits',
      where: 'tenant_id=? AND offline_uuid=?',
      whereArgs: [tenantId, visitUuid],
    );
    final orderRows = await reopened.db.query(
      'local_orders',
      where: 'tenant_id=? AND offline_uuid=?',
      whereArgs: [tenantId, orderUuid],
    );
    final collectionRows = await reopened.db.query(
      'local_collections',
      where: 'tenant_id=? AND offline_uuid=?',
      whereArgs: [tenantId, collectionUuid],
    );
    final expenseRows = await reopened.db.query(
      'local_expenses',
      where: 'tenant_id=? AND offline_uuid=?',
      whereArgs: [tenantId, expenseUuid],
    );

    expect(sessionRows, hasLength(1));
    expect(sessionRows.single['status'], 'completed');
    expect(sessionRows.single['sync_status'], 'pending');

    expect(queueRows, hasLength(2));
    expect(queueRows.map((row) => row['action']).toList(), ['start', 'end']);
    expect(queueRows.map((row) => row['priority']).toList(), [10, 20]);
    expect(queueRows.every((row) => row['status'] == 'pending'), isTrue);

    expect(gpsRows.single['sync_status'], 'pending');
    expect(visitRows.single['sync_status'], 'pending_checkout');
    expect(orderRows.single['sync_status'], 'pending');
    expect(orderRows.single['grand_total'], 760.0);
    expect(collectionRows.single['sync_status'], 'pending');
    expect(collectionRows.single['balance_before'], 760.0);
    expect(expenseRows.single['sync_status'], 'pending');

    expect(
      await LocalDependencyGuard(reopened).hasPendingAttendance(tenantId),
      isTrue,
    );

    await reopened.db.close();
  });
}
