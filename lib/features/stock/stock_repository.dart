import 'package:uuid/uuid.dart';

import '../../core/api/api_client.dart';
import '../../core/db/app_database.dart';
import '../../core/sync/connectivity_gate.dart';
import '../../core/sync/sync_retry_store.dart';

class StockRepository {
  StockRepository({required this.api, required this.db})
    : retry = SyncRetryStore(db);

  final ApiClient api;
  final AppDatabase db;
  final SyncRetryStore retry;

  Future<bool> enabled(String tenantId) async {
    final value = await db.readSetting('stock.enabled.$tenantId');
    return value == true;
  }

  Future<List<Map<String, dynamic>>> list(String tenantId) async {
    final rows = await db.db.query(
      'local_salesman_stock',
      where: 'tenant_id=?',
      whereArgs: [tenantId],
      orderBy: 'name ASC',
    );

    return rows.map(Map<String, dynamic>.from).toList();
  }

  Future<void> refresh(String tenantId) async {
    if (!await ConnectivityGate.instance.isOnline()) return;

    final response = await api.get('stock/me');
    final body = response is Map<String, dynamic>
        ? response
        : Map<String, dynamic>.from(response as Map);
    final rows = body['stock'] is List
        ? List<dynamic>.from(body['stock'] as List)
        : const <dynamic>[];

    await db.setting('stock.enabled.$tenantId', body['enabled'] == true);

    await db.db.transaction((txn) async {
      await txn.delete(
        'local_salesman_stock',
        where: 'tenant_id=?',
        whereArgs: [tenantId],
      );

      for (final raw in rows) {
        if (raw is! Map) continue;
        final row = Map<String, dynamic>.from(raw);
        await txn.insert('local_salesman_stock', {
          'tenant_id': tenantId,
          'product_uuid': row['product_id'].toString(),
          'sku': (row['sku'] ?? '').toString(),
          'name': (row['name'] ?? 'Product').toString(),
          'unit': (row['unit'] ?? 'pcs').toString(),
          'sellable_qty': _number(row['sellable_qty']),
          'damaged_qty': _number(row['damaged_qty']),
          'updated_at':
              row['updated_at']?.toString() ??
              DateTime.now().toUtc().toIso8601String(),
        });
      }
    });
  }

  Future<double> availableForProduct(
    String tenantId,
    String productUuid,
  ) async {
    if (!await enabled(tenantId)) return double.infinity;

    final rows = await db.db.query(
      'local_salesman_stock',
      columns: ['sellable_qty'],
      where: 'tenant_id=? AND product_uuid=?',
      whereArgs: [tenantId, productUuid],
      limit: 1,
    );
    final sellable = rows.isEmpty ? 0.0 : _number(rows.first['sellable_qty']);

    final reserved = await db.db.rawQuery(
      'SELECT COALESCE(SUM(i.quantity),0) AS total '
      'FROM local_order_items i '
      'JOIN local_orders o '
      'ON o.tenant_id=i.tenant_id AND o.offline_uuid=i.order_offline_uuid '
      'WHERE i.tenant_id=? AND i.product_uuid=? AND o.status=?',
      [tenantId, productUuid, 'pending'],
    );

    return sellable - _number(reserved.first['total']);
  }

  Future<void> validateOrderLines(
    String tenantId,
    List<Map<String, dynamic>> lines,
  ) async {
    if (!await enabled(tenantId)) return;

    for (final line in lines) {
      final productUuid = line['product_id'].toString();
      final quantity = _number(line['quantity']);
      final available = await availableForProduct(tenantId, productUuid);

      if (quantity > available + 0.00001) {
        throw StateError(
          'Insufficient van stock for ${line['name'] ?? 'product'}. '
          'Available ${available.toStringAsFixed(4)}, '
          'requested ${quantity.toStringAsFixed(4)}.',
        );
      }
    }
  }

  Future<List<Map<String, dynamic>>> returns(String tenantId) async {
    final rows = await db.db.query(
      'local_sales_returns',
      where: 'tenant_id=?',
      whereArgs: [tenantId],
      orderBy: 'returned_at DESC',
    );
    return rows.map(Map<String, dynamic>.from).toList();
  }

  Future<String> createReturnOffline({
    required String tenantId,
    required Map<String, dynamic> customer,
    required List<Map<String, dynamic>> items,
    String? visitUuid,
    String? orderUuid,
    String? notes,
  }) async {
    if (items.isEmpty) throw StateError('Add at least one returned product.');

    final uuid = const Uuid().v4();
    final now = DateTime.now().toUtc().toIso8601String();

    await db.db.transaction((txn) async {
      await txn.insert('local_sales_returns', {
        'tenant_id': tenantId,
        'offline_uuid': uuid,
        'customer_uuid': customer['id'].toString(),
        'customer_name': (customer['name'] ?? 'Customer').toString(),
        'visit_uuid': visitUuid,
        'order_uuid': orderUuid,
        'returned_at': now,
        'status': 'pending',
        'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
        'sync_status': 'pending',
        'created_at': now,
        'updated_at': now,
      });

      for (final item in items) {
        final quantity = _number(item['quantity']);
        final condition = item['condition']?.toString() ?? '';

        if (quantity <= 0) {
          throw StateError('Return quantity must be greater than zero.');
        }
        if (condition != 'resalable' && condition != 'damaged') {
          throw StateError('Return condition must be resalable or damaged.');
        }

        await txn.insert('local_sales_return_items', {
          'tenant_id': tenantId,
          'return_offline_uuid': uuid,
          'product_uuid': item['product_id'].toString(),
          'product_sku': (item['sku'] ?? '').toString(),
          'product_name': (item['name'] ?? 'Product').toString(),
          'unit': (item['unit'] ?? 'pcs').toString(),
          'quantity': quantity,
          'condition': condition,
          'reason': item['reason']?.toString(),
        });
      }
    });

    return uuid;
  }

  Future<int> syncPending(String tenantId) async {
    if (!await ConnectivityGate.instance.isOnline()) return 0;

    final rows = await db.db.query(
      'local_sales_returns',
      where: 'tenant_id=? AND sync_status IN (?,?,?)',
      whereArgs: [tenantId, 'pending', 'failed', 'blocked'],
      orderBy: 'returned_at ASC',
    );

    var synced = 0;

    for (final row in rows) {
      final uuid = row['offline_uuid'].toString();

      if (!await retry.shouldAttempt(
        tenantId: tenantId,
        entityType: 'sales_return',
        entityUuid: uuid,
      )) {
        continue;
      }

      final items = await db.db.query(
        'local_sales_return_items',
        where: 'tenant_id=? AND return_offline_uuid=?',
        whereArgs: [tenantId, uuid],
        orderBy: 'id ASC',
      );

      try {
        final response = Map<String, dynamic>.from(
          await api.post(
            'returns',
            data: {
              'offline_uuid': uuid,
              'customer_id': row['customer_uuid'],
              if (row['visit_uuid'] != null) 'visit_id': row['visit_uuid'],
              if (row['order_uuid'] != null) 'order_id': row['order_uuid'],
              'returned_at': row['returned_at'],
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

        await _applyReturn(tenantId, response);
        await retry.clear(
          tenantId: tenantId,
          entityType: 'sales_return',
          entityUuid: uuid,
        );
        synced++;
      } catch (error) {
        final failure = await retry.recordFailure(
          tenantId: tenantId,
          entityType: 'sales_return',
          entityUuid: uuid,
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
          whereArgs: [tenantId, uuid],
        );
      }
    }

    return synced;
  }

  Future<void> refreshReturns(String tenantId) async {
    if (!await ConnectivityGate.instance.isOnline()) return;

    final response = await api.get('returns/history');
    final body = response is Map<String, dynamic>
        ? response
        : Map<String, dynamic>.from(response as Map);
    final rows = body['returns'] is List
        ? List<dynamic>.from(body['returns'] as List)
        : const <dynamic>[];

    for (final raw in rows) {
      if (raw is! Map) continue;
      await _applyReturn(tenantId, Map<String, dynamic>.from(raw));
    }
  }

  Future<void> _applyReturn(
    String tenantId,
    Map<String, dynamic> server,
  ) async {
    final uuid = server['id']?.toString();
    if (uuid == null || uuid.isEmpty) return;

    final now = DateTime.now().toUtc().toIso8601String();
    final existing = await db.db.query(
      'local_sales_returns',
      where: 'tenant_id=? AND offline_uuid=?',
      whereArgs: [tenantId, uuid],
      limit: 1,
    );

    final values = {
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

      final items = (server['items'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

      if (items.isNotEmpty) {
        await txn.delete(
          'local_sales_return_items',
          where: 'tenant_id=? AND return_offline_uuid=?',
          whereArgs: [tenantId, uuid],
        );

        for (final item in items) {
          await txn.insert('local_sales_return_items', {
            'tenant_id': tenantId,
            'return_offline_uuid': uuid,
            'server_uuid': item['id']?.toString(),
            'product_uuid': item['product_id']?.toString() ?? '',
            'product_sku': item['sku']?.toString() ?? '',
            'product_name': item['name']?.toString() ?? 'Product',
            'unit': item['unit']?.toString() ?? 'pcs',
            'quantity': _number(item['quantity']),
            'condition': item['condition']?.toString() ?? 'resalable',
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
}
