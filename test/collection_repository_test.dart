import 'package:field_sales_mobile/core/api/api_client.dart';
import 'package:field_sales_mobile/core/db/app_database.dart';
import 'package:field_sales_mobile/core/storage/secret_store.dart';
import 'package:field_sales_mobile/features/collections/collection_repository.dart';
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

  test(
    'offline collection captures cached balance and deterministic receipt',
    () async {
      final db = AppDatabase();
      await db.open();

      const tenantId = 'tenant-collection-test';
      const customerUuid = 'customer-1';

      await db.db.insert('local_customer_balances', {
        'tenant_id': tenantId,
        'customer_uuid': customerUuid,
        'customer_name': 'Customer One',
        'currency': 'AFN',
        'receivable_total': 500,
        'verified_collections': 0,
        'pending_collections': 0,
        'outstanding_balance': 500,
        'updated_at': '2026-09-19T07:00:00Z',
      });

      final repository = CollectionRepository(
        api: ApiClient(SecretStore()),
        db: db,
      );

      final uuid = await repository.createOffline(
        tenantId: tenantId,
        customer: const {'id': customerUuid, 'name': 'Customer One'},
        collectedAt: DateTime.utc(2026, 9, 19, 7, 30),
        currency: 'afn',
        amount: 200,
        paymentMethod: 'cash',
        latitude: 34.5553,
        longitude: 69.2075,
        accuracy: 8,
        visitUuid: 'visit-1',
        notes: 'Offline cash collection',
      );

      final rows = await db.db.query(
        'local_collections',
        where: 'tenant_id=? AND offline_uuid=?',
        whereArgs: [tenantId, uuid],
      );

      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row['receipt_number'].toString(), startsWith('REC-20260919-'));
      expect(row['currency'], 'AFN');
      expect(row['amount'], 200.0);
      expect(row['balance_before'], 500.0);
      expect(row['overpayment_flag'], 0);
      expect(row['sync_status'], 'pending');

      await db.db.close();
    },
  );

  test('offline collection flags cached overpayment for review', () async {
    final db = AppDatabase();
    await db.open();

    const tenantId = 'tenant-overpayment-test';

    await db.db.insert('local_customer_balances', {
      'tenant_id': tenantId,
      'customer_uuid': 'customer-2',
      'customer_name': 'Customer Two',
      'currency': 'AFN',
      'receivable_total': 100,
      'verified_collections': 0,
      'pending_collections': 0,
      'outstanding_balance': 100,
      'updated_at': '2026-09-19T07:00:00Z',
    });

    final repository = CollectionRepository(
      api: ApiClient(SecretStore()),
      db: db,
    );

    final uuid = await repository.createOffline(
      tenantId: tenantId,
      customer: const {'id': 'customer-2', 'name': 'Customer Two'},
      collectedAt: DateTime.utc(2026, 9, 19, 7, 45),
      currency: 'AFN',
      amount: 150,
      paymentMethod: 'cash',
      latitude: 34.5553,
      longitude: 69.2075,
      accuracy: 8,
    );

    final row = (await db.db.query(
      'local_collections',
      where: 'tenant_id=? AND offline_uuid=?',
      whereArgs: [tenantId, uuid],
    )).single;

    expect(row['overpayment_flag'], 1);
    expect(row['balance_before'], 100.0);

    await db.db.close();
  });
}
