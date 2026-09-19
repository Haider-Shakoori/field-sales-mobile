import 'package:field_sales_mobile/core/api/api_client.dart';
import 'package:field_sales_mobile/core/db/app_database.dart';
import 'package:field_sales_mobile/core/storage/secret_store.dart';
import 'package:field_sales_mobile/features/expenses/expense_repository.dart';
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

  test('offline expense persists deterministic local claim metadata', () async {
    final db = AppDatabase();
    await db.open();

    final repository = ExpenseRepository(
      api: ApiClient(SecretStore()),
      db: db,
    );

    final uuid = await repository.createOffline(
      tenantId: 'tenant-expense-test',
      spentAt: DateTime.utc(2026, 9, 19, 8, 15),
      category: 'fuel',
      currency: 'afn',
      amount: 450.125,
      merchant: 'Fuel Station',
      referenceNumber: 'FUEL-001',
      latitude: 34.5553,
      longitude: 69.2075,
      accuracy: 8,
      notes: 'Field route fuel',
    );

    final rows = await db.db.query(
      'local_expenses',
      where: 'tenant_id=? AND offline_uuid=?',
      whereArgs: ['tenant-expense-test', uuid],
    );

    expect(rows, hasLength(1));
    final row = rows.single;
    expect(row['expense_number'].toString(), startsWith('EXP-20260919-'));
    expect(row['currency'], 'AFN');
    expect(row['amount'], 450.125);
    expect(row['category'], 'fuel');
    expect(row['status'], 'pending');
    expect(row['sync_status'], 'pending');
    expect(row['latitude'], 34.5553);
    expect(row['longitude'], 69.2075);

    await db.db.close();
  });

  test('expense validation rejects invalid amount and category', () async {
    final db = AppDatabase();
    await db.open();

    final repository = ExpenseRepository(
      api: ApiClient(SecretStore()),
      db: db,
    );

    expect(
      () => repository.createOffline(
        tenantId: 'tenant-expense-test',
        spentAt: DateTime.utc(2026, 9, 19, 8, 15),
        category: 'invalid',
        currency: 'AFN',
        amount: 10,
        latitude: 34.5553,
        longitude: 69.2075,
        accuracy: 8,
      ),
      throwsA(isA<StateError>()),
    );

    expect(
      () => repository.createOffline(
        tenantId: 'tenant-expense-test',
        spentAt: DateTime.utc(2026, 9, 19, 8, 15),
        category: 'fuel',
        currency: 'AFN',
        amount: 0,
        latitude: 34.5553,
        longitude: 69.2075,
        accuracy: 8,
      ),
      throwsA(isA<StateError>()),
    );

    await db.db.close();
  });
}
