import 'package:uuid/uuid.dart';

import '../../core/api/api_client.dart';
import '../../core/db/app_database.dart';

class CallActivityRepository {
  CallActivityRepository({required this.api, required this.db});

  final ApiClient api;
  final AppDatabase db;

  Future<List<Map<String, dynamic>>> list(String tenantId) async {
    final rows = await db.db.query(
      'local_call_activities',
      where: 'tenant_id=?',
      whereArgs: [tenantId],
      orderBy: 'called_at DESC',
    );

    return rows.map(Map<String, dynamic>.from).toList();
  }

  Future<String> recordLocal({
    required String tenantId,
    required Map<String, dynamic> customer,
    required String phoneNumber,
    required DateTime calledAt,
    String? outcome,
    String? notes,
  }) async {
    final uuid = const Uuid().v4();
    final now = DateTime.now().toUtc().toIso8601String();

    await db.db.insert('local_call_activities', {
      'tenant_id': tenantId,
      'offline_uuid': uuid,
      'customer_uuid': customer['id'].toString(),
      'customer_name': (customer['name'] ?? 'Customer').toString(),
      'phone_number': phoneNumber,
      'called_at': calledAt.toUtc().toIso8601String(),
      'outcome': outcome,
      'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
      'sync_status': 'pending',
      'created_at': now,
      'updated_at': now,
    });

    return uuid;
  }

  Future<int> pendingCount(String tenantId) async {
    final rows = await db.db.rawQuery(
      'SELECT COUNT(*) AS total FROM local_call_activities '
      'WHERE tenant_id=? AND sync_status<>?',
      [tenantId, 'synced'],
    );

    return rows.first['total'] as int? ?? 0;
  }

  Future<CallActivitySyncResult> syncPending(String tenantId) async {
    final rows = await db.db.query(
      'local_call_activities',
      where: 'tenant_id=? AND sync_status IN (?,?)',
      whereArgs: [tenantId, 'pending', 'failed'],
      orderBy: 'called_at ASC',
    );

    var synced = 0;
    var failed = 0;

    for (final row in rows) {
      try {
        final result = Map<String, dynamic>.from(
          await api.post(
            'call-activities',
            data: {
              'offline_uuid': row['offline_uuid'],
              'customer_id': row['customer_uuid'],
              'phone_number': row['phone_number'],
              'called_at': row['called_at'],
              if (row['outcome'] != null) 'outcome': row['outcome'],
              if (row['notes'] != null) 'notes': row['notes'],
            },
          ) as Map,
        );

        await db.db.update(
          'local_call_activities',
          {
            'server_uuid': result['id']?.toString(),
            'sync_status': 'synced',
            'last_error': null,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'tenant_id=? AND offline_uuid=?',
          whereArgs: [tenantId, row['offline_uuid']],
        );
        synced++;
      } catch (error) {
        await db.db.update(
          'local_call_activities',
          {
            'sync_status': 'failed',
            'last_error': error.toString(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'tenant_id=? AND offline_uuid=?',
          whereArgs: [tenantId, row['offline_uuid']],
        );
        failed++;
      }
    }

    return CallActivitySyncResult(synced: synced, failed: failed);
  }
}

class CallActivitySyncResult {
  const CallActivitySyncResult({required this.synced, required this.failed});

  final int synced;
  final int failed;
}
