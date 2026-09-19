import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  static const version = 9;

  Database? _db;

  Database get db => _db!;

  Future<void> open() async {
    final dir = await getDatabasesPath();

    _db = await openDatabase(
      p.join(dir, 'field_sales.db'),
      version: version,
      onCreate: (database, _) => _createV9(database),
      onUpgrade: _upgrade,
    );
  }

  Future<void> _createV9(Database database) async {
    await _createSyncTables(database);
    await _createMasterTables(database);
    await _createAttendanceTables(database);
    await _createVisitTables(database);
    await _createOrderTables(database);
    await _createCollectionTables(database);
  }

  Future<void> _createSyncTables(Database database) async {
    await database.execute(
      'CREATE TABLE IF NOT EXISTS sync_queue ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'tenant_id TEXT NOT NULL DEFAULT "", '
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
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_status_priority '
      'ON sync_queue(tenant_id,status,priority,created_at)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_entity '
      'ON sync_queue(tenant_id,entity_type,entity_uuid)',
    );
    await database.execute(
      'CREATE TABLE IF NOT EXISTS local_settings ('
      'key TEXT PRIMARY KEY, '
      'value TEXT NOT NULL'
      ')',
    );
    await database.execute(
      'CREATE TABLE IF NOT EXISTS local_sync_log ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'level TEXT, '
      'message TEXT, '
      'created_at TEXT NOT NULL'
      ')',
    );
    await database.execute(
      'CREATE TABLE IF NOT EXISTS session_meta ('
      'key TEXT PRIMARY KEY, '
      'value TEXT NOT NULL'
      ')',
    );
  }

  Future<void> _createMasterTables(Database database) async {
    for (final name in masterTables) {
      await database.execute(
        'CREATE TABLE IF NOT EXISTS $name ('
        'id INTEGER PRIMARY KEY AUTOINCREMENT, '
        'tenant_id TEXT NOT NULL, '
        'uuid TEXT NOT NULL, '
        'payload TEXT NOT NULL, '
        'cached_at TEXT NOT NULL, '
        'source TEXT NOT NULL DEFAULT "server", '
        'sync_status TEXT NOT NULL DEFAULT "synced"'
        ')',
      );
      await database.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_${name}_tenant_uuid '
        'ON $name(tenant_id,uuid)',
      );
      await database.execute(
        'CREATE INDEX IF NOT EXISTS idx_${name}_tenant_cached '
        'ON $name(tenant_id,cached_at)',
      );
    }
  }

  Future<void> _createAttendanceTables(Database database) async {
    await database.execute(
      'CREATE TABLE IF NOT EXISTS local_work_sessions ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'tenant_id TEXT NOT NULL, '
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
    await database.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS one_active_session '
      "ON local_work_sessions(tenant_id,status) WHERE status='active'",
    );
    await database.execute(
      'CREATE TABLE IF NOT EXISTS local_gps_points ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'tenant_id TEXT NOT NULL, '
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
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_gps_pending '
      'ON local_gps_points(tenant_id,sync_status,id)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_gps_recorded '
      'ON local_gps_points(tenant_id,recorded_at)',
    );
    await database.execute(
      'CREATE TABLE IF NOT EXISTS privacy_acknowledgements ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'policy_version TEXT NOT NULL, '
      'acknowledged_at TEXT NOT NULL, '
      'user_id TEXT, '
      'tenant_id TEXT, '
      'device_id TEXT, '
      'app_version TEXT NOT NULL, '
      'sync_status TEXT NOT NULL DEFAULT "pending", '
      'server_id INTEGER, '
      'server_uuid TEXT, '
      'UNIQUE(policy_version,user_id,tenant_id,device_id)'
      ')',
    );
  }

  Future<void> _createVisitTables(Database database) async {
    await database.execute(
      'CREATE TABLE IF NOT EXISTS local_visits ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'tenant_id TEXT NOT NULL, '
      'offline_uuid TEXT NOT NULL, '
      'server_uuid TEXT, '
      'customer_uuid TEXT NOT NULL, '
      'customer_name TEXT NOT NULL, '
      'route_uuid TEXT, '
      'is_planned INTEGER, '
      'status TEXT NOT NULL DEFAULT "active", '
      'outcome TEXT, '
      'notes TEXT, '
      'checked_in_at TEXT NOT NULL, '
      'checked_out_at TEXT, '
      'checkin_latitude REAL NOT NULL, '
      'checkin_longitude REAL NOT NULL, '
      'checkin_accuracy REAL NOT NULL, '
      'checkout_latitude REAL, '
      'checkout_longitude REAL, '
      'checkout_accuracy REAL, '
      'checkin_distance_meters REAL, '
      'checkout_distance_meters REAL, '
      'checkin_within_geofence INTEGER, '
      'checkout_within_geofence INTEGER, '
      'duration_seconds INTEGER, '
      'sync_status TEXT NOT NULL DEFAULT "pending_checkin", '
      'last_error TEXT, '
      'created_at TEXT NOT NULL, '
      'updated_at TEXT NOT NULL'
      ')',
    );
    await database.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_visits_tenant_uuid '
      'ON local_visits(tenant_id,offline_uuid)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_visits_tenant_status '
      'ON local_visits(tenant_id,status,checked_in_at)',
    );

    await database.execute(
      'CREATE TABLE IF NOT EXISTS local_visit_photos ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'tenant_id TEXT NOT NULL, '
      'client_uuid TEXT NOT NULL, '
      'visit_offline_uuid TEXT NOT NULL, '
      'server_uuid TEXT, '
      'local_path TEXT NOT NULL, '
      'captured_at TEXT NOT NULL, '
      'latitude REAL, '
      'longitude REAL, '
      'accuracy REAL, '
      'sync_status TEXT NOT NULL DEFAULT "pending", '
      'last_error TEXT, '
      'created_at TEXT NOT NULL'
      ')',
    );
    await database.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_visit_photos_tenant_uuid '
      'ON local_visit_photos(tenant_id,client_uuid)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_visit_photos_visit '
      'ON local_visit_photos(tenant_id,visit_offline_uuid,sync_status)',
    );

    await database.execute(
      'CREATE TABLE IF NOT EXISTS local_call_activities ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'tenant_id TEXT NOT NULL, '
      'offline_uuid TEXT NOT NULL, '
      'server_uuid TEXT, '
      'customer_uuid TEXT NOT NULL, '
      'customer_name TEXT NOT NULL, '
      'phone_number TEXT NOT NULL, '
      'called_at TEXT NOT NULL, '
      'outcome TEXT, '
      'notes TEXT, '
      'sync_status TEXT NOT NULL DEFAULT "pending", '
      'last_error TEXT, '
      'created_at TEXT NOT NULL, '
      'updated_at TEXT NOT NULL'
      ')',
    );
    await database.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_calls_tenant_uuid '
      'ON local_call_activities(tenant_id,offline_uuid)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_calls_customer '
      'ON local_call_activities(tenant_id,customer_uuid,called_at)',
    );
  }

  Future<void> _createOrderTables(Database database) async {
    await database.execute(
      'CREATE TABLE IF NOT EXISTS local_orders ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'tenant_id TEXT NOT NULL, '
      'offline_uuid TEXT NOT NULL, '
      'server_uuid TEXT, '
      'order_number TEXT, '
      'customer_uuid TEXT NOT NULL, '
      'customer_name TEXT NOT NULL, '
      'visit_uuid TEXT, '
      'ordered_at TEXT NOT NULL, '
      'payment_type TEXT NOT NULL, '
      'status TEXT NOT NULL DEFAULT "pending", '
      'currency TEXT NOT NULL, '
      'subtotal REAL NOT NULL DEFAULT 0, '
      'discount_total REAL NOT NULL DEFAULT 0, '
      'grand_total REAL NOT NULL DEFAULT 0, '
      'client_estimated_total REAL NOT NULL DEFAULT 0, '
      'pricing_adjusted INTEGER NOT NULL DEFAULT 0, '
      'notes TEXT, '
      'status_note TEXT, '
      'status_changed_at TEXT, '
      'sync_status TEXT NOT NULL DEFAULT "pending", '
      'last_error TEXT, '
      'created_at TEXT NOT NULL, '
      'updated_at TEXT NOT NULL'
      ')',
    );
    await database.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_orders_tenant_uuid '
      'ON local_orders(tenant_id,offline_uuid)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_orders_customer '
      'ON local_orders(tenant_id,customer_uuid,ordered_at)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_orders_sync '
      'ON local_orders(tenant_id,sync_status,ordered_at)',
    );

    await database.execute(
      'CREATE TABLE IF NOT EXISTS local_order_items ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'tenant_id TEXT NOT NULL, '
      'order_offline_uuid TEXT NOT NULL, '
      'server_uuid TEXT, '
      'product_uuid TEXT NOT NULL, '
      'product_sku TEXT NOT NULL, '
      'product_name TEXT NOT NULL, '
      'unit TEXT NOT NULL, '
      'quantity REAL NOT NULL, '
      'unit_price REAL NOT NULL, '
      'discount_percent REAL NOT NULL DEFAULT 0, '
      'discount_amount REAL NOT NULL DEFAULT 0, '
      'line_total REAL NOT NULL'
      ')',
    );
    await database.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_order_items_product '
      'ON local_order_items(tenant_id,order_offline_uuid,product_uuid)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_order_items_order '
      'ON local_order_items(tenant_id,order_offline_uuid)',
    );
  }

  Future<void> _createCollectionTables(Database database) async {
    await database.execute(
      'CREATE TABLE IF NOT EXISTS local_collections ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'tenant_id TEXT NOT NULL, '
      'offline_uuid TEXT NOT NULL, '
      'server_uuid TEXT, '
      'receipt_number TEXT NOT NULL, '
      'customer_uuid TEXT NOT NULL, '
      'customer_name TEXT NOT NULL, '
      'visit_uuid TEXT, '
      'collected_at TEXT NOT NULL, '
      'currency TEXT NOT NULL, '
      'amount REAL NOT NULL, '
      'payment_method TEXT NOT NULL, '
      'reference_number TEXT, '
      'status TEXT NOT NULL DEFAULT "pending", '
      'latitude REAL NOT NULL, '
      'longitude REAL NOT NULL, '
      'accuracy REAL NOT NULL, '
      'balance_before REAL NOT NULL DEFAULT 0, '
      'overpayment_flag INTEGER NOT NULL DEFAULT 0, '
      'notes TEXT, '
      'status_note TEXT, '
      'status_changed_at TEXT, '
      'sync_status TEXT NOT NULL DEFAULT "pending", '
      'last_error TEXT, '
      'created_at TEXT NOT NULL, '
      'updated_at TEXT NOT NULL'
      ')',
    );
    await database.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_collections_tenant_uuid '
      'ON local_collections(tenant_id,offline_uuid)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_collections_customer '
      'ON local_collections(tenant_id,customer_uuid,collected_at)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_collections_sync '
      'ON local_collections(tenant_id,sync_status,collected_at)',
    );

    await database.execute(
      'CREATE TABLE IF NOT EXISTS local_customer_balances ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'tenant_id TEXT NOT NULL, '
      'customer_uuid TEXT NOT NULL, '
      'customer_name TEXT NOT NULL, '
      'currency TEXT NOT NULL, '
      'receivable_total REAL NOT NULL DEFAULT 0, '
      'verified_collections REAL NOT NULL DEFAULT 0, '
      'pending_collections REAL NOT NULL DEFAULT 0, '
      'outstanding_balance REAL NOT NULL DEFAULT 0, '
      'updated_at TEXT NOT NULL'
      ')',
    );
    await database.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_customer_balances_unique '
      'ON local_customer_balances(tenant_id,customer_uuid,currency)',
    );
  }

  Future<void> _upgrade(
    Database database,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 5 &&
        await _tableExists(database, 'sync_queue') &&
        !await _hasColumn(database, 'sync_queue', 'tenant_id')) {
      await database.execute(
        'ALTER TABLE sync_queue '
        'ADD COLUMN tenant_id TEXT NOT NULL DEFAULT ""',
      );
    }

    await _createSyncTables(database);

    if (oldVersion < 6) {
      if (await _tableExists(database, 'local_work_sessions') &&
          !await _hasColumn(database, 'local_work_sessions', 'tenant_id')) {
        await database.execute(
          'ALTER TABLE local_work_sessions '
          'ADD COLUMN tenant_id TEXT NOT NULL DEFAULT ""',
        );
      }
      if (await _tableExists(database, 'local_gps_points') &&
          !await _hasColumn(database, 'local_gps_points', 'tenant_id')) {
        await database.execute(
          'ALTER TABLE local_gps_points '
          'ADD COLUMN tenant_id TEXT NOT NULL DEFAULT ""',
        );
      }

      // Legacy attendance/GPS rows have no trustworthy tenant identity. Keep
      // them locally but quarantine them under the empty tenant so they can
      // never upload into a newly signed-in tenant.
      await database.execute('DROP INDEX IF EXISTS one_active_session');
      await database.execute('DROP INDEX IF EXISTS idx_gps_pending');
      await database.execute('DROP INDEX IF EXISTS idx_gps_recorded');
    }

    await _createAttendanceTables(database);
    await _createVisitTables(database);
    await _createOrderTables(database);
    await _createCollectionTables(database);

    if (oldVersion < 4 &&
        !await _hasColumn(database, 'local_work_sessions', 'start_source')) {
      await database.execute(
        'ALTER TABLE local_work_sessions '
        'ADD COLUMN start_source TEXT NOT NULL DEFAULT "manual"',
      );
    }

    if (oldVersion < 5) {
      await _upgradeMasterCacheToV5(database);
    }

    await _createMasterTables(database);
  }

  Future<void> _upgradeMasterCacheToV5(Database database) async {
    final tables = (await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    )).map((row) => row['name']).whereType<String>().toSet();

    for (final name in masterTables) {
      if (!tables.contains(name)) {
        continue;
      }

      if (!await _hasColumn(database, name, 'tenant_id')) {
        await database.execute(
          'ALTER TABLE $name ADD COLUMN tenant_id TEXT NOT NULL DEFAULT ""',
        );
      }
      if (!await _hasColumn(database, name, 'source')) {
        await database.execute(
          'ALTER TABLE $name ADD COLUMN source TEXT NOT NULL DEFAULT "server"',
        );
      }
      if (!await _hasColumn(database, name, 'sync_status')) {
        await database.execute(
          'ALTER TABLE $name '
          'ADD COLUMN sync_status TEXT NOT NULL DEFAULT "synced"',
        );
      }

      // Pre-v5 master rows had no tenant identity. They are cache only, so
      // discard them rather than risk exposing one tenant's data to another.
      await database.delete(name, where: 'tenant_id = ?', whereArgs: ['']);
    }

    if (tables.contains('local_products')) {
      await database.execute('DROP TABLE IF EXISTS local_products');
    }
  }

  Future<bool> _tableExists(Database database, String table) async {
    final rows = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [table],
    );

    return rows.isNotEmpty;
  }

  Future<bool> _hasColumn(
    Database database,
    String table,
    String column,
  ) async {
    final rows = await database.rawQuery('PRAGMA table_info($table)');

    return rows.any((row) => row['name'] == column);
  }

  Future<void> setting(String key, Object value) => db.insert(
    'local_settings',
    {'key': key, 'value': jsonEncode(value)},
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  Future<dynamic> readSetting(String key) async {
    final rows = await db.query(
      'local_settings',
      where: 'key=?',
      whereArgs: [key],
      limit: 1,
    );

    return rows.isEmpty ? null : jsonDecode(rows.first['value'] as String);
  }

  static const masterTables = [
    'customers',
    'territories',
    'routes',
    'route_customers',
    'products',
    'price_lists',
    'price_list_items',
  ];
}
