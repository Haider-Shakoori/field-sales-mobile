import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../core/api/api_client.dart';
import '../../core/db/app_database.dart';
import '../master_data/master_data_repository.dart';

class SalesOperationsRepository {
  SalesOperationsRepository({
    required this.api,
    required this.db,
    required this.masterData,
  });

  final ApiClient api;
  final AppDatabase db;
  final MasterDataRepository masterData;

  Future<String> createOrder({
    required String customerUuid,
    String? visitUuid,
    required DateTime orderedAt,
    required List<Map<String, dynamic>> items,
    String currency = 'AFN',
    double discountAmount = 0,
    double cashAmount = 0,
    String? notes,
    int? priceListId,
  }) async {
    if (items.isEmpty) {
      throw StateError('Add at least one product.');
    }

    final uuid = const Uuid().v4();
    final now = DateTime.now().toUtc().toIso8601String();
    final normalized = <Map<String, dynamic>>[];
    var subtotal = 0.0;

    for (final item in items) {
      final productUuid = '${item['product_uuid']}';
      final quantity = double.tryParse('${item['quantity']}') ?? 0;
      if (quantity <= 0) throw StateError('Quantity must be greater than zero.');
      final price = item['unit_price'] == null
          ? await masterData.priceFor(
              productUuid,
              priceListId: priceListId,
              quantity: quantity,
            )
          : double.tryParse('${item['unit_price']}') ?? 0;
      final lineDiscount = double.tryParse('${item['discount_amount'] ?? 0}') ?? 0;
      final lineTotal = (quantity * price - lineDiscount).clamp(0, double.infinity);
      subtotal += lineTotal;
      normalized.add({
        'product_uuid': productUuid,
        'quantity': quantity,
        'unit_price': price,
        'discount_amount': lineDiscount,
        'line_total': lineTotal,
      });
    }

    final total = (subtotal - discountAmount).clamp(0, double.infinity);
    final cash = cashAmount.clamp(0, total);
    final credit = total - cash;

    await db.db.transaction((txn) async {
      await txn.insert('local_orders', {
        'offline_uuid': uuid,
        'customer_uuid': customerUuid,
        'visit_uuid': visitUuid,
        'ordered_at': orderedAt.toUtc().toIso8601String(),
        'currency': currency.toUpperCase(),
        'discount_amount': discountAmount,
        'cash_amount': cash,
        'subtotal': subtotal,
        'total_amount': total,
        'credit_amount': credit,
        'status': 'submitted',
        'notes': notes,
        'sync_status': 'pending',
        'created_at': now,
        'updated_at': now,
      });

      for (final item in normalized) {
        await txn.insert('local_order_items', {
          'order_uuid': uuid,
          ...item,
          'created_at': now,
        });
      }

      await txn.insert('sync_queue', {
        'entity_type': 'order',
        'entity_uuid': uuid,
        'action': 'create',
        'payload': jsonEncode({
          'offline_uuid': uuid,
          'customer_uuid': customerUuid,
          'visit_uuid': visitUuid,
          'ordered_at': orderedAt.toUtc().toIso8601String(),
          'currency': currency.toUpperCase(),
          'discount_amount': discountAmount,
          'cash_amount': cash,
          'notes': notes,
          'items': normalized
              .map((item) => {
                    'product_uuid': item['product_uuid'],
                    'quantity': item['quantity'],
                    'discount_amount': item['discount_amount'],
                  })
              .toList(),
        }),
        'priority': 50,
        'status': 'pending',
        'created_at': now,
        'updated_at': now,
      });
    });

    return uuid;
  }

  Future<String> createCollection({
    required String customerUuid,
    String? orderUuid,
    String? visitUuid,
    required double amount,
    String currency = 'AFN',
    required String paymentMethod,
    String? receiptNumber,
    String? manualReference,
    required DateTime collectedAt,
    double? latitude,
    double? longitude,
    double? accuracy,
    String? receiptPhotoPath,
    String? notes,
  }) async {
    if (amount <= 0) throw StateError('Collection amount must be greater than zero.');
    final uuid = const Uuid().v4();
    final now = DateTime.now().toUtc().toIso8601String();

    final payload = {
      'offline_uuid': uuid,
      'customer_uuid': customerUuid,
      'order_uuid': orderUuid,
      'visit_uuid': visitUuid,
      'amount': amount,
      'currency': currency.toUpperCase(),
      'payment_method': paymentMethod,
      'receipt_number': receiptNumber,
      'manual_reference': manualReference,
      'collected_at': collectedAt.toUtc().toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'receipt_photo_path': receiptPhotoPath,
      'notes': notes,
    };

    await db.db.transaction((txn) async {
      await txn.insert('local_collections', {
        ...payload,
        'sync_status': 'pending',
        'created_at': now,
        'updated_at': now,
      });
      await txn.insert('sync_queue', {
        'entity_type': 'collection',
        'entity_uuid': uuid,
        'action': 'create',
        'payload': jsonEncode(payload),
        'priority': 55,
        'status': 'pending',
        'created_at': now,
        'updated_at': now,
      });
    });

    return uuid;
  }

  Future<String> createExpense({
    required String category,
    required double amount,
    String currency = 'AFN',
    required DateTime spentAt,
    double? latitude,
    double? longitude,
    String? receiptPhotoPath,
    String? notes,
  }) async {
    if (amount <= 0) throw StateError('Expense amount must be greater than zero.');
    final uuid = const Uuid().v4();
    final now = DateTime.now().toUtc().toIso8601String();

    final payload = {
      'offline_uuid': uuid,
      'category': category,
      'amount': amount,
      'currency': currency.toUpperCase(),
      'spent_at': spentAt.toUtc().toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'receipt_photo_path': receiptPhotoPath,
      'notes': notes,
    };

    await db.db.transaction((txn) async {
      await txn.insert('local_expenses', {
        ...payload,
        'status': 'submitted',
        'sync_status': 'pending',
        'created_at': now,
        'updated_at': now,
      });
      await txn.insert('sync_queue', {
        'entity_type': 'expense',
        'entity_uuid': uuid,
        'action': 'create',
        'payload': jsonEncode(payload),
        'priority': 70,
        'status': 'pending',
        'created_at': now,
        'updated_at': now,
      });
    });

    return uuid;
  }

  Future<void> refreshTargets() async {
    final data = await api.get('targets/current');
    final items = (data as List).cast<dynamic>();
    final now = DateTime.now().toUtc().toIso8601String();

    await db.db.transaction((txn) async {
      await txn.delete('local_targets');
      for (final raw in items) {
        final item = Map<String, dynamic>.from(raw as Map);
        await txn.insert('local_targets', {
          'uuid': '${item['uuid']}',
          'payload': jsonEncode(item),
          'cached_at': now,
        });
      }
    });
  }

  Future<List<Map<String, dynamic>>> orders() =>
      db.db.query('local_orders', orderBy: 'ordered_at DESC');

  Future<List<Map<String, dynamic>>> collections() =>
      db.db.query('local_collections', orderBy: 'collected_at DESC');

  Future<List<Map<String, dynamic>>> expenses() =>
      db.db.query('local_expenses', orderBy: 'spent_at DESC');

  Future<List<Map<String, dynamic>>> targets() async {
    final rows = await db.db.query('local_targets');
    return rows
        .map((row) => Map<String, dynamic>.from(jsonDecode(row['payload'] as String) as Map))
        .toList();
  }

  Future<void> drain() async {
    final rows = await db.db.query(
      'sync_queue',
      where: 'entity_type IN (?,?,?) AND status IN (?,?)',
      whereArgs: ['order', 'collection', 'expense', 'pending', 'failed'],
      orderBy: 'priority ASC, id ASC',
    );

    for (final row in rows) {
      try {
        final entity = row['entity_type'] as String;
        final endpoint = switch (entity) {
          'order' => 'orders',
          'collection' => 'collections',
          'expense' => 'expenses',
          _ => throw StateError('Unsupported sync entity'),
        };

        final result = Map<String, dynamic>.from(
          await api.post(endpoint, data: jsonDecode(row['payload'] as String)),
        );

        await db.db.transaction((txn) async {
          await txn.update(
            'sync_queue',
            {
              'status': 'synced',
              'server_id': result['id'],
              'server_uuid': result['uuid'],
              'error_message': null,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            },
            where: 'id=?',
            whereArgs: [row['id']],
          );

          final table = switch (entity) {
            'order' => 'local_orders',
            'collection' => 'local_collections',
            'expense' => 'local_expenses',
            _ => '',
          };

          if (table.isNotEmpty) {
            await txn.update(
              table,
              {
                'server_id': result['id'],
                if (entity == 'order') 'server_uuid': result['uuid'],
                'sync_status': 'synced',
                'updated_at': DateTime.now().toUtc().toIso8601String(),
              },
              where: 'offline_uuid=?',
              whereArgs: [row['entity_uuid']],
            );
          }
        });
      } catch (error) {
        await db.db.update(
          'sync_queue',
          {
            'status': 'failed',
            'attempts': (row['attempts'] as int) + 1,
            'error_message': '$error',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'id=?',
          whereArgs: [row['id']],
        );
        break;
      }
    }
  }
}
