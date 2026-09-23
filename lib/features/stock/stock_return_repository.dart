import 'package:uuid/uuid.dart';

import '../../core/api/api_client.dart';
import '../../core/db/app_database.dart';
import '../../core/sync/connectivity_gate.dart';
import '../../core/sync/local_dependency_guard.dart';
import '../../core/sync/sync_retry_store.dart';

class StockReturnRepository {
  StockReturnRepository({
    required this.api,
    required this.db,
    required this.retry,
  });

  final ApiClient api;
  final AppDatabase db;
  final SyncRetryStore retry;

  Future<void> refreshStock(String tenantId) async {
    if (!await ConnectivityGate.instance.isOnline()) return;

    final response = await api.get('stock/me');
    final data = response is Map<String, dynamic>
        ? response
        : Map<String, dynamic>.from(response as Map);
    final enabled = data['enabled'] == true;
    final rows = (data['stock'] as List? ?? const [])
        .whereType<Map>()
        .map(Map<String, dynamic>.from)
        .toList();
    final now = DateTime.now().toUtc().toIso8601String();

    await db.db.transaction((txn) async {
      await txn.delete(
        'local_stock_balances',
        where: 'tenant_id=?',
        whereArgs: [tenantId],
      );

      for (final row in rows) {
        final productUuid = row['product_id']?.toString();
        if (productUuid == null || productUuid.isEmpty) continue;

        await txn.insert('local_stock_balances', {
          'tenant_id': tenantId,
          'product_uuid': productUuid,
          'sku': (row['sku'] ?? '').toString(),
          'name': (row['name'] ?? 'Product').toString(),
          'unit': (row['unit'] ?? 'pcs').toString(),
          'sellable_qty': _number(row['sellable_qty']),
          'damaged_qty': _number(row['damaged_qty']),
          'server_updated_at': row['updated_at']?.toString(),
          'cached_at': now,
        });
      }
    });

    await db.setting('salesman_stock_enabled:$tenantId', enabled);
  }

  Future<bool> stockEnabled(String tenantId) async {
    final value = await db.readSetting('salesman_stock_enabled:$tenantId');
    return value == true;
  }

  Future<List<Map<String, dynamic>>> stock(String tenantId) async {
    final rows = await db.db.query(
      'local_stock_balances',
      where: 'tenant_id=?',
      whereArgs: [tenantId],
      orderBy: 'name COLLATE NOCASE ASC',
    );

    return rows.map(Map<String, dynamic>.from).toList();
  }

  Future<double?> sellableFor(
    String tenantId,
    String productUuid, {
    bool subtractOpenLocalOrders = true,
  }) async {
    if (!await stockEnabled(tenantId)) return null;

    final rows = await db.db.query(
      'local_stock_balances',
      columns: ['sellable_qty'],
      where: 'tenant_id=? AND product_uuid=?',
      whereArgs: [tenantId, productUuid],
      limit: 1,
    );

    var available = rows.isEmpty ? 0.0 : _number(rows.first['sellable_qty']);

    if (!subtractOpenLocalOrders) return available;

    final reserved = await db.db.rawQuery(
      'SELECT COALESCE(SUM(i.quantity),0) AS total '
      'FROM local_order_items i '
      'JOIN local_orders o '
      'ON o.tenant_id=i.tenant_id '
      'AND o.offline_uuid=i.order_offline_uuid '
      'WHERE i.tenant_id=? AND i.product_uuid=? '
      "AND o.status NOT IN ('rejected','cancelled') "
      "AND o.sync_status<>'synced'",
      [tenantId, productUuid],
    );

    available -= _number(reserved.first['total']);
    return available < 0 ? 0 : available;
  }

  Future<String> createOffline({
    required String tenantId,
    required Map<String, dynamic> customer,
    required DateTime returnedAt,
    required List<ReturnDraftLine> items,
    String? visitUuid,
    String? orderUuid,
    String? notes,
  }) async {
    if (items.isEmpty) {
      throw StateError('Add at least one returned product.');
    }

    final uuid = const Uuid().v4();
    final now = DateTime.now().toUtc().toIso8601String();
    final seen = <String>{};

    for (final item in items) {
      if (item.quantity <= 0) {
        throw StateError('Return quantity must be greater than zero.');
      }
      if (!const {'resalable', 'damaged'}.contains(item.condition)) {
        throw StateError('Return condition must be resalable or damaged.');
      }

      final productUuid = item.product['id']?.toString() ?? '';
      final key = '$productUuid|${item.condition}';
      if (productUuid.isEmpty || !seen.add(key)) {
        throw StateError(
          'Each product and condition combination can appear only once.',
        );
      }
    }

    await db.db.transaction((txn) async {
      await txn.insert('local_sales_returns', {
        'tenant_id': tenantId,
        'offline_uuid': uuid,
        'customer_uuid': customer['id'].toString(),
        'customer_name': (customer['name'] ?? 'Customer').toString(),
        'visit_uuid': visitUuid,
        'order_uuid': orderUuid,
        'returned_at': returnedAt.toUtc().toIso8601String(),
        'status': 'pending',
        'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
        'sync_status': 'pending',
        'created_at': now,
        'updated_at': now,
      });

      for (final item in items) {
        await txn.insert('local_sales_return_items', {
          'tenant_id': tenantId,
          'return_offline_uuid': uuid,
          'product_uuid': item.product['id'].toString(),
          'sku': (item.product['sku'] ?? '').toString(),
          'name': (item.product['name'] ?? 'Product').toString(),
          'unit': (item.product['unit'] ?? 'pcs').toString(),
          'quantity': item.quantity,
          'condition': item.condition,
          'reason': item.reason?.trim().isEmpty == true
              ? null
              : item.reason?.trim(),
        });
      }
    });

    return uuid;
  }

  Future<List<Map<String, dynamic>>> history(String tenantId) async {
    final rows = await db.db.query(
      'local_sales_returns',
      where: 'tenant_id=?',
      whereArgs: [tenantId],
      orderBy: 'returned_at DESC',
    );

    final result = <Map<String, dynamic>>[];

    for (final row in rows) {
      final entry = Map<String, dynamic>.from(row);
      entry['items'] = await items(tenantId, row['offline_uuid'].toString());
      result.add(entry);
    }

    return result;
  }

  Future<List<Map<String, dynamic>>> items(
    String tenantId,
    String returnUuid,
  ) async {
    final rows = await db.db.query(
      'local_sales_return_items',
      where: 'tenant_id=? AND return_offline_uuid=?',
      whereArgs: [tenantId, returnUuid],
      orderBy: 'id ASC',
    );

    return rows.map(Map<String, dynamic>.from).toList();
  }

  Future<int> pendingCount(String tenantId) async {
    final rows = await db.db.rawQuery(
      'SELECT COUNT(*) AS total FROM local_sales_returns '
      'WHERE tenant_id=? AND sync_status<>?',
      [tenantId, 'synced'],
    );

    return rows.first['total'] as int? ?? 0;
  }

  Future<ReturnSyncResult> syncPending(String tenantId) async {
    if (!await ConnectivityGate.instance.isOnline()) {
      return const ReturnSyncResult(synced: 0, failed: 0);
    }

    final rows = await db.db.query(
      'local_sales_returns',
      where: 'tenant_id=? AND sync_status IN (?,?,?)',
      whereArgs: [tenantId, 'pending', 'failed', 'blocked'],
      orderBy: 'returned_at ASC',
    );

    var synced = 0;
    var failed = 0;
    final dependencies = LocalDependencyGuard(db);

    for (final row in rows) {
      final offlineUuid = row['offline_uuid'].toString();
      final visitUuid = row['visit_uuid']?.toString();

      if (visitUuid != null &&
          visitUuid.isNotEmpty &&
          !await dependencies.visitReady(tenantId, visitUuid)) {
        continue;
      }

      if (!await retry.shouldAttempt(
        tenantId: tenantId,
        entityType: 'sales_return',
        entityUuid: offlineUuid,
      )) {
        continue;
      }

      try {
        final returnItems = await items(tenantId, offlineUuid);
        final response = Map<String, dynamic>.from(
          await api.post(
            'returns',
            data: {
              'offline_uuid': offlineUuid,
              'customer_id': row['customer_uuid'],
              if (visitUuid != null && visitUuid.isNotEmpty)
                'visit_id': visitUuid,
              if (row['order_uuid'] != null) 'order_id': row['order_uuid'],
              'returned_at': row['returned_at'],
              if (row['notes'] != null) 'notes': row['notes'],
              'items': returnItems
                  .map(
                    (item) => {
                      'product_id': item['product_uuid'],
                      'quantity': item['quantity'],
                      'condition': item['condition'],
                      if (item['reason'] != null) 'reason': item['reason'],
                    },
                  )
                  .toList(),
            },
          ) as Map,
        );

        await _applyServerReturn(tenantId, response);
        await retry.clear(
          tenantId: tenantId,
          entityType: 'sales_return',
          entityUuid: offlineUuid,
        );
        synced++;
      } catch (error) {
        final failure = await retry.recordFailure(
          tenantId: tenantId,
          entityType: 'sales_return',
          entityUuid: offlineUuid,
          error: error,
        );

        await db.db.update(
          'local_sales_returns',
          {
            'sync_status': failure.blocked ? 'blocked' : 'failed',
            'last_error': failure.message,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'tenant_id=? AND offline_uuid=?',
          whereArgs: [tenantId, offlineUuid],
        );
        failed++;
      }
    }

    return ReturnSyncResult(synced: synced, failed: failed);
  }

  Future<void> refreshHistory(String tenantId) async {
    if (!await ConnectivityGate.instance.isOnline()) return;

    final response = await api.get('returns/history');
    final data = response is Map<String, dynamic>
        ? response
        : Map<String, dynamic>.from(response as Map);
    final rows = (data['returns'] as List? ?? const []).whereType<Map>().map(
      Map<String, dynamic>.from,
    );

    for (final row in rows) {
      await _applyServerReturn(tenantId, row);
    }
  }

  Future<void> _applyServerReturn(
    String tenantId,
    Map<String, dynamic> server,
  ) async {
    final uuid = server['id']?.toString();
    if (uuid == null || uuid.isEmpty) return;

    final existing = await db.db.query(
      'local_sales_returns',
      where: 'tenant_id=? AND offline_uuid=?',
      whereArgs: [tenantId, uuid],
      limit: 1,
    );
    final now = DateTime.now().toUtc().toIso8601String();
    final values = <String, Object?>{
      'server_uuid': uuid,
      'return_number': server['return_number']?.toString(),
      'customer_uuid': server['customer_id']?.toString() ?? '',
      'customer_name': server['customer_name']?.toString() ?? 'Customer',
      'visit_uuid': server['visit_id']?.toString(),
      'order_uuid': server['order_id']?.toString(),
      'returned_at': server['returned_at']?.toString() ?? now,
      'status': server['status']?.toString() ?? 'pending',
      'notes': server['notes']?.toString(),
      'status_note': server['status_note']?.toString(),
      'sync_status': 'synced',
      'last_error': null,
      'updated_at': now,
    };

    await db.db.transaction((txn) async {
      if (existing.isEmpty) {
        await txn.insert('local_sales_returns', {
          'tenant_id': tenantId,
          'offline_uuid': uuid,
          'created_at': now,
          ...values,
        });
      } else {
        await txn.update(
          'local_sales_returns',
          values,
          where: 'tenant_id=? AND offline_uuid=?',
          whereArgs: [tenantId, uuid],
        );
      }

      final serverItems = (server['items'] as List? ?? const [])
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .toList();

      if (serverItems.isNotEmpty) {
        await txn.delete(
          'local_sales_return_items',
          where: 'tenant_id=? AND return_offline_uuid=?',
          whereArgs: [tenantId, uuid],
        );

        for (final item in serverItems) {
          await txn.insert('local_sales_return_items', {
            'tenant_id': tenantId,
            'return_offline_uuid': uuid,
            'product_uuid': item['product_id']?.toString() ?? '',
            'sku': item['sku']?.toString() ?? '',
            'name': item['name']?.toString() ?? 'Product',
            'unit': item['unit']?.toString() ?? 'pcs',
            'quantity': _number(item['quantity']),
            'condition': item['condition']?.toString() ?? 'resalable',
            'reason': item['reason']?.toString(),
          });
        }
      }
    });

    await retry.clear(
      tenantId: tenantId,
      entityType: 'sales_return',
      entityUuid: uuid,
    );
  }

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class ReturnDraftLine {
  const ReturnDraftLine({
    required this.product,
    required this.quantity,
    required this.condition,
    this.reason,
  });

  final Map<String, dynamic> product;
  final double quantity;
  final String condition;
  final String? reason;
}

class ReturnSyncResult {
  const ReturnSyncResult({required this.synced, required this.failed});

  final int synced;
  final int failed;
}
