import 'package:uuid/uuid.dart';

import '../../core/api/api_client.dart';
import '../../core/db/app_database.dart';
import '../../core/sync/connectivity_gate.dart';
import '../../core/sync/sync_retry_store.dart';

class ExpenseRepository {
  ExpenseRepository({required this.api, required this.db})
    : retry = SyncRetryStore(db);

  final ApiClient api;
  final AppDatabase db;
  final SyncRetryStore retry;

  static const categories = <String>[
    'fuel',
    'transport',
    'meals',
    'accommodation',
    'parking_tolls',
    'mobile_data',
    'office_supplies',
    'customer_entertainment',
    'other',
  ];

  Future<List<Map<String, dynamic>>> list(String tenantId) async {
    final rows = await db.db.query(
      'local_expenses',
      where: 'tenant_id=?',
      whereArgs: [tenantId],
      orderBy: 'spent_at DESC',
    );

    return rows.map(Map<String, dynamic>.from).toList();
  }

  Future<int> pendingCount(String tenantId) async {
    final rows = await db.db.rawQuery(
      'SELECT COUNT(*) AS total FROM local_expenses '
      'WHERE tenant_id=? AND sync_status<>?',
      [tenantId, 'synced'],
    );

    return rows.first['total'] as int? ?? 0;
  }

  Future<String> createOffline({
    required String tenantId,
    required DateTime spentAt,
    required String category,
    required String currency,
    required double amount,
    required double latitude,
    required double longitude,
    required double accuracy,
    double? fuelLiters,
    double? fuelUnitPrice,
    double? odometerKm,
    String? merchant,
    String? referenceNumber,
    String? notes,
  }) async {
    if (!categories.contains(category)) {
      throw StateError('Select a valid expense category.');
    }

    if (amount <= 0) {
      throw StateError('Expense amount must be greater than zero.');
    }

    if (category != 'fuel' &&
        (fuelLiters != null || fuelUnitPrice != null || odometerKm != null)) {
      throw StateError('Fuel details are only valid for fuel expenses.');
    }

    if (fuelLiters != null && fuelLiters <= 0) {
      throw StateError('Fuel liters must be greater than zero.');
    }

    if (fuelUnitPrice != null && fuelUnitPrice <= 0) {
      throw StateError('Fuel unit price must be greater than zero.');
    }

    if (odometerKm != null && odometerKm < 0) {
      throw StateError('Odometer cannot be negative.');
    }

    final normalizedCurrency = currency.trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(normalizedCurrency)) {
      throw StateError('Currency must be a three-letter code.');
    }

    final uuid = const Uuid().v4();
    final at = spentAt.toUtc();
    final compact = uuid.replaceAll('-', '').substring(0, 8).toUpperCase();
    final ymd = at.toIso8601String().substring(0, 10).replaceAll('-', '');
    final now = DateTime.now().toUtc().toIso8601String();

    await db.db.insert('local_expenses', {
      'tenant_id': tenantId,
      'offline_uuid': uuid,
      'expense_number': 'EXP-$ymd-$compact',
      'spent_at': at.toIso8601String(),
      'category': category,
      'currency': normalizedCurrency,
      'amount': _round4(amount),
      'fuel_liters': category == 'fuel' ? fuelLiters : null,
      'fuel_unit_price': category == 'fuel'
          ? (fuelUnitPrice ??
                (fuelLiters != null ? _round4(amount / fuelLiters) : null))
          : null,
      'odometer_km': category == 'fuel' ? odometerKm : null,
      'merchant': _clean(merchant),
      'reference_number': _clean(referenceNumber),
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'status': 'pending',
      'notes': _clean(notes),
      'sync_status': 'pending',
      'created_at': now,
      'updated_at': now,
    });

    return uuid;
  }

  Future<ExpenseSyncResult> syncPending(String tenantId) async {
    if (!await ConnectivityGate.instance.isOnline()) {
      return const ExpenseSyncResult(synced: 0, failed: 0);
    }

    final rows = await db.db.query(
      'local_expenses',
      where: 'tenant_id=? AND sync_status IN (?,?,?)',
      whereArgs: [tenantId, 'pending', 'failed', 'blocked'],
      orderBy: 'spent_at ASC',
    );

    var synced = 0;
    var failed = 0;

    for (final row in rows) {
      final offlineUuid = row['offline_uuid'].toString();

      if (!await retry.shouldAttempt(
        tenantId: tenantId,
        entityType: 'expense',
        entityUuid: offlineUuid,
      )) {
        continue;
      }

      try {
        final server = Map<String, dynamic>.from(
          await api.post(
            'expenses',
            data: {
              'offline_uuid': row['offline_uuid'],
              'spent_at': row['spent_at'],
              'category': row['category'],
              'currency': row['currency'],
              'amount': row['amount'],
              if (row['fuel_liters'] != null) 'fuel_liters': row['fuel_liters'],
              if (row['fuel_unit_price'] != null)
                'fuel_unit_price': row['fuel_unit_price'],
              if (row['odometer_km'] != null) 'odometer_km': row['odometer_km'],
              if (row['merchant'] != null) 'merchant': row['merchant'],
              if (row['reference_number'] != null)
                'reference_number': row['reference_number'],
              'latitude': row['latitude'],
              'longitude': row['longitude'],
              'accuracy': row['accuracy'],
              if (row['notes'] != null) 'notes': row['notes'],
            },
          ) as Map,
        );

        await _applyServerExpense(tenantId, server);
        await retry.clear(
          tenantId: tenantId,
          entityType: 'expense',
          entityUuid: offlineUuid,
        );
        synced++;
      } catch (error) {
        final failure = await retry.recordFailure(
          tenantId: tenantId,
          entityType: 'expense',
          entityUuid: offlineUuid,
          error: error,
        );
        await db.db.update(
          'local_expenses',
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

    return ExpenseSyncResult(synced: synced, failed: failed);
  }

  Future<void> refreshHistory(String tenantId) async {
    if (!await ConnectivityGate.instance.isOnline()) {
      return;
    }

    final data = await api.get('expenses/history', query: {'per_page': 100});

    for (final raw in (data as List? ?? const []).whereType<Map>()) {
      await _applyServerExpense(tenantId, Map<String, dynamic>.from(raw));
    }
  }

  Future<void> _applyServerExpense(
    String tenantId,
    Map<String, dynamic> server,
  ) async {
    final uuid = server['id']?.toString();
    if (uuid == null || uuid.isEmpty) return;

    final existing = await db.db.query(
      'local_expenses',
      where: 'tenant_id=? AND offline_uuid=?',
      whereArgs: [tenantId, uuid],
      limit: 1,
    );

    final now = DateTime.now().toUtc().toIso8601String();
    final values = <String, Object?>{
      'server_uuid': uuid,
      'expense_number': server['expense_number']?.toString() ?? uuid,
      'spent_at': server['spent_at']?.toString() ?? now,
      'category': server['category']?.toString() ?? 'other',
      'currency': server['currency']?.toString() ?? 'AFN',
      'amount': _number(server['amount']),
      'fuel_liters': _nullableNumber(server['fuel_liters']),
      'fuel_unit_price': _nullableNumber(server['fuel_unit_price']),
      'odometer_km': _nullableNumber(server['odometer_km']),
      'merchant': server['merchant']?.toString(),
      'reference_number': server['reference_number']?.toString(),
      'latitude': _number(server['latitude']),
      'longitude': _number(server['longitude']),
      'accuracy': _number(server['accuracy']),
      'status': server['status']?.toString() ?? 'pending',
      'notes': server['notes']?.toString(),
      'review_note': server['review_note']?.toString(),
      'reviewed_at': server['reviewed_at']?.toString(),
      'reviewed_by': server['reviewed_by']?.toString(),
      'sync_status': 'synced',
      'last_error': null,
      'updated_at': now,
    };

    if (existing.isEmpty) {
      await db.db.insert('local_expenses', {
        'tenant_id': tenantId,
        'offline_uuid': uuid,
        'created_at': now,
        ...values,
      });
    } else {
      await db.db.update(
        'local_expenses',
        values,
        where: 'tenant_id=? AND offline_uuid=?',
        whereArgs: [tenantId, uuid],
      );
    }

    await retry.clear(
      tenantId: tenantId,
      entityType: 'expense',
      entityUuid: uuid,
    );
  }

  String? _clean(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  double? _nullableNumber(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  double _round4(double value) => (value * 10000).round() / 10000;
}

class ExpenseSyncResult {
  const ExpenseSyncResult({required this.synced, required this.failed});

  final int synced;
  final int failed;
}
