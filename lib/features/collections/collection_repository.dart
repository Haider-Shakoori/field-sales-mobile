import 'package:uuid/uuid.dart';

import '../../core/api/api_client.dart';
import '../../core/db/app_database.dart';
import '../../core/sync/local_dependency_guard.dart';
import '../../core/sync/sync_retry_store.dart';

class CollectionRepository {
  CollectionRepository({required this.api, required this.db})
    : retry = SyncRetryStore(db);

  final ApiClient api;
  final AppDatabase db;
  final SyncRetryStore retry;

  Future<List<Map<String, dynamic>>> list(String tenantId) async {
    final rows = await db.db.query(
      'local_collections',
      where: 'tenant_id=?',
      whereArgs: [tenantId],
      orderBy: 'collected_at DESC',
    );

    return rows.map(Map<String, dynamic>.from).toList();
  }

  Future<List<Map<String, dynamic>>> balances(String tenantId) async {
    final rows = await db.db.query(
      'local_customer_balances',
      where: 'tenant_id=?',
      whereArgs: [tenantId],
      orderBy: 'customer_name ASC, currency ASC',
    );

    return rows.map(Map<String, dynamic>.from).toList();
  }

  Future<List<Map<String, dynamic>>> balancesForCustomer(
    String tenantId,
    String customerUuid,
  ) async {
    final rows = await db.db.query(
      'local_customer_balances',
      where: 'tenant_id=? AND customer_uuid=?',
      whereArgs: [tenantId, customerUuid],
      orderBy: 'currency ASC',
    );

    return rows.map(Map<String, dynamic>.from).toList();
  }

  Future<int> pendingCount(String tenantId) async {
    final rows = await db.db.rawQuery(
      'SELECT COUNT(*) AS total FROM local_collections '
      'WHERE tenant_id=? AND sync_status<>?',
      [tenantId, 'synced'],
    );

    return rows.first['total'] as int? ?? 0;
  }

  Future<String> createOffline({
    required String tenantId,
    required Map<String, dynamic> customer,
    required DateTime collectedAt,
    required String currency,
    required double amount,
    required String paymentMethod,
    required double latitude,
    required double longitude,
    required double accuracy,
    String? referenceNumber,
    String? visitUuid,
    String? notes,
  }) async {
    if (amount <= 0) {
      throw StateError('Collection amount must be greater than zero.');
    }

    if (paymentMethod != 'cash' &&
        (referenceNumber == null || referenceNumber.trim().isEmpty)) {
      throw StateError(
        'A reference number is required for non-cash collections.',
      );
    }

    final normalizedCurrency = currency.trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(normalizedCurrency)) {
      throw StateError('Currency must be a three-letter code.');
    }
    final customerUuid = customer['id']?.toString() ?? '';
    if (customerUuid.isEmpty) {
      throw StateError('Selected customer is missing an ID.');
    }

    final balanceRows = await balancesForCustomer(tenantId, customerUuid);
    Map<String, dynamic>? balance;
    for (final row in balanceRows) {
      if (row['currency']?.toString() == normalizedCurrency) {
        balance = row;
        break;
      }
    }
    final outstanding = _number(balance?['outstanding_balance']);
    final available = balance == null
        ? outstanding
        : _number(balance['available_to_collect']);

    final uuid = const Uuid().v4();
    final at = collectedAt.toUtc();
    final compact = uuid.replaceAll('-', '').substring(0, 8).toUpperCase();
    final ymd = at.toIso8601String().substring(0, 10).replaceAll('-', '');
    final receipt = 'REC-$ymd-$compact';
    final now = DateTime.now().toUtc().toIso8601String();

    await db.db.insert('local_collections', {
      'tenant_id': tenantId,
      'offline_uuid': uuid,
      'receipt_number': receipt,
      'customer_uuid': customerUuid,
      'customer_name': (customer['name'] ?? 'Customer').toString(),
      'visit_uuid': visitUuid,
      'collected_at': at.toIso8601String(),
      'currency': normalizedCurrency,
      'amount': _round4(amount),
      'payment_method': paymentMethod,
      'reference_number': referenceNumber?.trim().isEmpty == true
          ? null
          : referenceNumber?.trim(),
      'status': 'pending',
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'balance_before': outstanding,
      'overpayment_flag': amount > available + 0.0001 ? 1 : 0,
      'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
      'sync_status': 'pending',
      'created_at': now,
      'updated_at': now,
    });

    return uuid;
  }

  Future<CollectionSyncResult> syncPending(String tenantId) async {
    final rows = await db.db.query(
      'local_collections',
      where: 'tenant_id=? AND sync_status IN (?,?,?)',
      whereArgs: [tenantId, 'pending', 'failed', 'blocked'],
      orderBy: 'collected_at ASC',
    );

    var synced = 0;
    var failed = 0;

    for (final row in rows) {
      final offlineUuid = row['offline_uuid'].toString();
      final customerUuid = row['customer_uuid'].toString();

      if (!await dependencies.customerReady(tenantId, customerUuid)) {
        continue;
      }

      final visitUuid = row['visit_uuid']?.toString();
      if (visitUuid != null &&
          visitUuid.isNotEmpty &&
          !await dependencies.visitReady(tenantId, visitUuid)) {
        continue;
      }

      if (!await retry.shouldAttempt(
        tenantId: tenantId,
        entityType: 'collection',
        entityUuid: offlineUuid,
      )) {
        continue;
      }

      try {
        final server = Map<String, dynamic>.from(
          await api.post(
            'collections',
            data: {
              'offline_uuid': row['offline_uuid'],
              'customer_id': row['customer_uuid'],
              if (row['visit_uuid'] != null) 'visit_id': row['visit_uuid'],
              'collected_at': row['collected_at'],
              'currency': row['currency'],
              'amount': row['amount'],
              'payment_method': row['payment_method'],
              if (row['reference_number'] != null)
                'reference_number': row['reference_number'],
              'latitude': row['latitude'],
              'longitude': row['longitude'],
              'accuracy': row['accuracy'],
              if (row['notes'] != null) 'notes': row['notes'],
            },
          ) as Map,
        );

        await _applyServerCollection(tenantId, server);
        await retry.clear(
          tenantId: tenantId,
          entityType: 'collection',
          entityUuid: offlineUuid,
        );
        synced++;
      } catch (error) {
        final failure = await retry.recordFailure(
          tenantId: tenantId,
          entityType: 'collection',
          entityUuid: offlineUuid,
          error: error,
        );
        await db.db.update(
          'local_collections',
          {
            'sync_status': failure.blocked ? 'blocked' : 'failed',
            'last_error': failure.message,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'tenant_id=? AND offline_uuid=?',
          whereArgs: [tenantId, row['offline_uuid']],
        );
        failed++;
      }
    }

    return CollectionSyncResult(synced: synced, failed: failed);
  }

  Future<void> refreshServerHistory(String tenantId) async {
    final data = await api.get('collections/history', query: {'per_page': 100});

    for (final raw in (data as List? ?? const []).whereType<Map>()) {
      await _applyServerCollection(tenantId, Map<String, dynamic>.from(raw));
    }
  }

  Future<void> refreshBalances(String tenantId) async {
    final data = await api.get('collections/balances');
    final now = DateTime.now().toUtc().toIso8601String();

    await db.db.transaction((txn) async {
      await txn.delete(
        'local_customer_balances',
        where: 'tenant_id=?',
        whereArgs: [tenantId],
      );

      for (final rawCustomer in (data as List? ?? const []).whereType<Map>()) {
        final customer = Map<String, dynamic>.from(rawCustomer);
        final customerUuid = customer['customer_id']?.toString() ?? '';
        if (customerUuid.isEmpty) continue;

        for (final rawBalance
            in (customer['balances'] as List? ?? const []).whereType<Map>()) {
          final balance = Map<String, dynamic>.from(rawBalance);
          await txn.insert('local_customer_balances', {
            'tenant_id': tenantId,
            'customer_uuid': customerUuid,
            'customer_name':
                customer['customer_name']?.toString() ?? 'Customer',
            'currency': balance['currency']?.toString() ?? 'AFN',
            'receivable_total': _number(balance['receivable_total']),
            'verified_collections': _number(balance['verified_collections']),
            'pending_collections': _number(balance['pending_collections']),
            'outstanding_balance': _number(balance['outstanding_balance']),
            'available_to_collect': _number(
              balance['available_to_collect'] ?? balance['outstanding_balance'],
            ),
            'updated_at': now,
          });
        }
      }
    });
  }

  Future<void> _applyServerCollection(
    String tenantId,
    Map<String, dynamic> server,
  ) async {
    final uuid = server['id']?.toString();
    if (uuid == null || uuid.isEmpty) return;

    final existing = await db.db.query(
      'local_collections',
      where: 'tenant_id=? AND offline_uuid=?',
      whereArgs: [tenantId, uuid],
      limit: 1,
    );
    final now = DateTime.now().toUtc().toIso8601String();
    final values = <String, Object?>{
      'server_uuid': uuid,
      'receipt_number': server['receipt_number']?.toString() ?? uuid,
      'customer_uuid': server['customer_id']?.toString() ?? '',
      'customer_name': server['customer_name']?.toString() ?? 'Customer',
      'visit_uuid': server['visit_id']?.toString(),
      'collected_at': server['collected_at']?.toString() ?? now,
      'currency': server['currency']?.toString() ?? 'AFN',
      'amount': _number(server['amount']),
      'payment_method': server['payment_method']?.toString() ?? 'cash',
      'reference_number': server['reference_number']?.toString(),
      'status': server['status']?.toString() ?? 'pending',
      'latitude': _number(server['latitude']),
      'longitude': _number(server['longitude']),
      'accuracy': _number(server['accuracy']),
      'distance_meters': server['distance_meters'] == null
          ? null
          : _number(server['distance_meters']),
      'within_geofence': server['within_geofence'] == null
          ? null
          : (server['within_geofence'] == true ? 1 : 0),
      'balance_before': _number(server['balance_before']),
      'overpayment_flag': server['overpayment_flag'] == true ? 1 : 0,
      'notes': server['notes']?.toString(),
      'status_note': server['status_note']?.toString(),
      'status_changed_at': server['status_changed_at']?.toString(),
      'sync_status': 'synced',
      'last_error': null,
      'updated_at': now,
    };

    if (existing.isEmpty) {
      await db.db.insert('local_collections', {
        'tenant_id': tenantId,
        'offline_uuid': uuid,
        'created_at': now,
        ...values,
      });
    } else {
      await db.db.update(
        'local_collections',
        values,
        where: 'tenant_id=? AND offline_uuid=?',
        whereArgs: [tenantId, uuid],
      );
    }

    await retry.clear(
      tenantId: tenantId,
      entityType: 'collection',
      entityUuid: uuid,
    );
  }

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _round4(double value) => (value * 10000).round() / 10000;
}

class CollectionSyncResult {
  const CollectionSyncResult({required this.synced, required this.failed});

  final int synced;
  final int failed;
}
