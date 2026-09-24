import 'dart:convert';

import 'package:field_sales_mobile/core/db/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<String> databasePath() async =>
    p.join(await getDatabasesPath(), 'field_sales.db');

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    await deleteDatabase(await databasePath());
  });

  test('database v11 creates tenant-safe operational target and sync-health tables', () async {
    final database = AppDatabase();
    await database.open();

    final tables = (await database.db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    )).map((row) => row['name']).toSet();

    expect(
      tables,
      containsAll([
        'sync_queue',
        'customers',
        'territories',
        'routes',
        'route_customers',
        'products',
        'price_lists',
        'price_list_items',
        'local_work_sessions',
        'local_gps_points',
        'privacy_acknowledgements',
        'local_visits',
        'local_visit_photos',
        'local_call_activities',
        'local_orders',
        'local_order_items',
        'local_collections',
        'local_customer_balances',
        'local_expenses',
        'local_targets',
        'local_sync_failures',
        'local_sync_cycles',
        'local_appointments',
      ]),
    );

    final customerColumns = (await database.db.rawQuery(
      'PRAGMA table_info(customers)',
    )).map((row) => row['name']).toSet();

    expect(
      customerColumns,
      containsAll(['tenant_id', 'uuid', 'source', 'sync_status']),
    );

    final sessionColumns = (await database.db.rawQuery(
      'PRAGMA table_info(local_work_sessions)',
    )).map((row) => row['name']).toSet();
    final gpsColumns = (await database.db.rawQuery(
      'PRAGMA table_info(local_gps_points)',
    )).map((row) => row['name']).toSet();

    expect(sessionColumns, contains('tenant_id'));
    expect(gpsColumns, contains('tenant_id'));

    final collectionColumns = (await database.db.rawQuery(
      'PRAGMA table_info(local_collections)',
    )).map((row) => row['name']).toSet();
    final balanceColumns = (await database.db.rawQuery(
      'PRAGMA table_info(local_customer_balances)',
    )).map((row) => row['name']).toSet();

    expect(
      collectionColumns,
      containsAll(['distance_meters', 'within_geofence']),
    );
    expect(balanceColumns, contains('available_to_collect'));

    final expenseColumns = (await database.db.rawQuery(
      'PRAGMA table_info(local_expenses)',
    )).map((row) => row['name']).toSet();
    final targetColumns = (await database.db.rawQuery(
      'PRAGMA table_info(local_targets)',
    )).map((row) => row['name']).toSet();

    expect(
      expenseColumns,
      containsAll(['tenant_id', 'offline_uuid', 'sync_status', 'review_note']),
    );
    expect(
      targetColumns,
      containsAll([
        'tenant_id',
        'target_uuid',
        'achieved_value',
        'progress_percent',
        'is_current',
      ]),
    );

    final syncFailureColumns = (await database.db.rawQuery(
      'PRAGMA table_info(local_sync_failures)',
    )).map((row) => row['name']).toSet();
    final syncCycleColumns = (await database.db.rawQuery(
      'PRAGMA table_info(local_sync_cycles)',
    )).map((row) => row['name']).toSet();

    expect(
      syncFailureColumns,
      containsAll([
        'tenant_id',
        'entity_type',
        'entity_uuid',
        'attempts',
        'status',
        'next_retry_at',
      ]),
    );
    expect(
      syncCycleColumns,
      containsAll([
        'cycle_uuid',
        'trigger_source',
        'issue_count',
        'waiting_count',
        'blocked_count',
        'stage_summary',
      ]),
    );

    final indexes = (await database.db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='index'",
    )).map((row) => row['name']).toSet();

    expect(
      indexes,
      containsAll([
        'idx_customers_tenant_uuid',
        'idx_products_tenant_uuid',
        'one_active_session',
        'idx_gps_pending',
        'idx_gps_recorded',
        'idx_visits_tenant_uuid',
        'idx_visit_photos_tenant_uuid',
        'idx_calls_tenant_uuid',
        'idx_orders_tenant_uuid',
        'idx_order_items_product',
        'idx_collections_tenant_uuid',
        'idx_customer_balances_unique',
        'idx_expenses_tenant_uuid',
        'idx_targets_tenant_uuid',
        'idx_sync_failures_status',
        'idx_sync_cycles_recent',
        'idx_appointments_tenant_uuid',
        'idx_appointments_calendar',
        'idx_appointments_sync',
      ]),
    );

    await database.db.close();
  });

  test(
    'v4 master cache upgrades safely without losing attendance schema',
    () async {
      final path = await databasePath();

      final old = await openDatabase(
        path,
        version: 4,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE sync_queue ('
            'id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'entity_type TEXT NOT NULL, '
            'entity_uuid TEXT NOT NULL, '
            'action TEXT NOT NULL, '
            'payload TEXT NOT NULL, '
            'priority INTEGER NOT NULL DEFAULT 100, '
            'attempts INTEGER NOT NULL DEFAULT 0, '
            'max_attempts INTEGER NOT NULL DEFAULT 10, '
            'status TEXT NOT NULL DEFAULT "pending", '
            'error_message TEXT, '
            'next_retry_at TEXT, '
            'server_id INTEGER, '
            'server_uuid TEXT, '
            'created_at TEXT NOT NULL, '
            'updated_at TEXT NOT NULL'
            ')',
          );
          await db.execute(
            'CREATE TABLE customers ('
            'id INTEGER PRIMARY KEY, '
            'uuid TEXT, '
            'payload TEXT NOT NULL, '
            'cached_at TEXT NOT NULL'
            ')',
          );
          await db.insert('customers', {
            'id': 1,
            'uuid': 'legacy',
            'payload': jsonEncode({'id': 'legacy', 'name': 'Legacy'}),
            'cached_at': '2026-01-01T00:00:00Z',
          });
        },
      );
      await old.close();

      final database = AppDatabase();
      await database.open();

      final customerColumns = (await database.db.rawQuery(
        'PRAGMA table_info(customers)',
      )).map((row) => row['name']).toSet();
      final queueColumns = (await database.db.rawQuery(
        'PRAGMA table_info(sync_queue)',
      )).map((row) => row['name']).toSet();

      expect(
        customerColumns,
        containsAll(['tenant_id', 'source', 'sync_status']),
      );
      expect(queueColumns, contains('tenant_id'));
      expect(
        await database.db.query(
          'customers',
          where: 'uuid = ?',
          whereArgs: ['legacy'],
        ),
        isEmpty,
      );

      final attendanceTables = (await database.db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      )).map((row) => row['name']).toSet();

      expect(attendanceTables, contains('local_work_sessions'));
      expect(attendanceTables, contains('local_gps_points'));

      await database.db.close();
    },
  );
  test(
    'v5 attendance and GPS rows are quarantined during v6 upgrade',
    () async {
      final path = await databasePath();

      final old = await openDatabase(
        path,
        version: 5,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE local_work_sessions ('
            'id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'offline_uuid TEXT NOT NULL UNIQUE, '
            'server_id INTEGER, '
            'date TEXT NOT NULL, '
            'start_time TEXT NOT NULL, '
            'end_time TEXT, '
            'start_latitude REAL NOT NULL, '
            'start_longitude REAL NOT NULL, '
            'start_accuracy REAL NOT NULL, '
            'end_latitude REAL, '
            'end_longitude REAL, '
            'end_accuracy REAL, '
            'status TEXT NOT NULL, '
            'sync_status TEXT NOT NULL, '
            'start_source TEXT NOT NULL DEFAULT "manual", '
            'privacy_ack_at TEXT, '
            'created_at TEXT NOT NULL, '
            'updated_at TEXT NOT NULL'
            ')',
          );
          await db.execute(
            'CREATE UNIQUE INDEX one_active_session '
            "ON local_work_sessions(status) WHERE status='active'",
          );
          await db.execute(
            'CREATE TABLE local_gps_points ('
            'id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'client_uuid TEXT NOT NULL UNIQUE, '
            'latitude REAL NOT NULL, '
            'longitude REAL NOT NULL, '
            'altitude REAL, '
            'accuracy REAL NOT NULL, '
            'speed REAL, '
            'heading REAL, '
            'battery_level INTEGER, '
            'is_charging INTEGER NOT NULL DEFAULT 0, '
            'network_status TEXT, '
            'is_mock_location INTEGER NOT NULL DEFAULT 0, '
            'provider TEXT, '
            'recorded_at TEXT NOT NULL, '
            'sequence_number INTEGER NOT NULL, '
            'batch_uuid TEXT, '
            'sync_status TEXT NOT NULL DEFAULT "pending", '
            'last_error TEXT, '
            'uploaded_at TEXT, '
            'created_at TEXT NOT NULL'
            ')',
          );
          await db.execute(
            'CREATE INDEX idx_gps_pending ON local_gps_points(sync_status,id)',
          );
          await db.execute(
            'CREATE INDEX idx_gps_recorded ON local_gps_points(recorded_at)',
          );

          await db.insert('local_work_sessions', {
            'offline_uuid': 'legacy-session',
            'date': '2026-09-18',
            'start_time': '2026-09-18T04:00:00Z',
            'start_latitude': 34.5,
            'start_longitude': 69.1,
            'start_accuracy': 8,
            'status': 'active',
            'sync_status': 'pending',
            'created_at': '2026-09-18T04:00:00Z',
            'updated_at': '2026-09-18T04:00:00Z',
          });
          await db.insert('local_gps_points', {
            'client_uuid': 'legacy-point',
            'latitude': 34.5,
            'longitude': 69.1,
            'accuracy': 8,
            'recorded_at': '2026-09-18T04:01:00Z',
            'sequence_number': 1,
            'sync_status': 'pending',
            'created_at': '2026-09-18T04:01:00Z',
          });
        },
      );
      await old.close();

      final database = AppDatabase();
      await database.open();

      final session = (await database.db.query(
        'local_work_sessions',
        where: 'offline_uuid=?',
        whereArgs: ['legacy-session'],
      )).single;
      final point = (await database.db.query(
        'local_gps_points',
        where: 'client_uuid=?',
        whereArgs: ['legacy-point'],
      )).single;

      expect(session['tenant_id'], '');
      expect(point['tenant_id'], '');

      final activeIndex =
          (await database.db.query(
                'sqlite_master',
                columns: ['sql'],
                where: 'type=? AND name=?',
                whereArgs: ['index', 'one_active_session'],
              )).single['sql']
              as String;
      final pendingIndex =
          (await database.db.query(
                'sqlite_master',
                columns: ['sql'],
                where: 'type=? AND name=?',
                whereArgs: ['index', 'idx_gps_pending'],
              )).single['sql']
              as String;

      expect(activeIndex, contains('tenant_id'));
      expect(pendingIndex, contains('tenant_id'));

      await database.db.close();
    },
  );
}
