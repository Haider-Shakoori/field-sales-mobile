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

  test('database v5 creates tenant-safe master and attendance tables', () async {
    final database = AppDatabase();
    await database.open();

    final tables = (await database.db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    ))
        .map((row) => row['name'])
        .toSet();

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
      ]),
    );

    final customerColumns = (await database.db.rawQuery(
      'PRAGMA table_info(customers)',
    ))
        .map((row) => row['name'])
        .toSet();

    expect(
      customerColumns,
      containsAll(['tenant_id', 'uuid', 'source', 'sync_status']),
    );

    final indexes = (await database.db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='index'",
    ))
        .map((row) => row['name'])
        .toSet();

    expect(
      indexes,
      containsAll([
        'idx_customers_tenant_uuid',
        'idx_products_tenant_uuid',
        'one_active_session',
        'idx_gps_pending',
        'idx_gps_recorded',
      ]),
    );

    await database.db.close();
  });

  test('v4 master cache upgrades safely without losing attendance schema',
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
    ))
        .map((row) => row['name'])
        .toSet();
    final queueColumns = (await database.db.rawQuery(
      'PRAGMA table_info(sync_queue)',
    ))
        .map((row) => row['name'])
        .toSet();

    expect(customerColumns, containsAll(['tenant_id', 'source', 'sync_status']));
    expect(queueColumns, contains('tenant_id'));
    expect(
      await database.db.query('customers', where: 'uuid = ?', whereArgs: ['legacy']),
      isEmpty,
    );

    final attendanceTables = (await database.db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    ))
        .map((row) => row['name'])
        .toSet();

    expect(attendanceTables, contains('local_work_sessions'));
    expect(attendanceTables, contains('local_gps_points'));

    await database.db.close();
  });
}
