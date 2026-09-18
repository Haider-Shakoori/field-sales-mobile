import 'dart:io';

import 'package:field_sales_mobile/core/storage/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/test_harness.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  tearDown(tearDownDatabase);

  group('DATABASE v4 — schema', () {
    test(
      'v4 creates the attendance and GPS tables with required indexes',
      () async {
        await initTestDatabase();

        final tables = await _objectNames('table');
        expect(
          tables,
          containsAll(['local_work_sessions', 'local_gps_points']),
        );

        final indexes = await _objectNames('index');
        expect(
          indexes,
          containsAll([
            'idx_work_sessions_single_active',
            'idx_work_sessions_date',
            'idx_gps_points_sync',
            'idx_gps_points_recorded',
          ]),
        );

        final columns = await _columnNames('local_work_sessions');
        expect(columns, contains('start_source'));
      },
    );

    test('at most one ACTIVE local work session is enforced', () async {
      await initTestDatabase();
      final db = await AppDatabase.instance;

      await db.insert('local_work_sessions', _sessionRow('s-1'));
      await expectLater(
        db.insert('local_work_sessions', _sessionRow('s-2')),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  group('DATABASE v3 → v4 migration', () {
    test('adds start_source additively and preserves v3 rows', () async {
      final dir = Directory.systemTemp.createTempSync('field_sales_v3_keep');
      final dbPath = '${dir.path}${Platform.pathSeparator}upgrade.db';
      addTearDown(() => dir.deleteSync(recursive: true));

      final legacy = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(version: 3, onCreate: _v3Create),
      );
      await legacy.insert('local_work_sessions', _sessionRow('v3-session'));
      await legacy.insert('local_gps_points', _gpsRow('v3-point'));
      await legacy.insert('customers', {
        'id': 1,
        'uuid': 'c-1',
        'name': 'Kept Shop',
        'is_active': 1,
      });
      await legacy.close();

      final upgraded = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: AppDatabase.version,
          onCreate: AppDatabase.createSchema,
          onUpgrade: AppDatabase.upgradeSchema,
        ),
      );
      AppDatabase.overrideInstance(upgraded);

      final rows = await DbAsserts.query('SELECT * FROM local_work_sessions');
      expect(rows, hasLength(1));
      expect(rows.single['offline_uuid'], 'v3-session');
      expect(rows.single['start_source'], 'manual');
      expect(
        (await DbAsserts.query('SELECT * FROM local_gps_points')),
        hasLength(1),
      );
      expect(
        (await DbAsserts.query("SELECT name FROM customers WHERE id = 1"))
            .single['name'],
        'Kept Shop',
      );

      // New values remain writable after the additive migration.
      await upgraded.update(
        'local_work_sessions',
        {'start_source': 'automatic'},
        where: 'offline_uuid = ?',
        whereArgs: ['v3-session'],
      );
      final automatic = await DbAsserts.query(
        "SELECT start_source FROM local_work_sessions WHERE offline_uuid = 'v3-session'",
      );
      expect(automatic.single['start_source'], 'automatic');

      await AppDatabase.close();
    });
  });

  group('DATABASE v2 → v3 migration', () {
    test('preserves every Batch 6 table and creates Batch 7 tables', () async {
      final dir = Directory.systemTemp.createTempSync('field_sales_v2_keep');
      final dbPath = '${dir.path}${Platform.pathSeparator}upgrade.db';
      addTearDown(() => dir.deleteSync(recursive: true));

      final legacy = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(version: 2, onCreate: _v2Create),
      );
      await legacy.insert('customers', {
        'id': 1,
        'uuid': 'c-1',
        'name': 'Batch Six Shop',
        'business_name': 'Batch Six Shop',
        'is_active': 1,
      });
      await legacy.insert('products', {
        'id': 10,
        'uuid': 'p-10',
        'name': 'Batch Six Product',
        'price': 3.5,
        'is_active': 1,
      });
      await legacy.insert('routes', {
        'id': 5,
        'uuid': 'r-5',
        'name': 'Batch Six Route',
        'is_active': 1,
      });
      await legacy.insert('session_meta', {
        'key': 'current_user',
        'value': '{"id":7,"name":"Salesman Seven"}',
      });
      await legacy.insert('sync_queue', {
        'entity_type': 'attendance',
        'entity_uuid': 'old-entry',
        'action': 'start',
        'payload': '{}',
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
      });
      await legacy.insert('local_settings', {'key': 'keep', 'value': 'me'});
      await legacy.close();

      final upgraded = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: AppDatabase.version,
          onCreate: AppDatabase.createSchema,
          onUpgrade: AppDatabase.upgradeSchema,
        ),
      );
      AppDatabase.overrideInstance(upgraded);

      // Batch 6 data retained.
      expect(
        (await DbAsserts.query("SELECT name FROM customers WHERE id = 1"))
            .single['name'],
        'Batch Six Shop',
      );
      expect(
        (await DbAsserts.query("SELECT name FROM products WHERE id = 10"))
            .single['name'],
        'Batch Six Product',
      );
      expect(
        (await DbAsserts.query("SELECT name FROM routes WHERE id = 5"))
            .single['name'],
        'Batch Six Route',
      );
      expect(
        (await DbAsserts.query('SELECT * FROM session_meta WHERE key = ?', [
          'current_user',
        ])),
        hasLength(1),
      );
      expect(
        (await DbAsserts.query(
          'SELECT * FROM sync_queue WHERE entity_uuid = ?',
          ['old-entry'],
        )),
        hasLength(1),
      );
      expect(
        (await DbAsserts.query('SELECT * FROM local_settings WHERE key = ?', [
          'keep',
        ])),
        hasLength(1),
      );

      // Batch 7 tables exist and are writable.
      final tables = await _objectNames('table');
      expect(tables, containsAll(['local_work_sessions', 'local_gps_points']));

      await upgraded.insert('local_work_sessions', _sessionRow('new-session'));
      await upgraded.insert('local_gps_points', _gpsRow('gps-1'));
      expect(
        (await DbAsserts.query('SELECT * FROM local_work_sessions')),
        hasLength(1),
      );
      expect(
        (await DbAsserts.query('SELECT * FROM local_gps_points')),
        hasLength(1),
      );

      // Close before the temp directory teardown removes the file (Windows).
      await AppDatabase.close();
    });
  });
}

Future<Set<String>> _objectNames(String type) async {
  final rows = await DbAsserts.query(
    "SELECT name FROM sqlite_master WHERE type = ?",
    [type],
  );
  return rows.map((r) => r['name']!.toString()).toSet();
}

Future<Set<String>> _columnNames(String table) async {
  final rows = await DbAsserts.query('PRAGMA table_info($table)');
  return rows.map((r) => r['name']!.toString()).toSet();
}

Map<String, Object?> _sessionRow(String uuid) => {
  'offline_uuid': uuid,
  'date': '2026-01-15',
  'start_time': '2026-01-15T08:00:00Z',
  'start_latitude': 34.5,
  'start_longitude': 69.2,
  'status': 'active',
  'sync_status': 'pending',
  'created_at': '2026-01-15T08:00:00Z',
  'updated_at': '2026-01-15T08:00:00Z',
};

Map<String, Object?> _gpsRow(String uuid) => {
  'client_uuid': uuid,
  'latitude': 34.5,
  'longitude': 69.2,
  'is_charging': 0,
  'is_mock_location': 0,
  'recorded_at': '2026-01-15T08:00:00Z',
  'sequence_number': 1,
  'sync_status': 'pending',
  'created_at': '2026-01-15T08:00:00Z',
};

/// Exact Batch 6 (v2) schema — kept verbatim so the upgrade test exercises the
/// real production migration path rather than a synthetic subset.
Future<void> _v2Create(Database db, int version) async {
  await db.execute('''
    CREATE TABLE sync_queue (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      entity_type TEXT NOT NULL,
      entity_uuid TEXT NOT NULL,
      action TEXT NOT NULL,
      payload TEXT NOT NULL,
      priority INTEGER NOT NULL DEFAULT 5,
      attempts INTEGER NOT NULL DEFAULT 0,
      max_attempts INTEGER NOT NULL DEFAULT 5,
      status TEXT NOT NULL DEFAULT 'pending',
      error_message TEXT,
      next_retry_at TEXT,
      server_id TEXT,
      server_uuid TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');
  await db.execute(
    'CREATE INDEX idx_sync_queue_status_priority ON sync_queue(status, priority, created_at)',
  );
  await db.execute(
    'CREATE INDEX idx_sync_queue_entity ON sync_queue(entity_type, entity_uuid)',
  );

  await db.execute('''
    CREATE TABLE local_products (
      uuid TEXT PRIMARY KEY,
      id INTEGER,
      sku TEXT,
      name TEXT NOT NULL,
      category TEXT,
      unit TEXT,
      price REAL NOT NULL DEFAULT 0,
      is_active INTEGER NOT NULL DEFAULT 1,
      sync_status TEXT NOT NULL DEFAULT 'synced',
      updated_at TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE local_settings (key TEXT PRIMARY KEY, value TEXT)
  ''');
  await db.execute('''
    CREATE TABLE local_sync_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sync_type TEXT NOT NULL,
      direction TEXT NOT NULL,
      status TEXT NOT NULL,
      records INTEGER NOT NULL DEFAULT 0,
      duration_ms INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL
    )
  ''');

  await db.execute('''
    CREATE TABLE customers (
      id INTEGER PRIMARY KEY,
      uuid TEXT,
      offline_uuid TEXT,
      code TEXT,
      name TEXT,
      business_name TEXT,
      contact_person TEXT,
      phone TEXT,
      whatsapp TEXT,
      email TEXT,
      address TEXT,
      province TEXT,
      district TEXT,
      latitude REAL,
      longitude REAL,
      geofence_radius REAL,
      photo_url TEXT,
      branch_id INTEGER,
      branch_name TEXT,
      category_id INTEGER,
      category_name TEXT,
      territory_id INTEGER,
      territory_name TEXT,
      route_id INTEGER,
      route_name TEXT,
      assigned_salesman_id INTEGER,
      assigned_salesman_name TEXT,
      credit_limit REAL DEFAULT 0,
      outstanding_balance REAL DEFAULT 0,
      price_list_id INTEGER,
      price_list_name TEXT,
      visit_frequency TEXT,
      is_active INTEGER NOT NULL DEFAULT 1,
      notes TEXT,
      updated_at TEXT,
      cached_at TEXT
    )
  ''');
  await db.execute('CREATE INDEX idx_customers_route ON customers(route_id)');
  await db.execute(
    'CREATE INDEX idx_customers_territory ON customers(territory_id)',
  );

  await db.execute('''
    CREATE TABLE territories (
      id INTEGER PRIMARY KEY,
      uuid TEXT,
      code TEXT,
      name TEXT,
      description TEXT,
      branch_id INTEGER,
      branch_name TEXT,
      latitude REAL,
      longitude REAL,
      radius_km REAL,
      is_active INTEGER NOT NULL DEFAULT 1,
      routes_count INTEGER DEFAULT 0,
      customers_count INTEGER DEFAULT 0,
      updated_at TEXT,
      cached_at TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE routes (
      id INTEGER PRIMARY KEY,
      uuid TEXT,
      code TEXT,
      name TEXT,
      description TEXT,
      territory_id INTEGER,
      territory_name TEXT,
      branch_id INTEGER,
      branch_name TEXT,
      weekday INTEGER,
      weekday_name TEXT,
      is_active INTEGER NOT NULL DEFAULT 1,
      customer_count INTEGER DEFAULT 0,
      salesman_id INTEGER,
      salesman_name TEXT,
      updated_at TEXT,
      cached_at TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE route_customers (
      route_id INTEGER NOT NULL,
      customer_id INTEGER NOT NULL,
      customer_name TEXT,
      customer_code TEXT,
      visit_order INTEGER DEFAULT 0,
      route_customer_id INTEGER,
      is_active INTEGER NOT NULL DEFAULT 1,
      cached_at TEXT,
      PRIMARY KEY (route_id, customer_id)
    )
  ''');
  await db.execute(
    'CREATE INDEX idx_route_customers_order ON route_customers(route_id, visit_order)',
  );

  await db.execute('''
    CREATE TABLE products (
      id INTEGER PRIMARY KEY,
      uuid TEXT,
      sku TEXT,
      name TEXT NOT NULL,
      category TEXT,
      unit TEXT,
      price REAL NOT NULL DEFAULT 0,
      is_active INTEGER NOT NULL DEFAULT 1,
      updated_at TEXT,
      cached_at TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE price_lists (
      id INTEGER PRIMARY KEY,
      uuid TEXT,
      name TEXT NOT NULL,
      is_default INTEGER NOT NULL DEFAULT 0,
      is_active INTEGER NOT NULL DEFAULT 1,
      items_count INTEGER DEFAULT 0,
      updated_at TEXT,
      cached_at TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE price_list_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      price_list_id INTEGER NOT NULL,
      product_id INTEGER NOT NULL,
      price REAL NOT NULL DEFAULT 0,
      cached_at TEXT,
      UNIQUE (price_list_id, product_id)
    )
  ''');

  await db.execute('''
    CREATE TABLE session_meta (key TEXT PRIMARY KEY, value TEXT)
  ''');
}

/// Exact Batch 7 v3 schema (no `start_source` column) so the v3 → v4
/// additive migration is exercised against the real prior production shape.
Future<void> _v3Create(Database db, int version) async {
  await _v2Create(db, version);

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
      start_accuracy REAL,
      end_latitude REAL,
      end_longitude REAL,
      end_accuracy REAL,
      status TEXT NOT NULL DEFAULT 'active',
      sync_status TEXT NOT NULL DEFAULT 'pending',
      privacy_ack_at TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');
  await db.execute(
    'CREATE UNIQUE INDEX idx_work_sessions_single_active '
    "ON local_work_sessions(status) WHERE status = 'active'",
  );
  await db.execute(
    'CREATE INDEX idx_work_sessions_date ON local_work_sessions(date)',
  );

  await db.execute('''
    CREATE TABLE local_gps_points (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      client_uuid TEXT NOT NULL UNIQUE,
      latitude REAL NOT NULL,
      longitude REAL NOT NULL,
      altitude REAL,
      accuracy REAL,
      speed REAL,
      heading REAL,
      battery_level INTEGER,
      is_charging INTEGER NOT NULL DEFAULT 0,
      network_status TEXT,
      is_mock_location INTEGER NOT NULL DEFAULT 0,
      provider TEXT,
      recorded_at TEXT NOT NULL,
      sequence_number INTEGER NOT NULL DEFAULT 0,
      batch_uuid TEXT,
      sync_status TEXT NOT NULL DEFAULT 'pending',
      last_error TEXT,
      uploaded_at TEXT,
      created_at TEXT NOT NULL
    )
  ''');
  await db.execute(
    'CREATE INDEX idx_gps_points_sync ON local_gps_points(sync_status, id)',
  );
  await db.execute(
    'CREATE INDEX idx_gps_points_recorded ON local_gps_points(recorded_at)',
  );
}
