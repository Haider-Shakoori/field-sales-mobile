import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../core/api/api_client.dart';
import '../../core/db/app_database.dart';
import '../../core/sync/sync_retry_store.dart';

class AttendanceRepository {
  AttendanceRepository({required this.api, required this.db})
    : retry = SyncRetryStore(db);

  final ApiClient api;
  final AppDatabase db;
  final SyncRetryStore retry;

  Future<Map<String, dynamic>?> active(String tenantId) async {
    final rows = await db.db.query(
      'local_work_sessions',
      where: 'tenant_id=? AND status=?',
      whereArgs: [tenantId, 'active'],
      limit: 1,
    );

    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, dynamic>?> forDate(String tenantId, String date) async {
    final rows = await db.db.query(
      'local_work_sessions',
      where: 'tenant_id=? AND date=?',
      whereArgs: [tenantId, date],
      limit: 1,
    );

    return rows.isEmpty ? null : rows.first;
  }

  Future<String> start({
    required String tenantId,
    required String date,
    required DateTime at,
    required double lat,
    required double lng,
    required double accuracy,
    required String source,
    String? privacyAckAt,
  }) async {
    final uuid = const Uuid().v4();

    await db.db.transaction((txn) async {
      final now = DateTime.now().toUtc().toIso8601String();

      await txn.insert('local_work_sessions', {
        'tenant_id': tenantId,
        'offline_uuid': uuid,
        'date': date,
        'start_time': at.toUtc().toIso8601String(),
        'start_latitude': lat,
        'start_longitude': lng,
        'start_accuracy': accuracy,
        'status': 'active',
        'sync_status': 'pending',
        'start_source': source,
        'privacy_ack_at': privacyAckAt,
        'created_at': now,
        'updated_at': now,
      });

      await txn.insert('sync_queue', {
        'tenant_id': tenantId,
        'entity_type': 'attendance',
        'entity_uuid': uuid,
        'action': 'start',
        'payload': jsonEncode({
          'latitude': lat,
          'longitude': lng,
          'accuracy': accuracy,
          'offline_uuid': uuid,
          'started_at': at.toUtc().toIso8601String(),
        }),
        'priority': 10,
        'status': 'pending',
        'created_at': now,
        'updated_at': now,
      });
    });

    return uuid;
  }

  Future<void> end({
    required Map<String, dynamic> session,
    required DateTime at,
    required double lat,
    required double lng,
    required double accuracy,
  }) async {
    final tenantId = '${session['tenant_id']}';
    if (tenantId.isEmpty || tenantId == 'null') {
      throw StateError('Work session tenant is unavailable.');
    }

    await db.db.transaction((txn) async {
      final now = DateTime.now().toUtc().toIso8601String();

      await txn.update(
        'local_work_sessions',
        {
          'end_time': at.toUtc().toIso8601String(),
          'end_latitude': lat,
          'end_longitude': lng,
          'end_accuracy': accuracy,
          'status': 'completed',
          'sync_status': 'pending',
          'updated_at': now,
        },
        where: 'tenant_id=? AND id=?',
        whereArgs: [tenantId, session['id']],
      );

      await txn.insert('sync_queue', {
        'tenant_id': tenantId,
        'entity_type': 'attendance',
        'entity_uuid': session['offline_uuid'],
        'action': 'end',
        'payload': jsonEncode({
          'latitude': lat,
          'longitude': lng,
          'accuracy': accuracy,
          'ended_at': at.toUtc().toIso8601String(),
        }),
        'priority': 20,
        'status': 'pending',
        'created_at': now,
        'updated_at': now,
      });
    });
  }

  Future<void> drain(String tenantId) async {
    final rows = await db.db.query(
      'sync_queue',
      where: 'tenant_id=? AND entity_type=? AND status IN (?,?,?)',
      whereArgs: [tenantId, 'attendance', 'pending', 'failed', 'blocked'],
      orderBy: 'priority ASC, id ASC',
    );

    for (final row in rows) {
      final action = '${row['action']}';
      final entityUuid = '${row['entity_uuid']}';
      final retryUuid = '$entityUuid:$action';

      if (!await retry.shouldAttempt(
        tenantId: tenantId,
        entityType: 'attendance',
        entityUuid: retryUuid,
      )) {
        break;
      }

      try {
        final data = jsonDecode(row['payload'] as String);
        final result = Map<String, dynamic>.from(
          await api.post('attendance/$action', data: data),
        );

        await db.db.transaction((txn) async {
          await txn.update(
            'sync_queue',
            {
              'status': 'synced',
              'server_id': result['id'],
              'server_uuid': result['uuid'],
              'error_message': null,
              'next_retry_at': null,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            },
            where: 'tenant_id=? AND id=?',
            whereArgs: [tenantId, row['id']],
          );

          await txn.update(
            'local_work_sessions',
            {
              'server_id': result['id'],
              'sync_status': 'synced',
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            },
            where: 'tenant_id=? AND offline_uuid=?',
            whereArgs: [tenantId, row['entity_uuid']],
          );
        });

        await retry.clear(
          tenantId: tenantId,
          entityType: 'attendance',
          entityUuid: retryUuid,
        );
      } catch (error) {
        final failure = await retry.recordFailure(
          tenantId: tenantId,
          entityType: 'attendance',
          entityUuid: retryUuid,
          error: error,
        );

        await db.db.update(
          'sync_queue',
          {
            'status': failure.blocked ? 'blocked' : 'failed',
            'attempts': failure.attempts,
            'error_message': failure.message,
            'next_retry_at': failure.nextRetryAt?.toIso8601String(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'tenant_id=? AND id=?',
          whereArgs: [tenantId, row['id']],
        );

        break;
      }
    }
  }
}
