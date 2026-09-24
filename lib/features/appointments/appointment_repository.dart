import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/api/api_client.dart';
import '../../core/db/app_database.dart';
import '../../core/sync/connectivity_gate.dart';
import '../../core/sync/local_dependency_guard.dart';
import '../../core/sync/sync_retry_store.dart';

class AppointmentRepository {
  AppointmentRepository({required this.api, required this.db})
    : retry = SyncRetryStore(db),
      dependencies = LocalDependencyGuard(db);

  final ApiClient api;
  final AppDatabase db;
  final SyncRetryStore retry;
  final LocalDependencyGuard dependencies;

  Future<List<Map<String, dynamic>>> list(
    String tenantId, {
    DateTime? from,
    DateTime? to,
  }) async {
    final where = <String>['tenant_id=?'];
    final args = <Object?>[tenantId];

    if (from != null) {
      where.add('starts_at>=?');
      args.add(from.toUtc().toIso8601String());
    }
    if (to != null) {
      where.add('starts_at<=?');
      args.add(to.toUtc().toIso8601String());
    }

    final rows = await db.db.query(
      'local_appointments',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'starts_at ASC',
    );

    return rows.map(Map<String, dynamic>.from).toList();
  }

  Future<String> createLocal({
    required String tenantId,
    Map<String, dynamic>? customer,
    required String title,
    required String type,
    required DateTime startsAt,
    DateTime? endsAt,
    int? reminderMinutesBefore,
    String? location,
    String? notes,
  }) async {
    final uuid = const Uuid().v4();
    final now = DateTime.now().toUtc().toIso8601String();

    await db.db.insert('local_appointments', {
      'tenant_id': tenantId,
      'offline_uuid': uuid,
      'customer_uuid': customer?['id']?.toString(),
      'customer_name': customer?['name']?.toString(),
      'title': title.trim(),
      'type': type,
      'status': 'scheduled',
      'starts_at': startsAt.toUtc().toIso8601String(),
      'ends_at': endsAt?.toUtc().toIso8601String(),
      'reminder_minutes_before': reminderMinutesBefore,
      'location': _nullable(location),
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
  }) async {
    final rows = await db.db.query(
      'local_appointments',
      columns: ['sync_status'],
      where: 'tenant_id=? AND offline_uuid=?',
      whereArgs: [tenantId, offlineUuid],
      limit: 1,
    );

    if (rows.isEmpty) {
      throw StateError('Appointment not found.');
    }

    final currentSync = rows.first['sync_status']?.toString() ?? 'synced';
    final nextSync =
        currentSync == 'pending_create' || currentSync == 'failed_create'
        ? currentSync
        : 'pending_status';

    await db.db.update(
      'local_appointments',
      {
        'status': status,
        'completed_at': status == 'completed'
            ? DateTime.now().toUtc().toIso8601String()
            : null,
        'sync_status': nextSync,
        'last_error': null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'tenant_id=? AND offline_uuid=?',
      whereArgs: [tenantId, offlineUuid],
    );
  }

  Future<int> pendingCount(String tenantId) async {
    final rows = await db.db.rawQuery(
      'SELECT COUNT(*) AS total FROM local_appointments '
      'WHERE tenant_id=? AND sync_status<>?',
      [tenantId, 'synced'],
    );

    return rows.first['total'] as int? ?? 0;
  }

  Future<AppointmentSyncResult> syncPending(String tenantId) async {
    if (!await ConnectivityGate.instance.isOnline()) {
      return const AppointmentSyncResult(synced: 0, failed: 0);
    }

    final rows = await db.db.query(
      'local_appointments',
      where: 'tenant_id=? AND sync_status<>?',
      whereArgs: [tenantId, 'synced'],
      orderBy: 'starts_at ASC',
    );

    var synced = 0;
    var failed = 0;

    for (final row in rows) {
      final offlineUuid = row['offline_uuid'].toString();

      if (!await retry.shouldAttempt(
        tenantId: tenantId,
        entityType: 'appointment',
        entityUuid: offlineUuid,
      )) {
        continue;
      }

      final customerUuid = row['customer_uuid']?.toString();
      if (customerUuid != null &&
          customerUuid.isNotEmpty &&
          !await dependencies.customerReady(tenantId, customerUuid)) {
        continue;
      }

      try {
        var serverUuid = row['server_uuid']?.toString();
        final syncStatus = row['sync_status']?.toString() ?? 'synced';

        if (syncStatus == 'pending_create' || syncStatus == 'failed_create') {
          final result = Map<String, dynamic>.from(
            await api.post(
              'appointments',
              data: {
                'offline_uuid': offlineUuid,
                if (customerUuid != null && customerUuid.isNotEmpty)
                  'customer_id': customerUuid,
                'title': row['title'],
                'type': row['type'],
                'starts_at': row['starts_at'],
                if (row['ends_at'] != null) 'ends_at': row['ends_at'],
                if (row['reminder_minutes_before'] != null)
                  'reminder_minutes_before': row['reminder_minutes_before'],
                if (row['location'] != null) 'location': row['location'],
                if (row['notes'] != null) 'notes': row['notes'],
              },
            ) as Map,
          );

          serverUuid = result['id']?.toString() ?? offlineUuid;

          if (row['status'] != 'scheduled') {
            await api.patch(
              'appointments/$serverUuid/status',
              data: {'status': row['status']},
            );
          }
        } else if (syncStatus == 'pending_status' ||
            syncStatus == 'failed_status') {
          serverUuid ??= offlineUuid;
          await api.patch(
            'appointments/$serverUuid/status',
            data: {'status': row['status']},
          );
        }

        await db.db.update(
          'local_appointments',
          {
            'server_uuid': serverUuid ?? offlineUuid,
            'sync_status': 'synced',
            'last_error': null,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'tenant_id=? AND offline_uuid=?',
          whereArgs: [tenantId, offlineUuid],
        );
        await retry.clear(
          tenantId: tenantId,
          entityType: 'appointment',
          entityUuid: offlineUuid,
        );
        synced++;
      } catch (error) {
        final failure = await retry.recordFailure(
          tenantId: tenantId,
          entityType: 'appointment',
          entityUuid: offlineUuid,
          error: error,
        );
        final status = row['sync_status']?.toString() ?? '';

        await db.db.update(
          'local_appointments',
          {
            'sync_status': status.contains('create')
                ? 'failed_create'
                : 'failed_status',
            'last_error': failure.message,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'tenant_id=? AND offline_uuid=?',
          whereArgs: [tenantId, offlineUuid],
        );
        failed++;
      }
    }

    return AppointmentSyncResult(synced: synced, failed: failed);
  }

  Future<void> refresh(String tenantId) async {
    if (!await ConnectivityGate.instance.isOnline()) {
      return;
    }

    final now = DateTime.now();
    final from = now.subtract(const Duration(days: 30));
    final to = now.add(const Duration(days: 90));
    final data = await api.get(
      'appointments',
      query: {'from': _dateKey(from), 'to': _dateKey(to)},
    );

    final rows = (data as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();

    for (final row in rows) {
      final uuid = row['id']?.toString();
      if (uuid == null || uuid.isEmpty) continue;

      final existing = await db.db.query(
        'local_appointments',
        columns: ['sync_status'],
        where: 'tenant_id=? AND offline_uuid=?',
        whereArgs: [tenantId, uuid],
        limit: 1,
      );

      if (existing.isNotEmpty &&
          existing.first['sync_status']?.toString() != 'synced') {
        continue;
      }

      final timestamp = DateTime.now().toUtc().toIso8601String();
      await db.db.insert('local_appointments', {
        'tenant_id': tenantId,
        'offline_uuid': uuid,
        'server_uuid': uuid,
        'customer_uuid': row['customer_id']?.toString(),
        'customer_name': row['customer_name']?.toString(),
        'title': row['title']?.toString() ?? 'Appointment',
        'type': row['type']?.toString() ?? 'meeting',
        'status': row['status']?.toString() ?? 'scheduled',
        'starts_at': row['starts_at']?.toString() ?? timestamp,
        'ends_at': row['ends_at']?.toString(),
        'reminder_minutes_before': row['reminder_minutes_before'],
        'location': row['location']?.toString(),
        'notes': row['notes']?.toString(),
        'completed_at': row['completed_at']?.toString(),
        'sync_status': 'synced',
        'last_error': null,
        'created_at': timestamp,
        'updated_at': row['updated_at']?.toString() ?? timestamp,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  String? _nullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  String _dateKey(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }
}

class AppointmentSyncResult {
  const AppointmentSyncResult({required this.synced, required this.failed});

  final int synced;
  final int failed;
}
