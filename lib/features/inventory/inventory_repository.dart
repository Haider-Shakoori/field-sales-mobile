import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../core/api/api_client.dart';
import '../../core/db/app_database.dart';
import '../../core/sync/connectivity_gate.dart';
import '../../core/sync/local_dependency_guard.dart';
import '../../core/sync/sync_retry_store.dart';

class InventoryRepository {
  InventoryRepository({required this.api, required this.db})
    : retry = SyncRetryStore(db),
      dependencies = LocalDependencyGuard(db);

  final ApiClient api;
  final AppDatabase db;
  final SyncRetryStore retry;
  final LocalDependencyGuard dependencies;

  Future<bool> isEnabled(String tenantId) async {
    final rows = await db.db.query(
      'local_van_stock_meta',
      columns: ['enabled'],
      where: 'tenant_id=?',
      whereArgs: [tenantId],
      limit: 1,
    );

    return rows.isNotEmpty && rows.first['enabled'] == 1;
  }

  Future<List<Map<String, dynamic>>> stock(String tenantId) async {
    final rows = await db.db.query(
      'local_van_stock',
      where: 'tenant_id=?',
      whereArgs: [tenantId],
      orderBy: 'name ASC',
    );

    final result = <Map<String, dynamic>>[];

    for (final row in rows) {
      final item = Map<String, dynamic>.from(row);
      item['local_available_quantity'] = await localAvailable(
        tenantId,
        row['product_uuid'].toString(),
      );
      result.add(item);
    }

    return result;
  }

  Future<double?> localAvailable(String tenantId, String productUuid) async {
    if (!await isEnabled(tenantId)) return null;

    final rows = await db.db.query(
      'local_van_stock',
      columns: ['available_quantity'],
      where: 'tenant_id=? AND product_uuid=?',
      whereArgs: [tenantId, productUuid],
      limit: 1,
    );

    if (rows.isEmpty) return 0;

    final cached = _number(rows.first['available_quantity']);
    final pending = await db.db.rawQuery(
      'SELECT COALESCE(SUM(i.quantity),0) AS total '
      'FROM local_order_items i '
      'JOIN local_orders o '
      'ON o.tenant_id=i.tenant_id '
      'AND o.offline_uuid=i.order_offline_uuid '
      'WHERE i.tenant_id=? AND i.product_uuid=? '
      'AND o.sync_status<>?',
      [tenantId, productUuid, 'synced'],
    );

    return _round4(cached - _number(pending.first['total']));
  }

  Future<void> ensureOrderAvailability(
    String tenantId,
    List<Map<String, dynamic>> lines,
  ) async {
    if (!await isEnabled(tenantId)) return;

    for (final line in lines) {
      final product = Map<String, dynamic>.from(line['product'] as Map);
      final productUuid = product['id']?.toString() ?? '';
      final requested = _number(line['quantity']);
      final available = await localAvailable(tenantId, productUuid) ?? 0;

      if (available + 0.0001 < requested) {
        throw StateError(
          'Insufficient van stock for ${product['name'] ?? 'product'}. '
          'Available ${available.toStringAsFixed(4)} '
          '${product['unit'] ?? ''}, requested '
          '${requested.toStringAsFixed(4)} ${product['unit'] ?? ''}.',
        );
      }
    }
  }

  Future<void> refreshStock(String tenantId) async {
    if (!await ConnectivityGate.instance.isOnline()) return;

    final raw = await api.get('van-stock');
    final payload = raw is Map<String, dynamic>
        ? raw
        : Map<String, dynamic>.from(raw as Map);
    final enabled = payload['enabled'] == true;
    final items = (payload['items'] as List? ?? const [])
        .whereType<Map>()
        .map(Map<String, dynamic>.from)
        .toList();
    final now = DateTime.now().toUtc().toIso8601String();

    await db.db.transaction((txn) async {
      await txn.insert('local_van_stock_meta', {
        'tenant_id': tenantId,
        'enabled': enabled ? 1 : 0,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      await txn.delete(
        'local_van_stock',
        where: 'tenant_id=?',
        whereArgs: [tenantId],
      );

      for (final item in items) {
        await txn.insert('local_van_stock', {
          'tenant_id': tenantId,
          'product_uuid': item['product_id'].toString(),
          'sku': (item['sku'] ?? '').toString(),
          'name': (item['name'] ?? 'Product').toString(),
          'unit': (item['unit'] ?? 'pcs').toString(),
          'sellable_quantity': _number(item['sellable_quantity']),
          'reserved_quantity': _number(item['reserved_quantity']),
          'available_quantity': _number(item['available_quantity']),
          'damaged_quantity': _number(item['damaged_quantity']),
          'server_updated_at': item['updated_at']?.toString(),
          'cached_at': now,
        });
      }
    });
  }

  Future<List<Map<String, dynamic>>> returns(String tenantId) async {
    final rows = await db.db.query(
      'local_customer_returns',
      where: 'tenant_id=?',
      whereArgs: [tenantId],
      orderBy: 'returned_at DESC',
    );

    return rows.map(Map<String, dynamic>.from).toList();
  }

  Future<List<Map<String, dynamic>>> returnItems(
    String tenantId,
    String returnUuid,
  ) async {
    final rows = await db.db.query(
      'local_customer_return_items',
      where: 'tenant_id=? AND return_offline_uuid=?',
      whereArgs: [tenantId, returnUuid],
      orderBy: 'id ASC',
    );

    return rows.map(Map<String, dynamic>.from).toList();
  }

  Future<int> pendingReturnCount(String tenantId) async {
    final rows = await db.db.rawQuery(
      'SELECT COUNT(*) AS total FROM local_customer_returns '
      'WHERE tenant_id=? AND sync_status<>?',
      [tenantId, 'synced'],
    );

    return rows.first['total'] as int? ?? 0;
  }

  Future<String> createReturnOffline({
    required String tenantId,
    required Map<String, dynamic> customer,
    required DateTime returnedAt,
    required String reason,
    required List<ReturnDraftLine> lines,
    String? visitUuid,
    Map<String, dynamic>? order,
    String? notes,
  }) async {
    if (lines.isEmpty) {
      throw StateError('Add at least one returned product.');
    }

    final grouped = <String, ReturnDraftLine>{};

    for (final line in lines) {
      if (line.quantity <= 0) {
        throw StateError('Return quantity must be greater than zero.');
      }
      if (line.condition != 'sellable' && line.condition != 'damaged') {
        throw StateError('Return condition must be sellable or damaged.');
      }

      final productUuid = line.product['id']?.toString() ?? '';
      if (productUuid.isEmpty) {
        throw StateError('Returned product is missing an ID.');
      }

      final key = '$productUuid|${line.condition}';
      final existing = grouped[key];

      if (existing == null) {
        grouped[key] = line;
      } else {
        grouped[key] = ReturnDraftLine(
          product: existing.product,
          quantity: _round4(existing.quantity + line.quantity),
          condition: existing.condition,
          reason: [existing.reason, line.reason]
              .where((value) => value != null && value!.trim().isNotEmpty)
              .join('; '),
        );
      }
    }

    if (order != null) {
      final orderUuid =
          order['offline_uuid']?.toString() ?? order['id']?.toString() ?? '';
      if (orderUuid.isEmpty ||
          order['status']?.toString() != 'approved' ||
          order['sync_status']?.toString() != 'synced') {
        throw StateError(
          'Returns can only link to an approved synchronized order.',
        );
      }

      final orderItems = await db.db.query(
        'local_order_items',
        where: 'tenant_id=? AND order_offline_uuid=?',
        whereArgs: [tenantId, orderUuid],
      );

      final orderedByProduct = <String, double>{};
      for (final item in orderItems) {
        final productUuid = item['product_uuid'].toString();
        orderedByProduct[productUuid] =
            (orderedByProduct[productUuid] ?? 0) + _number(item['quantity']);
      }

      final priorRows = await db.db.rawQuery(
        'SELECT i.product_uuid, COALESCE(SUM(i.quantity),0) AS total '
        'FROM local_customer_return_items i '
        'JOIN local_customer_returns r '
        'ON r.tenant_id=i.tenant_id '
        'AND r.offline_uuid=i.return_offline_uuid '
        'WHERE r.tenant_id=? AND r.order_uuid=? '
        'AND r.status IN (?,?) '
        'GROUP BY i.product_uuid',
        [tenantId, orderUuid, 'pending', 'approved'],
      );
      final returnedByProduct = <String, double>{
        for (final row in priorRows)
          row['product_uuid'].toString(): _number(row['total']),
      };

      final requestedByProduct = <String, double>{};
      for (final line in grouped.values) {
        final productUuid = line.product['id'].toString();
        requestedByProduct[productUuid] =
            (requestedByProduct[productUuid] ?? 0) + line.quantity;
      }

      for (final entry in requestedByProduct.entries) {
        final remaining = _round4(
          (orderedByProduct[entry.key] ?? 0) -
              (returnedByProduct[entry.key] ?? 0),
        );

        if (remaining + 0.0001 < entry.value) {
          final product = grouped.values.firstWhere(
            (line) => line.product['id'].toString() == entry.key,
          );
          throw StateError(
            'Only ${remaining.toStringAsFixed(4)} '
            '${product.product['unit'] ?? ''} of '
            '${product.product['name'] ?? 'product'} remains returnable.',
          );
        }
      }
    }

    final uuid = const Uuid().v4();
    final now = DateTime.now().toUtc().toIso8601String();
    final orderUuid = order == null
        ? null
        : order['offline_uuid']?.toString() ?? order['id']?.toString();

    await db.db.transaction((txn) async {
      await txn.insert('local_customer_returns', {
        'tenant_id': tenantId,
        'offline_uuid': uuid,
        'customer_uuid': customer['id'].toString(),
        'customer_name': (customer['name'] ?? 'Customer').toString(),
        'visit_uuid': visitUuid,
        'order_uuid': orderUuid,
        'order_number': order?['order_number']?.toString(),
        'returned_at': returnedAt.toUtc().toIso8601String(),
        'status': 'pending',
        'reason': reason.trim(),
        'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
        'sync_status': 'pending',
        'created_at': now,
        'updated_at': now,
      });

      for (final line in grouped.values) {
        await txn.insert('local_customer_return_items', {
          'tenant_id': tenantId,
          'return_offline_uuid': uuid,
          'product_uuid': line.product['id'].toString(),
          'product_sku': (line.product['sku'] ?? '').toString(),
          'product_name': (line.product['name'] ?? 'Product').toString(),
          'unit': (line.product['unit'] ?? 'pcs').toString(),
          'quantity': _round4(line.quantity),
          'condition': line.condition,
          'reason': line.reason?.trim().isEmpty == true
              ? null
              : line.reason?.trim(),
        });
      }
    });

    return uuid;
  }

  Future<InventorySyncResult> syncPendingReturns(String tenantId) async {
    if (!await ConnectivityGate.instance.isOnline()) {
      return const InventorySyncResult(synced: 0, failed: 0);
    }

    final rows = await db.db.query(
      'local_customer_returns',
      where: 'tenant_id=? AND sync_status IN (?,?,?)',
      whereArgs: [tenantId, 'pending', 'failed', 'blocked'],
      orderBy: 'returned_at ASC',
    );

    var synced = 0;
    var failed = 0;

    for (final row in rows) {
      final uuid = row['offline_uuid'].toString();

      if (!await dependencies.customerReady(
        tenantId,
        row['customer_uuid'].toString(),
      )) {
        continue;
      }

      final visitUuid = row['visit_uuid']?.toString();
      if (visitUuid != null &&
          visitUuid.isNotEmpty &&
          !await dependencies.visitReady(tenantId, visitUuid)) {
        continue;
      }

      final orderUuid = row['order_uuid']?.toString();
      if (orderUuid != null && orderUuid.isNotEmpty) {
        final orderRows = await db.db.query(
          'local_orders',
          columns: ['sync_status', 'status'],
          where: 'tenant_id=? AND offline_uuid=?',
          whereArgs: [tenantId, orderUuid],
          limit: 1,
        );

        if (orderRows.isEmpty ||
            orderRows.first['sync_status'] != 'synced' ||
            orderRows.first['status'] != 'approved') {
          continue;
        }
      }

      if (!await retry.shouldAttempt(
        tenantId: tenantId,
        entityType: 'customer_return',
        entityUuid: uuid,
      )) {
        continue;
      }

      final items = await returnItems(tenantId, uuid);

      try {
        final response = Map<String, dynamic>.from(
          await api.post(
            'returns',
            data: {
              'offline_uuid': uuid,
              'customer_id': row['customer_uuid'],
              if (visitUuid != null && visitUuid.isNotEmpty)
                'visit_id': visitUuid,
              if (orderUuid != null && orderUuid.isNotEmpty)
                'order_id': orderUuid,
              'returned_at': row['returned_at'],
              'reason': row['reason'],
              if (row['notes'] != null) 'notes': row['notes'],
              'items': items
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
          entityType: 'customer_return',
          entityUuid: uuid,
        );
        synced++;
      } catch (error) {
        final failure = await retry.recordFailure(
          tenantId: tenantId,
          entityType: 'customer_return',
          entityUuid: uuid,
          error: error,
        );
        await db.db.update(
          'local_customer_returns',
          {
            'sync_status': failure.blocked ? 'blocked' : 'failed',
            'last_error': failure.message,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'tenant_id=? AND offline_uuid=?',
          whereArgs: [tenantId, uuid],
        );
        failed++;
      }
    }

    return InventorySyncResult(synced: synced, failed: failed);
  }

  Future<void> refreshReturnHistory(String tenantId) async {
    if (!await ConnectivityGate.instance.isOnline()) return;

    final data = await api.get('returns/history', query: {'per_page': 100});
    final rows = (data as List? ?? const []).whereType<Map>().map(
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
      'local_customer_returns',
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
      'order_number': server['order_number']?.toString(),
      'returned_at': server['returned_at']?.toString() ?? now,
      'status': server['status']?.toString() ?? 'pending',
      'reason': server['reason']?.toString() ?? '',
      'notes': server['notes']?.toString(),
      'status_note': server['status_note']?.toString(),
      'sync_status': 'synced',
      'last_error': null,
      'updated_at': now,
    };

    await db.db.transaction((txn) async {
      if (existing.isEmpty) {
        await txn.insert('local_customer_returns', {
          'tenant_id': tenantId,
          'offline_uuid': uuid,
          'created_at': now,
          ...values,
        });
      } else {
        await txn.update(
          'local_customer_returns',
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
          'local_customer_return_items',
          where: 'tenant_id=? AND return_offline_uuid=?',
          whereArgs: [tenantId, uuid],
        );

        for (final item in serverItems) {
          await txn.insert('local_customer_return_items', {
            'tenant_id': tenantId,
            'return_offline_uuid': uuid,
            'server_uuid': item['id']?.toString(),
            'product_uuid': item['product_id']?.toString() ?? '',
            'product_sku': item['sku']?.toString() ?? '',
            'product_name': item['name']?.toString() ?? 'Product',
            'unit': item['unit']?.toString() ?? 'pcs',
            'quantity': _number(item['quantity']),
            'condition': item['condition']?.toString() ?? 'sellable',
            'reason': item['reason']?.toString(),
          });
        }
      }
    });
  }

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _round4(double value) => (value * 10000).round() / 10000;
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

class InventorySyncResult {
  const InventorySyncResult({required this.synced, required this.failed});

  final int synced;
  final int failed;
}
