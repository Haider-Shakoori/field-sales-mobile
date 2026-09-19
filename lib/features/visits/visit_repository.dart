import 'dart:io';

import 'package:uuid/uuid.dart';

import '../../core/api/api_client.dart';
import '../../core/db/app_database.dart';
import '../../core/sync/sync_retry_store.dart';

class VisitRepository {
  VisitRepository({required this.api, required this.db})
      : retry = SyncRetryStore(db);

  final ApiClient api;
  final AppDatabase db;
  final SyncRetryStore retry;

  Future<List<Map<String, dynamic>>> list(String tenantId) async {
    final rows = await db.db.query(
      'local_visits',
      where: 'tenant_id=?',
      whereArgs: [tenantId],
      orderBy: 'checked_in_at DESC',
    );

    return rows.map(Map<String, dynamic>.from).toList();
  }

  Future<Map<String, dynamic>?> active(String tenantId) async {
    final rows = await db.db.query(
      'local_visits',
      where: 'tenant_id=? AND status=?',
      whereArgs: [tenantId, 'active'],
      orderBy: 'checked_in_at DESC',
      limit: 1,
    );

    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
  }

  Future<String> checkInLocal({
    required String tenantId,
    required Map<String, dynamic> customer,
    required DateTime at,
    required double latitude,
    required double longitude,
    required double accuracy,
  }) async {
    final uuid = const Uuid().v4();
    final now = DateTime.now().toUtc().toIso8601String();

    await db.db.insert('local_visits', {
      'tenant_id': tenantId,
      'offline_uuid': uuid,
      'customer_uuid': customer['id'].toString(),
      'customer_name': (customer['name'] ?? 'Customer').toString(),
      'status': 'active',
      'checked_in_at': at.toUtc().toIso8601String(),
      'checkin_latitude': latitude,
      'checkin_longitude': longitude,
      'checkin_accuracy': accuracy,
      'sync_status': 'pending_checkin',
      'created_at': now,
      'updated_at': now,
    });

    return uuid;
  }

  Future<void> checkOutLocal({
    required String tenantId,
    required Map<String, dynamic> visit,
    required DateTime at,
    required double latitude,
    required double longitude,
    required double accuracy,
    required String outcome,
    String? notes,
  }) async {
    await db.db.update(
      'local_visits',
      {
        'status': 'completed',
        'outcome': outcome,
        'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
        'checked_out_at': at.toUtc().toIso8601String(),
        'checkout_latitude': latitude,
        'checkout_longitude': longitude,
        'checkout_accuracy': accuracy,
        'sync_status': 'pending_checkout',
        'last_error': null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'tenant_id=? AND offline_uuid=?',
      whereArgs: [tenantId, visit['offline_uuid']],
    );
  }

  Future<String> addPhotoLocal({
    required String tenantId,
    required String visitOfflineUuid,
    required String localPath,
    required DateTime capturedAt,
    double? latitude,
    double? longitude,
    double? accuracy,
  }) async {
    final uuid = const Uuid().v4();

    await db.db.insert('local_visit_photos', {
      'tenant_id': tenantId,
      'client_uuid': uuid,
      'visit_offline_uuid': visitOfflineUuid,
      'local_path': localPath,
      'captured_at': capturedAt.toUtc().toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'sync_status': 'pending',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });

    return uuid;
  }

  Future<int> pendingCount(String tenantId) async {
    final visits = await db.db.rawQuery(
      'SELECT COUNT(*) AS total FROM local_visits '
      'WHERE tenant_id=? AND sync_status<>?',
      [tenantId, 'synced'],
    );
    final photos = await db.db.rawQuery(
      'SELECT COUNT(*) AS total FROM local_visit_photos '
      'WHERE tenant_id=? AND sync_status<>?',
      [tenantId, 'synced'],
    );

    return (visits.first['total'] as int? ?? 0) +
        (photos.first['total'] as int? ?? 0);
  }

  Future<VisitSyncResult> syncPending(String tenantId) async {
    final rows = await db.db.query(
      'local_visits',
      where: 'tenant_id=? AND sync_status IN (?,?,?,?)',
      whereArgs: [
        tenantId,
        'pending_checkin',
        'pending_checkout',
        'failed',
        'blocked',
      ],
      orderBy: 'checked_in_at ASC',
    );

    var synced = 0;
    var failed = 0;

    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw);
      final offlineUuid = row['offline_uuid'].toString();

      if (!await retry.shouldAttempt(
        tenantId: tenantId,
        entityType: 'visit',
        entityUuid: offlineUuid,
      )) {
        continue;
      }

      try {
        await _syncVisit(tenantId, row);
        await retry.clear(
          tenantId: tenantId,
          entityType: 'visit',
          entityUuid: offlineUuid,
        );
        synced++;
      } catch (error) {
        final failure = await retry.recordFailure(
          tenantId: tenantId,
          entityType: 'visit',
          entityUuid: offlineUuid,
          error: error,
        );
        await db.db.update(
          'local_visits',
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

    final syncedVisits = await db.db.query(
      'local_visits',
      where: 'tenant_id=? AND server_uuid IS NOT NULL',
      whereArgs: [tenantId],
    );
    for (final row in syncedVisits) {
      try {
        await _syncPhotos(
          tenantId,
          row['offline_uuid'].toString(),
          row['server_uuid'].toString(),
        );
      } catch (_) {
        failed++;
      }
    }

    return VisitSyncResult(synced: synced, failed: failed);
  }

  Future<void> _syncVisit(String tenantId, Map<String, dynamic> row) async {
    var serverUuid = row['server_uuid']?.toString();

    if (serverUuid == null || serverUuid.isEmpty) {
      final result = Map<String, dynamic>.from(
        await api.post(
          'visits/check-in',
          data: {
            'offline_uuid': row['offline_uuid'],
            'customer_id': row['customer_uuid'],
            'latitude': row['checkin_latitude'],
            'longitude': row['checkin_longitude'],
            'accuracy': row['checkin_accuracy'],
            'checked_in_at': row['checked_in_at'],
          },
        ) as Map,
      );

      serverUuid = result['id'].toString();
      final checkin = result['checkin'] is Map
          ? Map<String, dynamic>.from(result['checkin'] as Map)
          : const <String, dynamic>{};

      await db.db.update(
        'local_visits',
        {
          'server_uuid': serverUuid,
          'route_uuid': result['route_id'],
          'is_planned': _boolInt(result['is_planned']),
          'checkin_distance_meters': checkin['distance_meters'],
          'checkin_within_geofence': _boolInt(checkin['within_geofence']),
          'sync_status': row['status'] == 'completed'
              ? 'pending_checkout'
              : 'synced',
          'last_error': null,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'tenant_id=? AND offline_uuid=?',
        whereArgs: [tenantId, row['offline_uuid']],
      );
    }

    if (row['status'] == 'completed') {
      final result = Map<String, dynamic>.from(
        await api.post(
          'visits/$serverUuid/check-out',
          data: {
            'latitude': row['checkout_latitude'],
            'longitude': row['checkout_longitude'],
            'accuracy': row['checkout_accuracy'],
            'checked_out_at': row['checked_out_at'],
            'outcome': row['outcome'],
            if (row['notes'] != null) 'notes': row['notes'],
          },
        ) as Map,
      );

      final checkout = result['checkout'] is Map
          ? Map<String, dynamic>.from(result['checkout'] as Map)
          : const <String, dynamic>{};

      await db.db.update(
        'local_visits',
        {
          'server_uuid': result['id'].toString(),
          'route_uuid': result['route_id'],
          'is_planned': _boolInt(result['is_planned']),
          'duration_seconds': result['duration_seconds'],
          'checkout_distance_meters': checkout['distance_meters'],
          'checkout_within_geofence': _boolInt(checkout['within_geofence']),
          'sync_status': 'synced',
          'last_error': null,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'tenant_id=? AND offline_uuid=?',
        whereArgs: [tenantId, row['offline_uuid']],
      );
    }

    await _syncPhotos(tenantId, row['offline_uuid'].toString(), serverUuid);
  }

  Future<void> _syncPhotos(
    String tenantId,
    String visitOfflineUuid,
    String visitServerUuid,
  ) async {
    final rows = await db.db.query(
      'local_visit_photos',
      where:
          'tenant_id=? AND visit_offline_uuid=? AND sync_status IN (?,?,?)',
      whereArgs: [
        tenantId,
        visitOfflineUuid,
        'pending',
        'failed',
        'blocked',
      ],
      orderBy: 'id ASC',
    );

    for (final row in rows) {
      final clientUuid = row['client_uuid'].toString();

      if (!await retry.shouldAttempt(
        tenantId: tenantId,
        entityType: 'visit_photo',
        entityUuid: clientUuid,
      )) {
        continue;
      }

      final file = File(row['local_path'].toString());

      if (!await file.exists()) {
        final failure = await retry.recordFailure(
          tenantId: tenantId,
          entityType: 'visit_photo',
          entityUuid: clientUuid,
          error: StateError('Local photo file is unavailable.'),
          retryableOverride: false,
        );
        await db.db.update(
          'local_visit_photos',
          {
            'sync_status': failure.blocked ? 'blocked' : 'failed',
            'last_error': failure.message,
          },
          where: 'tenant_id=? AND id=?',
          whereArgs: [tenantId, row['id']],
        );
        continue;
      }

      try {
        final result = Map<String, dynamic>.from(
          await api.postMultipart(
            'visits/$visitServerUuid/photos',
            filePath: file.path,
            fields: {
              'client_uuid': clientUuid,
              'captured_at': row['captured_at'],
              if (row['latitude'] != null) 'latitude': row['latitude'],
              if (row['longitude'] != null) 'longitude': row['longitude'],
              if (row['accuracy'] != null) 'accuracy': row['accuracy'],
            },
          ) as Map,
        );

        await db.db.update(
          'local_visit_photos',
          {
            'server_uuid': result['id']?.toString(),
            'sync_status': 'synced',
            'last_error': null,
          },
          where: 'tenant_id=? AND id=?',
          whereArgs: [tenantId, row['id']],
        );
        await retry.clear(
          tenantId: tenantId,
          entityType: 'visit_photo',
          entityUuid: clientUuid,
        );
      } catch (error) {
        final failure = await retry.recordFailure(
          tenantId: tenantId,
          entityType: 'visit_photo',
          entityUuid: clientUuid,
          error: error,
        );
        await db.db.update(
          'local_visit_photos',
          {
            'sync_status': failure.blocked ? 'blocked' : 'failed',
            'last_error': failure.message,
          },
          where: 'tenant_id=? AND id=?',
          whereArgs: [tenantId, row['id']],
        );
      }
    }
  }

  int? _boolInt(dynamic value) {
    if (value == null) return null;
    return value == true || value == 1 ? 1 : 0;
  }
}

class VisitSyncResult {
  const VisitSyncResult({required this.synced, required this.failed});

  final int synced;
  final int failed;
}
