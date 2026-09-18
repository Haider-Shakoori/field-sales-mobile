import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  static const version = 5;

  Database? _db;
  Database get db => _db!;

  Future<void> open() async {
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'field_sales.db'),
      version: version,
      onCreate: (database, _) => _createV5(database),
      onUpgrade: _upgrade,
    );
  }

  Future<void> _createV5(Database db) async {
    await db.execute('''
      CREATE TABLE sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entity_type TEXT NOT NULL,
        entity_uuid TEXT NOT NULL,
        action TEXT NOT NULL,
        payload TEXT NOT NULL,
        priority INTEGER NOT NULL DEFAULT 100,
        attempts INTEGER NOT NULL DEFAULT 0,
        max_attempts INTEGER NOT NULL DEFAULT 10,
        status TEXT NOT NULL DEFAULT "pending",
        error_message TEXT,
        next_retry_at TEXT,
        server_id INTEGER,
        server_uuid TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_sync_status_priority ON sync_queue(status,priority,created_at)');
    await db.execute('CREATE INDEX idx_sync_entity ON sync_queue(entity_type,entity_uuid)');

    await db.execute('CREATE TABLE local_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
    await db.execute('CREATE TABLE local_sync_log (id INTEGER PRIMARY KEY AUTOINCREMENT, level TEXT, message TEXT, created_at TEXT NOT NULL)');

    for (final name in [
      'customers',
      'territories',
      'routes',
      'route_customers',
      'products',
      'price_lists',
      'price_list_items',
    ]) {
      await db.execute('CREATE TABLE ' + name + ' (id INTEGER PRIMARY KEY, uuid TEXT, payload TEXT NOT NULL, cached_at TEXT NOT NULL)');
      await db.execute('CREATE INDEX idx_' + name + '_uuid ON ' + name + '(uuid)');
    }

    await db.execute('CREATE TABLE session_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)');

    await db.execute('''
      CREATE TABLE local_work_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        offline_uuid TEXT NOT NULL UNIQUE,
        server_id INTEGER,
        date TEXT NOT NULL,
        start_time TEXT NOT NULL,
        end_time TEXT,
        start_latitude REAL NOT NULL,
        start_longitude REAL NOT NULL,
        start_accuracy REAL NOT NULL,
        end_latitude REAL,
        end_longitude REAL,
        end_accuracy REAL,
        status TEXT NOT NULL,
        sync_status TEXT NOT NULL,
        start_source TEXT NOT NULL DEFAULT "manual",
        privacy_ack_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE UNIQUE INDEX one_active_session ON local_work_sessions(status) WHERE status="active"');
    await db.execute('CREATE INDEX idx_work_sessions_date ON local_work_sessions(date)');

    await db.execute('''
      CREATE TABLE local_gps_points (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        client_uuid TEXT NOT NULL UNIQUE,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        altitude REAL,
        accuracy REAL NOT NULL,
        speed REAL,
        heading REAL,
        battery_level INTEGER,
        is_charging INTEGER NOT NULL DEFAULT 0,
        network_status TEXT,
        is_mock_location INTEGER NOT NULL DEFAULT 0,
        provider TEXT,
        recorded_at TEXT NOT NULL,
        sequence_number INTEGER NOT NULL,
        batch_uuid TEXT,
        sync_status TEXT NOT NULL DEFAULT "pending",
        last_error TEXT,
        uploaded_at TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_gps_pending ON local_gps_points(sync_status,id)');
    await db.execute('CREATE INDEX idx_gps_recorded ON local_gps_points(recorded_at)');

    await db.execute('''
      CREATE TABLE privacy_acknowledgements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        policy_version TEXT NOT NULL,
        acknowledged_at TEXT NOT NULL,
        user_id TEXT,
        tenant_id TEXT,
        device_id TEXT,
        app_version TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT "pending",
        server_id INTEGER,
        server_uuid TEXT,
        UNIQUE(policy_version,user_id,tenant_id,device_id)
      )
    ''');

    await _createOperationsTables(db);
  }

  Future<void> _createOperationsTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_visits (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        offline_uuid TEXT NOT NULL UNIQUE,
        server_id INTEGER,
        customer_uuid TEXT NOT NULL,
        route_uuid TEXT,
        work_session_uuid TEXT,
        is_planned INTEGER NOT NULL DEFAULT 1,
        status TEXT NOT NULL,
        checked_in_at TEXT NOT NULL,
        checked_out_at TEXT,
        check_in_latitude REAL NOT NULL,
        check_in_longitude REAL NOT NULL,
        check_in_accuracy REAL NOT NULL,
        check_out_latitude REAL,
        check_out_longitude REAL,
        check_out_accuracy REAL,
        within_geofence INTEGER,
        distance_from_customer_m REAL,
        duration_minutes INTEGER,
        outcome TEXT,
        notes TEXT,
        media_json TEXT,
        flags_json TEXT,
        sync_status TEXT NOT NULL DEFAULT "pending",
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS one_active_visit ON local_visits(status) WHERE status="checked_in"');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_local_visits_customer ON local_visits(customer_uuid,checked_in_at)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_call_activities (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        offline_uuid TEXT NOT NULL UNIQUE,
        server_id INTEGER,
        customer_uuid TEXT NOT NULL,
        visit_uuid TEXT,
        phone_number TEXT NOT NULL,
        initiated_at TEXT NOT NULL,
        outcome TEXT,
        notes TEXT,
        sync_status TEXT NOT NULL DEFAULT "pending",
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_local_calls_customer ON local_call_activities(customer_uuid,initiated_at)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        offline_uuid TEXT NOT NULL UNIQUE,
        server_id INTEGER,
        server_uuid TEXT,
        customer_uuid TEXT NOT NULL,
        visit_uuid TEXT,
        ordered_at TEXT NOT NULL,
        currency TEXT NOT NULL,
        discount_amount REAL NOT NULL DEFAULT 0,
        cash_amount REAL NOT NULL DEFAULT 0,
        subtotal REAL NOT NULL DEFAULT 0,
        total_amount REAL NOT NULL DEFAULT 0,
        credit_amount REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT "draft",
        notes TEXT,
        sync_status TEXT NOT NULL DEFAULT "pending",
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_local_orders_customer ON local_orders(customer_uuid,ordered_at)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_order_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_uuid TEXT NOT NULL,
        product_uuid TEXT NOT NULL,
        quantity REAL NOT NULL,
        unit_price REAL NOT NULL,
        discount_amount REAL NOT NULL DEFAULT 0,
        line_total REAL NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_local_order_items_order ON local_order_items(order_uuid)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_collections (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        offline_uuid TEXT NOT NULL UNIQUE,
        server_id INTEGER,
        customer_uuid TEXT NOT NULL,
        order_uuid TEXT,
        visit_uuid TEXT,
        amount REAL NOT NULL,
        currency TEXT NOT NULL,
        payment_method TEXT NOT NULL,
        receipt_number TEXT,
        manual_reference TEXT,
        collected_at TEXT NOT NULL,
        latitude REAL,
        longitude REAL,
        accuracy REAL,
        receipt_photo_path TEXT,
        notes TEXT,
        sync_status TEXT NOT NULL DEFAULT "pending",
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        offline_uuid TEXT NOT NULL UNIQUE,
        server_id INTEGER,
        category TEXT NOT NULL,
        amount REAL NOT NULL,
        currency TEXT NOT NULL,
        spent_at TEXT NOT NULL,
        latitude REAL,
        longitude REAL,
        receipt_photo_path TEXT,
        notes TEXT,
        status TEXT NOT NULL DEFAULT "submitted",
        sync_status TEXT NOT NULL DEFAULT "pending",
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('CREATE TABLE IF NOT EXISTS local_targets (uuid TEXT PRIMARY KEY, payload TEXT NOT NULL, cached_at TEXT NOT NULL)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_notifications (
        uuid TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        data_json TEXT,
        created_at TEXT NOT NULL,
        read_at TEXT
      )
    ''');
  }

  Future<bool> _hasColumn(Database db, String table, String column) async =>
      (await db.rawQuery('PRAGMA table_info(' + table + ')')).any((row) => row['name'] == column);

  Future<void> _upgrade(Database db, int old, int next) async {
    final tables = (await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
        .map((row) => row['name'])
        .toSet();

    if (old < 4) {
      if (!tables.contains('local_work_sessions')) {
        await _createV5(db);
        return;
      }

      if (!await _hasColumn(db, 'local_work_sessions', 'start_source')) {
        await db.execute('ALTER TABLE local_work_sessions ADD COLUMN start_source TEXT NOT NULL DEFAULT "manual"');
      }

      if (!tables.contains('local_gps_points')) {
        await db.execute('''
          CREATE TABLE local_gps_points (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            client_uuid TEXT NOT NULL UNIQUE,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            altitude REAL,
            accuracy REAL NOT NULL,
            speed REAL,
            heading REAL,
            battery_level INTEGER,
            is_charging INTEGER NOT NULL DEFAULT 0,
            network_status TEXT,
            is_mock_location INTEGER NOT NULL DEFAULT 0,
            provider TEXT,
            recorded_at TEXT NOT NULL,
            sequence_number INTEGER NOT NULL,
            batch_uuid TEXT,
            sync_status TEXT NOT NULL DEFAULT "pending",
            last_error TEXT,
            uploaded_at TEXT,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('CREATE INDEX idx_gps_pending ON local_gps_points(sync_status,id)');
        await db.execute('CREATE INDEX idx_gps_recorded ON local_gps_points(recorded_at)');
      }

      if (!tables.contains('privacy_acknowledgements')) {
        await db.execute('''
          CREATE TABLE privacy_acknowledgements (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            policy_version TEXT NOT NULL,
            acknowledged_at TEXT NOT NULL,
            user_id TEXT,
            tenant_id TEXT,
            device_id TEXT,
            app_version TEXT NOT NULL,
            sync_status TEXT NOT NULL DEFAULT "pending",
            server_id INTEGER,
            server_uuid TEXT,
            UNIQUE(policy_version,user_id,tenant_id,device_id)
          )
        ''');
      }
    }

    if (old < 5) {
      await _createOperationsTables(db);
      for (final name in [
        'customers',
        'territories',
        'routes',
        'route_customers',
        'products',
        'price_lists',
        'price_list_items',
      ]) {
        if (tables.contains(name)) {
          try {
            await db.execute('CREATE INDEX IF NOT EXISTS idx_' + name + '_uuid ON ' + name + '(uuid)');
          } catch (_) {
            // Older caches may not expose a uuid column.
          }
        }
      }
    }
  }

  Future<void> setting(String key, Object value) => db.insert(
        'local_settings',
        {'key': key, 'value': jsonEncode(value)},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<dynamic> readSetting(String key) async {
    final rows = await db.query('local_settings', where: 'key=?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : jsonDecode(rows.first['value'] as String);
  }
}
