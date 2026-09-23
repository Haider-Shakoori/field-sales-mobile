import 'package:uuid/uuid.dart';

import '../../core/api/api_client.dart';
import '../../core/db/app_database.dart';
import '../../core/sync/connectivity_gate.dart';
import '../../core/sync/local_dependency_guard.dart';
import '../../core/sync/sync_retry_store.dart';
import '../master_data/master_data_repository.dart';

class OrderRepository {
  OrderRepository({
    required this.api,
    required this.db,
    required this.masterData,
  }) : retry = SyncRetryStore(db),
       dependencies = LocalDependencyGuard(db);

  final ApiClient api;
  final AppDatabase db;
  final MasterDataRepository masterData;
  final SyncRetryStore retry;
  final LocalDependencyGuard dependencies;

  Future<List<Map<String, dynamic>>> list(String tenantId) async {
    final rows = await db.db.query(
      'local_orders',
      where: 'tenant_id=?',
      whereArgs: [tenantId],
      orderBy: 'ordered_at DESC',
    );

    return rows.map(Map<String, dynamic>.from).toList();
  }

  Future<List<Map<String, dynamic>>> items(
    String tenantId,
    String orderOfflineUuid,
  ) async {
    final rows = await db.db.query(
      'local_order_items',
      where: 'tenant_id=? AND order_offline_uuid=?',
      whereArgs: [tenantId, orderOfflineUuid],
      orderBy: 'id ASC',
    );

    return rows.map(Map<String, dynamic>.from).toList();
  }

  Future<int> pendingCount(String tenantId) async {
    final rows = await db.db.rawQuery(
      'SELECT COUNT(*) AS total FROM local_orders '
      'WHERE tenant_id=? AND sync_status<>?',
      [tenantId, 'synced'],
    );

    return rows.first['total'] as int? ?? 0;
  }

  Future<OrderPreview> preview({
    required String tenantId,
    required Map<String, dynamic> customer,
    required DateTime orderedAt,
    required List<OrderDraftLine> lines,
  }) async {
    if (lines.isEmpty) {
      throw StateError('Add at least one product.');
    }

    final stockEnabled =
        await db.readSetting('salesman_stock_enabled:$tenantId') == true;
    final priceLists = await masterData.list('price_lists', tenantId);
    final priceItems = await masterData.list('price_list_items', tenantId);
    final customerPriceListId = customer['price_list_id']?.toString();
    final orderDate = orderedAt.toLocal().toIso8601String().substring(0, 10);

    Map<String, dynamic>? priceList;
    if (customerPriceListId != null && customerPriceListId.isNotEmpty) {
      for (final row in priceLists) {
        if (row['id']?.toString() != customerPriceListId) continue;
        if (row['is_active'] != true) continue;

        final from = row['effective_from']?.toString();
        final to = row['effective_to']?.toString();
        if (from != null && from.isNotEmpty && orderDate.compareTo(from) < 0) {
          continue;
        }
        if (to != null && to.isNotEmpty && orderDate.compareTo(to) > 0) {
          continue;
        }

        priceList = row;
        break;
      }
    }

    var subtotal = 0.0;
    var discountTotal = 0.0;
    String? currency;
    final priced = <OrderPricedLine>[];
    final productIds = <String>{};

    for (final line in lines) {
      if (line.quantity <= 0) {
        throw StateError('Quantity must be greater than zero.');
      }
      if (line.discountPercent < 0 || line.discountPercent > 100) {
        throw StateError('Discount must be between 0 and 100.');
      }

      final productId = line.product['id']?.toString() ?? '';
      if (productId.isEmpty) {
        throw StateError('Selected product is missing an ID.');
      }
      if (!productIds.add(productId)) {
        throw StateError('A product can appear only once in an order.');
      }

      if (stockEnabled) {
        final available = await _availableStock(tenantId, productId);
        if (line.quantity > available + 0.0001) {
          final name = (line.product['name'] ?? 'Product').toString();
          throw StateError(
            name +
                ' exceeds available van stock. Available: ' +
                available.toStringAsFixed(2) +
                '.',
          );
        }
      }

      var unitPrice = _number(line.product['base_price']);
      var lineCurrency = line.product['currency']?.toString() ?? 'AFN';

      if (priceList != null) {
        Map<String, dynamic>? bestTier;
        var bestQuantity = -1.0;

        for (final tier in priceItems) {
          if (tier['price_list_id']?.toString() !=
              priceList['id']?.toString()) {
            continue;
          }
          if (tier['product_id']?.toString() != productId) continue;

          final minQuantity = _number(tier['min_quantity']);
          if (minQuantity <= line.quantity && minQuantity > bestQuantity) {
            bestTier = tier;
            bestQuantity = minQuantity;
          }
        }

        if (bestTier != null) {
          unitPrice = _number(bestTier['price']);
          lineCurrency = priceList['currency']?.toString() ?? lineCurrency;
        }
      }

      if (currency != null && currency != lineCurrency) {
        throw StateError('All products in an order must use one currency.');
      }
      currency ??= lineCurrency;

      final gross = _round4(line.quantity * unitPrice);
      final discount = _round4(gross * (line.discountPercent / 100));
      final total = _round4(gross - discount);

      subtotal = _round4(subtotal + gross);
      discountTotal = _round4(discountTotal + discount);

      priced.add(
        OrderPricedLine(
          product: line.product,
          quantity: _round4(line.quantity),
          unitPrice: _round4(unitPrice),
          discountPercent: _round4(line.discountPercent),
          discountAmount: discount,
          lineTotal: total,
        ),
      );
    }

    return OrderPreview(
      currency: currency ?? 'AFN',
      subtotal: subtotal,
      discountTotal: discountTotal,
      grandTotal: _round4(subtotal - discountTotal),
      lines: priced,
    );
  }

  Future<String> createOffline({
    required String tenantId,
    required Map<String, dynamic> customer,
    required DateTime orderedAt,
    required String paymentType,
    required List<OrderDraftLine> lines,
    String? visitUuid,
    String? notes,
  }) async {
    final previewResult = await preview(
      tenantId: tenantId,
      customer: customer,
      orderedAt: orderedAt,
      lines: lines,
    );

    final uuid = const Uuid().v4();
    final now = DateTime.now().toUtc().toIso8601String();

    await db.db.transaction((txn) async {
      await txn.insert('local_orders', {
        'tenant_id': tenantId,
        'offline_uuid': uuid,
        'customer_uuid': customer['id'].toString(),
        'customer_name': (customer['name'] ?? 'Customer').toString(),
        'visit_uuid': visitUuid,
        'ordered_at': orderedAt.toUtc().toIso8601String(),
        'payment_type': paymentType,
        'status': 'pending',
        'currency': previewResult.currency,
        'subtotal': previewResult.subtotal,
        'discount_total': previewResult.discountTotal,
        'grand_total': previewResult.grandTotal,
        'client_estimated_total': previewResult.grandTotal,
        'pricing_adjusted': 0,
        'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
        'sync_status': 'pending',
        'created_at': now,
        'updated_at': now,
      });

      for (final line in previewResult.lines) {
        await txn.insert('local_order_items', {
          'tenant_id': tenantId,
          'order_offline_uuid': uuid,
          'product_uuid': line.product['id'].toString(),
          'product_sku': (line.product['sku'] ?? '').toString(),
          'product_name': (line.product['name'] ?? 'Product').toString(),
          'unit': (line.product['unit'] ?? 'pcs').toString(),
          'quantity': line.quantity,
          'unit_price': line.unitPrice,
          'discount_percent': line.discountPercent,
          'discount_amount': line.discountAmount,
          'line_total': line.lineTotal,
        });
      }
    });

    return uuid;
  }

  Future<OrderSyncResult> syncPending(String tenantId) async {
    if (!await ConnectivityGate.instance.isOnline()) {
      return const OrderSyncResult(synced: 0, failed: 0);
    }

    final rows = await db.db.query(
      'local_orders',
      where: 'tenant_id=? AND sync_status IN (?,?,?)',
      whereArgs: [tenantId, 'pending', 'failed', 'blocked'],
      orderBy: 'ordered_at ASC',
    );

    var synced = 0;
    var failed = 0;

    for (final order in rows) {
      final offlineUuid = order['offline_uuid'].toString();
      final customerUuid = order['customer_uuid'].toString();

      if (!await dependencies.customerReady(tenantId, customerUuid)) {
        continue;
      }

      final visitUuid = order['visit_uuid']?.toString();
      if (visitUuid != null &&
          visitUuid.isNotEmpty &&
          !await dependencies.visitReady(tenantId, visitUuid)) {
        continue;
      }

      if (!await retry.shouldAttempt(
        tenantId: tenantId,
        entityType: 'order',
        entityUuid: offlineUuid,
      )) {
        continue;
      }

      final orderItems = await items(tenantId, offlineUuid);

      try {
        final response = Map<String, dynamic>.from(
          await api.post(
            'orders',
            data: {
              'offline_uuid': offlineUuid,
              'customer_id': order['customer_uuid'],
              if (order['visit_uuid'] != null) 'visit_id': order['visit_uuid'],
              'ordered_at': order['ordered_at'],
              'payment_type': order['payment_type'],
              'client_estimated_total': order['client_estimated_total'],
              if (order['notes'] != null) 'notes': order['notes'],
              'items': orderItems
                  .map(
                    (item) => {
                      'product_id': item['product_uuid'],
                      'quantity': item['quantity'],
                      'discount_percent': item['discount_percent'],
                    },
                  )
                  .toList(),
            },
          ) as Map,
        );

        await _applyServerOrder(tenantId, response);
        await retry.clear(
          tenantId: tenantId,
          entityType: 'order',
          entityUuid: offlineUuid,
        );
        synced++;
      } catch (error) {
        final failure = await retry.recordFailure(
          tenantId: tenantId,
          entityType: 'order',
          entityUuid: offlineUuid,
          error: error,
        );
        await db.db.update(
          'local_orders',
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

    return OrderSyncResult(synced: synced, failed: failed);
  }

  Future<void> refreshServerHistory(String tenantId) async {
    if (!await ConnectivityGate.instance.isOnline()) {
      return;
    }

    final data = await api.get('orders/history', query: {'per_page': 100});

    final rows = (data as List? ?? const []).whereType<Map>().map(
      (row) => Map<String, dynamic>.from(row),
    );

    for (final row in rows) {
      await _applyServerOrder(tenantId, row);
    }
  }

  Future<void> _applyServerOrder(
    String tenantId,
    Map<String, dynamic> server,
  ) async {
    final uuid = server['id']?.toString();
    if (uuid == null || uuid.isEmpty) return;

    final existing = await db.db.query(
      'local_orders',
      where: 'tenant_id=? AND offline_uuid=?',
      whereArgs: [tenantId, uuid],
      limit: 1,
    );

    final now = DateTime.now().toUtc().toIso8601String();
    final values = <String, Object?>{
      'server_uuid': uuid,
      'order_number': server['order_number']?.toString(),
      'customer_uuid': server['customer_id']?.toString() ?? '',
      'customer_name': server['customer_name']?.toString() ?? 'Customer',
      'visit_uuid': server['visit_id']?.toString(),
      'ordered_at': server['ordered_at']?.toString() ?? now,
      'payment_type': server['payment_type']?.toString() ?? 'cash',
      'status': server['status']?.toString() ?? 'pending',
      'currency': server['currency']?.toString() ?? 'AFN',
      'subtotal': _number(server['subtotal']),
      'discount_total': _number(server['discount_total']),
      'grand_total': _number(server['grand_total']),
      'client_estimated_total': _number(
        server['client_estimated_total'] ?? server['grand_total'],
      ),
      'pricing_adjusted': server['pricing_adjusted'] == true ? 1 : 0,
      'notes': server['notes']?.toString(),
      'status_note': server['status_note']?.toString(),
      'status_changed_at': server['status_changed_at']?.toString(),
      'sync_status': 'synced',
      'last_error': null,
      'updated_at': now,
    };

    await db.db.transaction((txn) async {
      if (existing.isEmpty) {
        await txn.insert('local_orders', {
          'tenant_id': tenantId,
          'offline_uuid': uuid,
          'created_at': now,
          ...values,
        });
      } else {
        await txn.update(
          'local_orders',
          values,
          where: 'tenant_id=? AND offline_uuid=?',
          whereArgs: [tenantId, uuid],
        );
      }

      final serverItems = (server['items'] as List? ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

      if (serverItems.isNotEmpty) {
        await txn.delete(
          'local_order_items',
          where: 'tenant_id=? AND order_offline_uuid=?',
          whereArgs: [tenantId, uuid],
        );

        for (final item in serverItems) {
          await txn.insert('local_order_items', {
            'tenant_id': tenantId,
            'order_offline_uuid': uuid,
            'server_uuid': item['id']?.toString(),
            'product_uuid': item['product_id']?.toString() ?? '',
            'product_sku': item['sku']?.toString() ?? '',
            'product_name': item['name']?.toString() ?? 'Product',
            'unit': item['unit']?.toString() ?? 'pcs',
            'quantity': _number(item['quantity']),
            'unit_price': _number(item['unit_price']),
            'discount_percent': _number(item['discount_percent']),
            'discount_amount': _number(item['discount_amount']),
            'line_total': _number(item['line_total']),
          });
        }
      }
    });

    await retry.clear(
      tenantId: tenantId,
      entityType: 'order',
      entityUuid: uuid,
    );
  }

  Future<double> _availableStock(
    String tenantId,
    String productUuid,
  ) async {
    final balanceRows = await db.db.query(
      'local_stock_balances',
      columns: ['sellable_qty'],
      where: 'tenant_id=? AND product_uuid=?',
      whereArgs: [tenantId, productUuid],
      limit: 1,
    );
    var available = balanceRows.isEmpty
        ? 0.0
        : _number(balanceRows.first['sellable_qty']);

    final reservedRows = await db.db.rawQuery(
      'SELECT COALESCE(SUM(i.quantity),0) AS total '
      'FROM local_order_items i '
      'JOIN local_orders o '
      'ON o.tenant_id=i.tenant_id '
      'AND o.offline_uuid=i.order_offline_uuid '
      'WHERE i.tenant_id=? AND i.product_uuid=? '
      'AND o.status NOT IN ("rejected","cancelled") '
      'AND o.sync_status<>"synced"',
      [tenantId, productUuid],
    );
    available -= _number(reservedRows.first['total']);

    return available < 0 ? 0 : available;
  }

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _round4(double value) => (value * 10000).round() / 10000;
}

class OrderDraftLine {
  const OrderDraftLine({
    required this.product,
    required this.quantity,
    required this.discountPercent,
  });

  final Map<String, dynamic> product;
  final double quantity;
  final double discountPercent;
}

class OrderPricedLine {
  const OrderPricedLine({
    required this.product,
    required this.quantity,
    required this.unitPrice,
    required this.discountPercent,
    required this.discountAmount,
    required this.lineTotal,
  });

  final Map<String, dynamic> product;
  final double quantity;
  final double unitPrice;
  final double discountPercent;
  final double discountAmount;
  final double lineTotal;
}

class OrderPreview {
  const OrderPreview({
    required this.currency,
    required this.subtotal,
    required this.discountTotal,
    required this.grandTotal,
    required this.lines,
  });

  final String currency;
  final double subtotal;
  final double discountTotal;
  final double grandTotal;
  final List<OrderPricedLine> lines;
}

class OrderSyncResult {
  const OrderSyncResult({required this.synced, required this.failed});

  final int synced;
  final int failed;
}
