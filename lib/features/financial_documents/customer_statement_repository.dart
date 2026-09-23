import 'dart:convert';

import '../../core/api/api_client.dart';
import '../../core/db/app_database.dart';

import 'package:sqflite/sqflite.dart';

import '../../core/sync/connectivity_gate.dart';

class CustomerStatementRepository {
  CustomerStatementRepository({required this.api, required this.db});

  final ApiClient api;
  final AppDatabase db;

  Future<Map<String, dynamic>> load({
    required String tenantId,
    required String customerUuid,
    String? from,
    String? to,
    String? currency,
    bool refresh = true,
  }) async {
    var online = false;

    if (refresh) {
      online = await ConnectivityGate.instance.isOnline();
    }

    if (refresh && online) {
      final response = await api.get(
        'customers/$customerUuid/statement',
        query: {
          'from': ?from,
          'to': ?to,
          'currency': ?currency,
        },
      );

      final statement = response is Map<String, dynamic>
          ? response
          : Map<String, dynamic>.from(response as Map);

      await _cache(tenantId, customerUuid, statement);

      return {...statement, '_cached': false};
    }

    final cached = await _cached(
      tenantId: tenantId,
      customerUuid: customerUuid,
      from: from,
      to: to,
      currency: currency,
    );

    if (cached != null) {
      return {...cached, '_cached': true};
    }

    throw StateError(
      online
          ? 'No cached statement matches this date range.'
          : 'No cached customer statement is available offline.',
    );
  }

  Future<void> _cache(
    String tenantId,
    String customerUuid,
    Map<String, dynamic> statement,
  ) async {
    final from = statement['from']?.toString();
    final to = statement['to']?.toString();
    final currency = statement['currency']?.toString();

    if (from == null || to == null || currency == null) {
      throw StateError('Customer statement response is incomplete.');
    }

    final now = DateTime.now().toUtc().toIso8601String();

    await db.db.insert('local_customer_statements', {
      'tenant_id': tenantId,
      'customer_uuid': customerUuid,
      'currency': currency,
      'from_date': from,
      'to_date': to,
      'payload': jsonEncode(statement),
      'cached_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> _cached({
    required String tenantId,
    required String customerUuid,
    String? from,
    String? to,
    String? currency,
  }) async {
    final exact = from != null && to != null && currency != null;

    final rows = await db.db.query(
      'local_customer_statements',
      where: exact
          ? 'tenant_id=? AND customer_uuid=? AND currency=? '
                'AND from_date=? AND to_date=?'
          : 'tenant_id=? AND customer_uuid=?',
      whereArgs: exact
          ? [tenantId, customerUuid, currency, from, to]
          : [tenantId, customerUuid],
      orderBy: 'cached_at DESC',
      limit: 1,
    );

    if (rows.isEmpty) return null;

    final decoded = jsonDecode(rows.first['payload'].toString());
    if (decoded is! Map) return null;

    return Map<String, dynamic>.from(decoded);
  }
}
