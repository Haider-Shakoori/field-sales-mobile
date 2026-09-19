import 'package:field_sales_mobile/core/db/app_database.dart';
import 'package:field_sales_mobile/core/sync/local_dependency_guard.dart';
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

  test('dependency guard defers unsynced customer visit and attendance', () async {
    final db = AppDatabase();
    await db.open();
    const tenantId = 'tenant-dependency';
    final now = DateTime.utc(2026, 9, 19, 8).toIso8601String();

    await db.db.insert('customers', {
      'tenant_id': tenantId,
      'uuid': 'customer-1',
      'payload': '{"id":"customer-1","name":"Customer One"}',
      'cached_at': now,
      'source': 'local',
      'sync_status': 'pending',
    });

    await db.db.insert('local_visits', {
      'tenant_id': tenantId,
      'offline_uuid': 'visit-1',
      'customer_uuid': 'customer-1',
      'customer_name': 'Customer One',
      'status': 'active',
      'checked_in_at': now,
      'checkin_latitude': 34.5,
      'checkin_longitude': 69.2,
      'checkin_accuracy': 8,
      'sync_status': 'pending_checkin',
      'created_at': now,
      'updated_at': now,
    });

    await db.db.insert('sync_queue', {
      'tenant_id': tenantId,
      'entity_type': 'attendance',
      'entity_uuid': 'session-1',
      'action': 'start',
      'payload': '{}',
      'priority': 10,
      'status': 'pending',
      'attempts': 0,
      'max_attempts': 10,
      'created_at': now,
      'updated_at': now,
    });

    final guard = LocalDependencyGuard(db);

    expect(await guard.customerReady(tenantId, 'customer-1'), isFalse);
    expect(await guard.visitReady(tenantId, 'visit-1'), isFalse);
    expect(await guard.hasPendingAttendance(tenantId), isTrue);

    await db.db.update(
      'customers',
      {'sync_status': 'synced', 'source': 'server'},
      where: 'tenant_id=? AND uuid=?',
      whereArgs: [tenantId, 'customer-1'],
    );
    await db.db.update(
      'local_visits',
      {'server_uuid': 'visit-server-1', 'sync_status': 'synced'},
      where: 'tenant_id=? AND offline_uuid=?',
      whereArgs: [tenantId, 'visit-1'],
    );
    await db.db.update(
      'sync_queue',
      {'status': 'done'},
      where: 'tenant_id=? AND entity_type=?',
      whereArgs: [tenantId, 'attendance'],
    );

    expect(await guard.customerReady(tenantId, 'customer-1'), isTrue);
    expect(await guard.visitReady(tenantId, 'visit-1'), isTrue);
    expect(await guard.hasPendingAttendance(tenantId), isFalse);

    await db.db.close();
  });
}
