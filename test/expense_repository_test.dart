import 'dart:io';

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

    final repository = ExpenseRepository(api: ApiClient(SecretStore()), db: db);
    final receipt = File(
      p.join(Directory.systemTemp.path, 'fieldpulse-fuel-receipt.jpg'),
    );
    await receipt.writeAsBytes([1, 2, 3, 4]);

    final uuid = await repository.createOffline(
      tenantId: 'tenant-expense-test',
      spentAt: DateTime.utc(2026, 9, 19, 8, 15),
      category: 'fuel',
      currency: 'afn',
      amount: 450.125,
      fuelLiters: 10,
      odometerKm: 1001.5,
      vehicleReference: 'CAR-01',
      fullTank: true,
      receiptLocalPath: receipt.path,
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
    expect(row['fuel_liters'], 10);
    expect(row['fuel_unit_price'], 45.0125);
    expect(row['odometer_km'], 1001.5);
    expect(row['vehicle_reference'], 'CAR-01');
    expect(row['full_tank'], 1);
    expect(row['receipt_local_path'], receipt.path);
    expect(row['receipt_uploaded'], 0);
    expect(row['status'], 'pending');
    expect(row['sync_status'], 'pending');
    expect(row['latitude'], 34.5553);
    expect(row['longitude'], 69.2075);

    await db.db.close();
    if (await receipt.exists()) await receipt.delete();
  });

  test('expense validation rejects invalid amount and category', () async {
    final db = AppDatabase();
    await db.open();

    final repository = ExpenseRepository(api: ApiClient(SecretStore()), db: db);

    await expectLater(
      repository.createOffline(
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

    await expectLater(
      repository.createOffline(
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
