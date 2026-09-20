import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../core/db/app_database.dart';
import '../../core/sync/connectivity_gate.dart';
import 'master_data_source.dart';

class MasterDataRepository {
  MasterDataRepository({required this.database, required this.source});

  final AppDatabase database;
  final MasterDataSource source;

  static const _rootCollections = <String, String>{
    'customers': 'customers',
    'territories': 'territories',
    'routes': 'routes',
    'products': 'products',
    'price_lists': 'price-lists',
  };

  Future<void> refreshAll(String tenantId) async {
    if (!await ConnectivityGate.instance.isOnline()) {
      return;
    }

    for (final entry in _rootCollections.entries) {
      await _refreshCollection(
        tenantId: tenantId,
        table: entry.key,
        path: entry.value,
      );
    }

    final routes = await list('routes', tenantId);
    for (final route in routes) {
      final routeId = route['id']?.toString();
      if (routeId == null || routeId.isEmpty) {
        continue;
      }

      await _refreshCollection(
        tenantId: tenantId,
        table: 'route_customers',
        path: 'routes/$routeId/customers',
        syntheticUuid: (row) => '$routeId:${row['id']}',
        decorate: (row) => {...row, 'route_id': routeId},
      );
    }

    final priceLists = await list('price_lists', tenantId);
    for (final priceList in priceLists) {
      final priceListId = priceList['id']?.toString();
      if (priceListId == null || priceListId.isEmpty) {
        continue;
      }

      await _refreshCollection(
        tenantId: tenantId,
        table: 'price_list_items',
        path: 'price-lists/$priceListId/items',
      );
    }
  }

  Future<List<Map<String, dynamic>>> list(String table, String tenantId) async {
    _assertMasterTable(table);

    final rows = await database.db.query(
      table,
      where: 'tenant_id = ?',
      whereArgs: [tenantId],
      orderBy: 'id ASC',
    );

    return rows
        .map(
          (row) => Map<String, dynamic>.from(
            jsonDecode(row['payload'] as String) as Map,
          ),
        )
        .toList();
  }

  Future<int> pendingCount(String tenantId) async {
    final rows = await database.db.rawQuery(
      'SELECT COUNT(*) AS total FROM sync_queue '
      'WHERE tenant_id = ? AND status = ?',
      [tenantId, 'pending'],
    );

    return (rows.first['total'] as int?) ?? 0;
  }

  Future<void> cacheServerRow({
    required String table,
    required String tenantId,
    required Map<String, dynamic> row,
    DatabaseExecutor? executor,
  }) async {
    _assertMasterTable(table);

    final uuid = row['id']?.toString() ?? row['uuid']?.toString();
    if (uuid == null || uuid.isEmpty) {
      throw StateError('Master-data row is missing a UUID.');
    }

    final target = executor ?? database.db;
    final now = DateTime.now().toUtc().toIso8601String();

    await target.insert(table, {
      'tenant_id': tenantId,
      'uuid': uuid,
      'payload': jsonEncode(row),
      'cached_at': now,
      'source': 'server',
      'sync_status': 'synced',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _refreshCollection({
    required String tenantId,
    required String table,
    required String path,
    String Function(Map<String, dynamic> row)? syntheticUuid,
    Map<String, dynamic> Function(Map<String, dynamic> row)? decorate,
  }) async {
    _assertMasterTable(table);

    final syncKey = 'master_sync:$tenantId:$table:$path';
    final updatedSince = await database.readSetting(syncKey) as String?;
    final syncStartedAt = DateTime.now().toUtc().toIso8601String();
    var pageNumber = 1;

    while (true) {
      final page = await source.fetchPage(
        path,
        page: pageNumber,
        updatedSince: updatedSince,
      );

      await database.db.transaction((transaction) async {
        for (final original in page.rows) {
          final row = decorate?.call(original) ?? original;
          final uuid =
              syntheticUuid?.call(row) ??
              row['id']?.toString() ??
              row['uuid']?.toString();

          if (uuid == null || uuid.isEmpty) {
            continue;
          }

          await transaction.insert(table, {
            'tenant_id': tenantId,
            'uuid': uuid,
            'payload': jsonEncode(row),
            'cached_at': syncStartedAt,
            'source': 'server',
            'sync_status': 'synced',
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });

      if (!page.hasMore) {
        break;
      }

      pageNumber = page.nextPage ?? pageNumber + 1;
    }

    await database.setting(syncKey, syncStartedAt);
  }

  void _assertMasterTable(String table) {
    if (!AppDatabase.masterTables.contains(table)) {
      throw ArgumentError.value(table, 'table', 'Unsupported master table');
    }
  }
}
