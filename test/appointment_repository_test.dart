import 'package:field_sales_mobile/core/api/api_client.dart';
import 'package:field_sales_mobile/core/db/app_database.dart';
import 'package:field_sales_mobile/core/storage/secret_store.dart';
import 'package:field_sales_mobile/features/appointments/appointment_repository.dart';
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

  test('offline appointment persists and stays pending until sync', () async {
    final db = AppDatabase();
    await db.open();

    final repository = AppointmentRepository(
      api: ApiClient(SecretStore()),
      db: db,
    );

    final uuid = await repository.createLocal(
      tenantId: 'tenant-calendar-test',
      customer: const {
        'id': 'customer-uuid-1',
        'name': 'Calendar Customer',
      },
      title: 'Payment review',
      type: 'meeting',
      startsAt: DateTime.utc(2026, 9, 26, 5, 30),
      endsAt: DateTime.utc(2026, 9, 26, 6, 0),
      reminderMinutesBefore: 30,
      location: 'Customer office',
      notes: 'Review receivable before next order.',
    );

    final rows = await db.db.query(
      'local_appointments',
      where: 'tenant_id=? AND offline_uuid=?',
      whereArgs: ['tenant-calendar-test', uuid],
    );

    expect(rows, hasLength(1));
    expect(rows.single['customer_uuid'], 'customer-uuid-1');
    expect(rows.single['title'], 'Payment review');
    expect(rows.single['status'], 'scheduled');
    expect(rows.single['sync_status'], 'pending_create');
    expect(rows.single['reminder_minutes_before'], 30);
    expect(await repository.pendingCount('tenant-calendar-test'), 1);

    await repository.updateStatusLocal(
      tenantId: 'tenant-calendar-test',
      offlineUuid: uuid,
      status: 'completed',
    );

    final updated = (await db.db.query(
      'local_appointments',
      where: 'tenant_id=? AND offline_uuid=?',
      whereArgs: ['tenant-calendar-test', uuid],
    )).single;

    expect(updated['status'], 'completed');
    expect(updated['sync_status'], 'pending_create');
    expect(updated['completed_at'], isNotNull);

    await db.db.close();
  });

  test('appointment cache is tenant scoped and chronologically ordered', () async {
    final db = AppDatabase();
    await db.open();

    final repository = AppointmentRepository(
      api: ApiClient(SecretStore()),
      db: db,
    );

    await repository.createLocal(
      tenantId: 'tenant-a',
      title: 'Later meeting',
      type: 'meeting',
      startsAt: DateTime.utc(2026, 9, 28, 9),
    );
    await repository.createLocal(
      tenantId: 'tenant-a',
      title: 'Earlier visit',
      type: 'visit',
      startsAt: DateTime.utc(2026, 9, 27, 9),
    );
    await repository.createLocal(
      tenantId: 'tenant-b',
      title: 'Other tenant',
      type: 'meeting',
      startsAt: DateTime.utc(2026, 9, 26, 9),
    );

    final rows = await repository.list('tenant-a');

    expect(rows, hasLength(2));
    expect(rows.first['title'], 'Earlier visit');
    expect(rows.last['title'], 'Later meeting');

    await db.db.close();
  });
}
