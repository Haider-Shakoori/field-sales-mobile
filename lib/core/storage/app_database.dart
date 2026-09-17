import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../sync/sync_status.dart';

/// Local offline-first database (SQLite via sqflite).
///
/// v1 held the sync queue, the pending-local entities mirror, settings and the
/// sync log. v2 adds the master-data cache tables (customers, territories,
/// routes, route customers, products, price lists + items) and session meta so
/// the app stays fully readable offline. All schema is created idempotently.
class AppDatabase {
  AppDatabase._();

  static const version = 2;
  static Database? _instance;
  static Future<Database>? _opening;

  static Future<Database> get instance async {
    final cached = _instance;
    if (cached != null) {
      return cached;
    }
    final inFlight = _opening;
    if (inFlight != null) {
      return inFlight;
    }
    final opening = _open();
    _opening = opening;
    try {
      final db = await opening;
      _instance = db;
      return db;
    } finally {
      _opening = null;
    }
  }

  static Future<Database> _open() async {
    final path = join(await getDatabasesPath(), 'field_sales.db');
    return openDatabase(
      path,
      version: version,
      onCreate: createSchema,
      onUpgrade: upgradeSchema,
    );
  }

  /// Test hook: replaces the singleton with a caller-managed database so the
  /// whole schema (including onUpgrade) can be exercised with sqflite_common_ffi.
  static void overrideInstance(Database db) => _instance = db;

  static Future<void> createSchema(Database db, int version) async {
    await _createQueueTables(db);
    await _createLocalTables(db);
    await _createMasterDataTables(db);
    await _createSessionTables(db);
  }

  static Future<void> upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await _createMasterDataTables(db);
      await _createSessionTables(db);
    }
  }

  static Future<void> _createQueueTables(Database db) async {
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
        status TEXT NOT NULL DEFAULT '${nameOf(SyncStatus.pending)}',
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
  }

  static Future<void> _createLocalTables(Database db) async {
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
        sync_status TEXT NOT NULL DEFAULT '${nameOf(SyncStatus.synced)}',
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE local_settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
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
  }

  static Future<void> _createMasterDataTables(Database db) async {
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
  }

  static Future<void> _createSessionTables(Database db) async {
    await db.execute('''
      CREATE TABLE session_meta (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
  }

  static Future<void> close() async {
    final db = _instance;
    _instance = null;
    if (db != null) {
      await db.close();
    }
  }
}

String nameOf(SyncStatus status) => status.name;
