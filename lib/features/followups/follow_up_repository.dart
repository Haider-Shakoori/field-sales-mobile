import 'package:uuid/uuid.dart';

import '../../core/api/api_client.dart';
import '../../core/db/app_database.dart';
import '../../core/sync/connectivity_gate.dart';
import '../../core/sync/local_dependency_guard.dart';
import '../../core/sync/sync_retry_store.dart';

class FollowUpRepository {
  FollowUpRepository({required this.api, required this.db})
    : retry = SyncRetryStore(db),
      dependencies = LocalDependencyGuard(db);

  static const types = ['call', 'visit', 'payment', 'order', 'other'];
  static const priorities = ['low', 'normal', 'high'];
  static const statuses = ['pending', 'completed', 'cancelled'];

  final ApiClient api;
  final AppDatabase db;
  final SyncRetryStore retry;
  final LocalDependencyGuard dependencies;

  Future<List<Map<String, dynamic>>> list(String tenantId) async {
    final rows = await db.db.query(
      'local_customer_follow_ups',
      where: 'tenant_id=?',
      whereArgs: [tenantId],
      orderBy: 'status ASC, due_at ASC',
    );
    return rows.map(Map<String, dynamic>.from).toList();
  }

  Future<int> pendingCount(String tenantId) async {
    final rows = await db.db.rawQuery(
      'SELECT COUNT(*) AS total FROM local_customer_follow_ups '
      'WHERE tenant_id=? AND sync_status<>?',
      [tenantId, 'synced'],
    );
    return rows.first['total'] as int? ?? 0;
  }

  Future<String> createLocal({
    required String tenantId,
    required Map<String, dynamic> customer,
    required String type,
    required String priority,
    required DateTime dueAt,
    String? notes,
  }) async {
    if (!types.contains(type)) {
      throw StateError('Select a valid follow-up type.');
    }
    if (!priorities.contains(priority)) {
      throw StateError('Select a valid follow-up priority.');
    }

    final uuid = const Uuid().v4();
    final now = DateTime.now().toUtc().toIso8601String();

    await db.db.insert('local_customer_follow_ups', {
      'tenant_id': tenantId,
      'offline_uuid': uuid,
      'customer_uuid': customer['id'].toString(),
      'customer_name': (customer['name'] ?? 'Customer').toString(),
      'type': type,
      'priority': priority,
      'status': 'pending',
      'due_at': dueAt.toUtc().toIso8601String(),
      'notes': _nullable(notes),
      'sync_status': 'pending_create',
      'created_at': now,
      'updated_at': now,
    });

    return uuid;
  }

  Future<void> updateStatusLocal({
    required String tenantId,
    required String offlineUuid,
    required String status,
    String? completionNote,
  }) async {
    if (status != 'completed' && status != 'cancelled') {
      throw StateError('Follow-up status must be completed or cancelled.');
    }

    final rows = await db.db.query(
      'local_customer_follow_ups',
      columns: ['sync_status'],
      where: 'tenant_id=? AND offline_uuid=?',
      whereArgs: [tenantId, offlineUuid],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Follow-up not found.');
    final current = rows.first['sync_status']?.toString() ?? 'synced';
    final nextSync = current == 'pending_create' || current == 'failed_create'
        ? current
        : 'pending_status';
    final now = DateTime.now().toUtc();

    await db.db.update(
      'local_customer_follow_ups',
      {
        'status': status,
        'completed_at': status == 'completed' ? now.toIso8601String() : null,
        'completion_note': _nullable(completionNote),
        'sync_status': nextSync,
        'last_error': null,
        'updated_at': now.toIso8601String(),
      },
      where: 'tenant_id=? AND offline_uuid=?',
      whereArgs: [tenantId, offlineUuid],
    );
  }

  Future<FollowUpSyncResult> syncPending(String tenantId) async {
    if (!await ConnectivityGate.instance.isOnline()) {
      return const FollowUpSyncResult(synced: 0, failed: 0);
    }

    final rows = await db.db.query(
      'local_customer_follow_ups',
      where: 'tenant_id=? AND sync_status<>?',
      whereArgs: [tenantId, 'synced'],
      orderBy: 'due_at ASC',
    );

    var synced = 0;
    var failed = 0;

    for (final row in rows) {
      final offlineUuid = row['offline_uuid'].toString();
      if (!await retry.shouldAttempt(
        tenantId: tenantId,
        entityType: 'follow_up',
        entityUuid: offlineUuid,
      )) {
        continue;
      }

      try {
        final syncStatus = row['sync_status']?.toString() ?? 'synced';
        var serverUuid = row['server_uuid']?.toString();
        Map<String, dynamic>? server;

        if (syncStatus == 'pending_create' || syncStatus == 'failed_create') {
          final customerUuid = row['customer_uuid'].toString();
          if (!await dependencies.customerReady(tenantId, customerUuid)) {
            continue;
          }
          server = Map<String, dynamic>.from(
            await api.post(
              'customers/$customerUuid/follow-ups',
              data: {
                'offline_uuid': offlineUuid,
                'type': row['type'],
                'priority': row['priority'],
                'due_at': row['due_at'],
                if (row['notes'] != null) 'notes': row['notes'],
              },
            ) as Map,
          );
          serverUuid = server['id']?.toString() ?? offlineUuid;

          if (row['status'] != 'pending') {
            server = Map<String, dynamic>.from(
              await api.patch(
                'follow-ups/$serverUuid/status',
                data: {
                  'status': row['status'],
                  if (row['completion_note'] != null)
                    'completion_note': row['completion_note'],
                },
              ) as Map,
            );
          }
        } else if (syncStatus == 'pending_status' ||
            syncStatus == 'failed_status') {
          serverUuid ??= offlineUuid;
          server = Map<String, dynamic>.from(
            await api.patch(
              'follow-ups/$serverUuid/status',
              data: {
                'status': row['status'],
                if (row['completion_note'] != null)
                  'completion_note': row['completion_note'],
              },
            ) as Map,
          );
        }

        if (server != null) {
          await _applyServer(tenantId, server);
        } else {
          await db.db.update(
            'local_customer_follow_ups',
            {
              'server_uuid': serverUuid ?? offlineUuid,
              'sync_status': 'synced',
              'last_error': null,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            },
            where: 'tenant_id=? AND offline_uuid=?',
            whereArgs: [tenantId, offlineUuid],
          );
        }

        await retry.clear(
          tenantId: tenantId,
          entityType: 'follow_up',
          entityUuid: offlineUuid,
        );
        synced++;
      } catch (error) {
        final failure = await retry.recordFailure(
          tenantId: tenantId,
          entityType: 'follow_up',
          entityUuid: offlineUuid,
          error: error,
        );
        final current = row['sync_status']?.toString() ?? '';
        final phase = current.contains('status') ? 'status' : 'create';
        await db.db.update(
          'local_customer_follow_ups',
          {
            'sync_status': failure.blocked ? 'blocked' : 'failed_$phase',
            'last_error': failure.message,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'tenant_id=? AND offline_uuid=?',
          whereArgs: [tenantId, offlineUuid],
        );
        failed++;
      }
    }

    return FollowUpSyncResult(synced: synced, failed: failed);
  }

  Future<void> refresh(String tenantId) async {
    if (!await ConnectivityGate.instance.isOnline()) return;

    var page = 1;
    var lastPage = 1;

    do {
      final envelope = await api.getEnvelope(
        'follow-ups',
        query: {'per_page': 100, 'page': page},
      );
      final rows = envelope.data is List
          ? List<Map<String, dynamic>>.from(
              (envelope.data as List).map(
                (row) => Map<String, dynamic>.from(row as Map),
              ),
            )
          : const <Map<String, dynamic>>[];
      for (final server in rows) {
        final uuid = server['id']?.toString();
        if (uuid == null || uuid.isEmpty) continue;

        final local = await db.db.query(
          'local_customer_follow_ups',
          columns: ['sync_status'],
          where: 'tenant_id=? AND offline_uuid=?',
          whereArgs: [tenantId, uuid],
          limit: 1,
        );
        if (local.isNotEmpty && local.first['sync_status'] != 'synced') {
          continue;
        }

        await _applyServer(tenantId, server);
      }

      final rawLast = envelope.meta['last_page'];
      lastPage = rawLast is int ? rawLast : int.tryParse('$rawLast') ?? 1;
      page++;
    } while (page <= lastPage);
  }

  Future<void> _applyServer(
    String tenantId,
    Map<String, dynamic> server,
  ) async {
    final uuid = server['id'].toString();
    final now = DateTime.now().toUtc().toIso8601String();
    final existing = await db.db.query(
      'local_customer_follow_ups',
      columns: ['created_at'],
      where: 'tenant_id=? AND offline_uuid=?',
      whereArgs: [tenantId, uuid],
      limit: 1,
    );

    final values = <String, Object?>{
      'tenant_id': tenantId,
      'offline_uuid': uuid,
      'server_uuid': uuid,
      'customer_uuid': server['customer_id']?.toString() ?? '',
      'customer_name': server['customer_name']?.toString(),
      'type': server['type']?.toString() ?? 'call',
      'priority': server['priority']?.toString() ?? 'normal',
      'status': server['status']?.toString() ?? 'pending',
      'due_at': server['due_at']?.toString() ?? now,
      'notes': server['notes']?.toString(),
      'completed_at': server['completed_at']?.toString(),
      'completion_note': server['completion_note']?.toString(),
      'sync_status': 'synced',
      'last_error': null,
      'created_at': existing.isEmpty
          ? server['created_at']?.toString() ?? now
          : existing.first['created_at'],
      'updated_at': server['updated_at']?.toString() ?? now,
    };

    if (existing.isEmpty) {
      await db.db.insert('local_customer_follow_ups', values);
    } else {
      await db.db.update(
        'local_customer_follow_ups',
        values,
        where: 'tenant_id=? AND offline_uuid=?',
        whereArgs: [tenantId, uuid],
      );
    }
  }

  String? _nullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

class FollowUpSyncResult {
  const FollowUpSyncResult({required this.synced, required this.failed});

  final int synced;
  final int failed;
}
