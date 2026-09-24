import 'package:field_sales_mobile/core/api/api_client.dart';
import 'package:field_sales_mobile/core/db/app_database.dart';
import 'package:field_sales_mobile/core/storage/secret_store.dart';
import 'package:field_sales_mobile/features/mileage/mileage_repository.dart';
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

  test('offline mileage uses odometer for efficiency and GPS for variance', () async {
    final db = AppDatabase();
    await db.open();

    const tenantId = 'mileage-tenant';
    final now = DateTime.utc(2026, 9, 25, 8);

    await db.db.insert('local_work_sessions', {
      'tenant_id': tenantId,
      'offline_uuid': 'session-1',
      'date': '2026-09-25',
      'start_time': now.toIso8601String(),
      'end_time': now.add(const Duration(hours: 1)).toIso8601String(),
      'start_latitude': 34.55,
      'start_longitude': 69.20,
      'start_accuracy': 5,
      'end_latitude': 34.56,
      'end_longitude': 69.20,
      'end_accuracy': 5,
      'status': 'completed',
      'sync_status': 'synced',
      'start_source': 'manual',
      'vehicle_reference': 'CAR-01',
      'odometer_start_km': 1000,
      'odometer_end_km': 1002,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });

    final points = [
      ['gps-1', 34.55, 69.20, now.add(const Duration(minutes: 5))],
      ['gps-2', 34.56, 69.20, now.add(const Duration(minutes: 15))],
    ];

    for (final point in points) {
      await db.db.insert('local_gps_points', {
        'tenant_id': tenantId,
        'client_uuid': point[0],
        'latitude': point[1],
        'longitude': point[2],
        'accuracy': 5,
        'is_mock_location': 0,
        'recorded_at': (point[3] as DateTime).toIso8601String(),
        'sequence_number': 1,
        'sync_status': 'synced',
        'created_at': now.toIso8601String(),
      });
    }

    await db.db.insert('local_expenses', {
      'tenant_id': tenantId,
      'offline_uuid': 'fuel-1',
      'expense_number': 'EXP-FUEL-1',
      'spent_at': now.add(const Duration(minutes: 20)).toIso8601String(),
      'category': 'fuel',
      'currency': 'AFN',
      'amount': 450,
      'fuel_liters': 10,
      'fuel_unit_price': 45,
      'odometer_km': 1001.5,
      'latitude': 34.555,
      'longitude': 69.20,
      'accuracy': 5,
      'status': 'approved',
      'sync_status': 'synced',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });

    final repository = MileageRepository(
      api: ApiClient(SecretStore()),
      db: db,
    );
    final rows = await repository.localHistory(tenantId);

    expect(rows, hasLength(1));
    final row = rows.single;
    expect(row['vehicle_reference'], 'CAR-01');
    expect(row['odometer_distance_km'], 2);
    expect(row['effective_distance_km'], 2);
    expect(row['fuel_liters'], 10);
    expect(row['km_per_liter'], 0.2);
    expect((row['gps_distance_km'] as double), greaterThan(1));
    expect((row['fuel_cost_by_currency'] as Map)['AFN'], 450);

    await db.db.close();
  });

  test('offline mileage ignores mock and low accuracy GPS points', () async {
    final db = AppDatabase();
    await db.open();

    const tenantId = 'mileage-filter-tenant';
    final start = DateTime.utc(2026, 9, 25, 8);

    await db.db.insert('local_work_sessions', {
      'tenant_id': tenantId,
      'offline_uuid': 'session-filter',
      'date': '2026-09-25',
      'start_time': start.toIso8601String(),
      'end_time': start.add(const Duration(hours: 1)).toIso8601String(),
      'start_latitude': 34.55,
      'start_longitude': 69.20,
      'start_accuracy': 5,
      'status': 'completed',
      'sync_status': 'synced',
      'start_source': 'manual',
      'created_at': start.toIso8601String(),
      'updated_at': start.toIso8601String(),
    });

    await db.db.insert('local_gps_points', {
      'tenant_id': tenantId,
      'client_uuid': 'good-1',
      'latitude': 34.55,
      'longitude': 69.20,
      'accuracy': 5,
      'is_mock_location': 0,
      'recorded_at': start.add(const Duration(minutes: 5)).toIso8601String(),
      'sequence_number': 1,
      'sync_status': 'synced',
      'created_at': start.toIso8601String(),
    });
    await db.db.insert('local_gps_points', {
      'tenant_id': tenantId,
      'client_uuid': 'mock',
      'latitude': 35.55,
      'longitude': 70.20,
      'accuracy': 5,
      'is_mock_location': 1,
      'recorded_at': start.add(const Duration(minutes: 10)).toIso8601String(),
      'sequence_number': 2,
      'sync_status': 'synced',
      'created_at': start.toIso8601String(),
    });
    await db.db.insert('local_gps_points', {
      'tenant_id': tenantId,
      'client_uuid': 'bad-accuracy',
      'latitude': 35.55,
      'longitude': 70.20,
      'accuracy': 80,
      'is_mock_location': 0,
      'recorded_at': start.add(const Duration(minutes: 15)).toIso8601String(),
      'sequence_number': 3,
      'sync_status': 'synced',
      'created_at': start.toIso8601String(),
    });

    final repository = MileageRepository(
      api: ApiClient(SecretStore()),
      db: db,
    );
    final rows = await repository.localHistory(tenantId);

    expect(rows.single['gps_distance_km'], 0);

    await db.db.close();
  });
}
