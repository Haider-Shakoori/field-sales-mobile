import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/db/app_database.dart';
import '../../core/sync/connectivity_gate.dart';
import '../../core/sync/local_dependency_guard.dart';
import '../../core/sync/sync_retry_store.dart';

class VisitRepository {
  VisitRepository({required this.api, required this.db})
    : retry = SyncRetryStore(db),
      dependencies = LocalDependencyGuard(db);

  final ApiClient api;
  final AppDatabase db;
  final SyncRetryStore retry;
  final LocalDependencyGuard dependencies;

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
    final missing = await missingRequiredForms(
      tenantId,
      visitOfflineUuid: visit['offline_uuid'].toString(),
      customerUuid: visit['customer_uuid'].toString(),
    );

    if (missing.isNotEmpty) {
      throw StateError(
        'Complete required visit forms before checking out: '
        '${missing.map((form) => form['name']).join(', ')}',
      );
    }

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

  Future<void> refreshForms(String tenantId) async {
    final result = await api.get('visit-forms');
    final body = result is Map<String, dynamic>
        ? result
        : Map<String, dynamic>.from(result as Map);
    final templates = body['templates'] is List
        ? List<dynamic>.from(body['templates'] as List)
        : const <dynamic>[];
    final cachedAt = DateTime.now().toUtc().toIso8601String();

    await db.db.transaction((txn) async {
      await txn.delete(
        'local_visit_form_templates',
        where: 'tenant_id=?',
        whereArgs: [tenantId],
      );

      for (final raw in templates) {
        if (raw is! Map) continue;
        final template = Map<String, dynamic>.from(raw);
        final scope = template['scope'] is Map
            ? Map<String, dynamic>.from(template['scope'] as Map)
            : const <String, dynamic>{};

        await txn.insert('local_visit_form_templates', {
          'tenant_id': tenantId,
          'uuid': template['id'].toString(),
          'code': (template['code'] ?? '').toString(),
          'name': (template['name'] ?? 'Visit form').toString(),
          'version': (template['version'] as num?)?.toInt() ?? 1,
          'required_on_checkout': template['required_on_checkout'] == true
              ? 1
              : 0,
          'scope_type': (scope['type'] ?? 'all').toString(),
          'scope_uuid': scope['id']?.toString(),
          'payload': jsonEncode(template),
          'cached_at': cachedAt,
        });
      }
    });
  }

  Future<List<Map<String, dynamic>>> applicableForms(
    String tenantId, {
    required String customerUuid,
    String? visitOfflineUuid,
  }) async {
    final customerRows = await db.db.query(
      'customers',
      where: 'tenant_id=? AND uuid=?',
      whereArgs: [tenantId, customerUuid],
      limit: 1,
    );

    if (customerRows.isEmpty) return const [];

    final customer = Map<String, dynamic>.from(
      jsonDecode(customerRows.first['payload'].toString()) as Map,
    );
    final routeIds = customer['route_ids'] is List
        ? (customer['route_ids'] as List)
              .map((value) => value.toString())
              .toSet()
        : <String>{};

    final rows = await db.db.query(
      'local_visit_form_templates',
      where: 'tenant_id=?',
      whereArgs: [tenantId],
      orderBy: 'name ASC',
    );

    final submissions = visitOfflineUuid == null
        ? const <Map<String, Object?>>[]
        : await db.db.query(
            'local_visit_form_submissions',
            where: 'tenant_id=? AND visit_offline_uuid=?',
            whereArgs: [tenantId, visitOfflineUuid],
          );
    final submissionByTemplate = {
      for (final row in submissions) row['template_uuid'].toString(): row,
    };

    final forms = <Map<String, dynamic>>[];

    for (final row in rows) {
      final scopeType = row['scope_type'].toString();
      final scopeUuid = row['scope_uuid']?.toString();
      final applies =
          scopeType == 'all' ||
          (scopeType == 'branch' && scopeUuid == customer['branch_id']) ||
          (scopeType == 'territory' && scopeUuid == customer['territory_id']) ||
          (scopeType == 'route' &&
              scopeUuid != null &&
              routeIds.contains(scopeUuid));

      if (!applies) continue;

      final form = Map<String, dynamic>.from(
        jsonDecode(row['payload'].toString()) as Map,
      );
      final submission = submissionByTemplate[row['uuid'].toString()];
      form['local_submission'] = submission == null
          ? null
          : {
              'offline_uuid': submission['offline_uuid'],
              'server_uuid': submission['server_uuid'],
              'sync_status': submission['sync_status'],
              'submitted_at': submission['submitted_at'],
              'last_error': submission['last_error'],
            };
      forms.add(form);
    }

    return forms;
  }

  Future<List<Map<String, dynamic>>> missingRequiredForms(
    String tenantId, {
    required String visitOfflineUuid,
    required String customerUuid,
  }) async {
    final forms = await applicableForms(
      tenantId,
      customerUuid: customerUuid,
      visitOfflineUuid: visitOfflineUuid,
    );

    return forms
        .where(
          (form) =>
              form['required_on_checkout'] == true &&
              form['local_submission'] == null,
        )
        .toList();
  }

  Future<String> saveFormSubmissionLocal({
    required String tenantId,
    required Map<String, dynamic> visit,
    required Map<String, dynamic> template,
    required List<Map<String, dynamic>> answers,
  }) async {
    final visitUuid = visit['offline_uuid'].toString();
    final templateUuid = template['id'].toString();

    final existing = await db.db.query(
      'local_visit_form_submissions',
      where: 'tenant_id=? AND visit_offline_uuid=? AND template_uuid=?',
      whereArgs: [tenantId, visitUuid, templateUuid],
      limit: 1,
    );

    if (existing.isNotEmpty && existing.first['sync_status'] == 'synced') {
      throw StateError('This visit form has already been submitted.');
    }

    final now = DateTime.now().toUtc().toIso8601String();
    final offlineUuid = existing.isEmpty
        ? const Uuid().v4()
        : existing.first['offline_uuid'].toString();
    final values = {
      'tenant_id': tenantId,
      'offline_uuid': offlineUuid,
      'visit_offline_uuid': visitUuid,
      'template_uuid': templateUuid,
      'template_version': (template['version'] as num?)?.toInt() ?? 1,
      'template_name': (template['name'] ?? 'Visit form').toString(),
      'answers_json': jsonEncode(answers),
      'submitted_at': now,
      'sync_status': 'pending',
      'last_error': null,
      'updated_at': now,
    };

    if (existing.isEmpty) {
      await db.db.insert('local_visit_form_submissions', {
        ...values,
        'created_at': now,
      });
    } else {
      await db.db.update(
        'local_visit_form_submissions',
        values,
        where: 'tenant_id=? AND id=?',
        whereArgs: [tenantId, existing.first['id']],
      );
    }

    return offlineUuid;
  }

  Future<List<Map<String, dynamic>>> visitPhotos(
    String tenantId,
    String visitOfflineUuid,
  ) async {
    final rows = await db.db.query(
      'local_visit_photos',
      where: 'tenant_id=? AND visit_offline_uuid=?',
      whereArgs: [tenantId, visitOfflineUuid],
      orderBy: 'captured_at DESC',
    );

    return rows.map(Map<String, dynamic>.from).toList();
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
    final forms = await db.db.rawQuery(
      'SELECT COUNT(*) AS total FROM local_visit_form_submissions '
      'WHERE tenant_id=? AND sync_status<>?',
      [tenantId, 'synced'],
    );

    return (visits.first['total'] as int? ?? 0) +
        (photos.first['total'] as int? ?? 0) +
        (forms.first['total'] as int? ?? 0);
  }

  Future<VisitSyncResult> syncPending(String tenantId) async {
    if (!await ConnectivityGate.instance.isOnline()) {
      return const VisitSyncResult(synced: 0, failed: 0);
    }

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
      final customerUuid = row['customer_uuid'].toString();

      if (!await dependencies.customerReady(tenantId, customerUuid)) {
        continue;
      }

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

    await _syncPhotos(tenantId, row['offline_uuid'].toString(), serverUuid);
    await _syncFormSubmissions(
      tenantId,
      row['offline_uuid'].toString(),
      serverUuid,
    );

    if (row['status'] == 'completed') {
      final requiredReady = await _requiredFormsReadyForCheckout(
        tenantId,
        customerUuid: row['customer_uuid'].toString(),
        visitOfflineUuid: row['offline_uuid'].toString(),
      );

      if (!requiredReady) {
        await db.db.update(
          'local_visits',
          {
            'sync_status': 'pending_checkout',
            'last_error':
                'Required visit forms are waiting for completion or sync.',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'tenant_id=? AND offline_uuid=?',
          whereArgs: [tenantId, row['offline_uuid']],
        );
        return;
      }

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
  }

  Future<bool> _requiredFormsReadyForCheckout(
    String tenantId, {
    required String customerUuid,
    required String visitOfflineUuid,
  }) async {
    final forms = await applicableForms(
      tenantId,
      customerUuid: customerUuid,
      visitOfflineUuid: visitOfflineUuid,
    );

    for (final form in forms) {
      if (form['required_on_checkout'] != true) continue;
      final submission = form['local_submission'];
      if (submission is! Map || submission['sync_status'] != 'synced') {
        return false;
      }
    }

    return true;
  }

  Future<void> _syncFormSubmissions(
    String tenantId,
    String visitOfflineUuid,
    String visitServerUuid,
  ) async {
    final rows = await db.db.query(
      'local_visit_form_submissions',
      where:
          'tenant_id=? AND visit_offline_uuid=? '
          'AND sync_status IN (?,?,?)',
      whereArgs: [tenantId, visitOfflineUuid, 'pending', 'failed', 'blocked'],
      orderBy: 'id ASC',
    );

    for (final row in rows) {
      final offlineUuid = row['offline_uuid'].toString();

      if (!await retry.shouldAttempt(
        tenantId: tenantId,
        entityType: 'visit_form_submission',
        entityUuid: offlineUuid,
      )) {
        continue;
      }

      try {
        final result = Map<String, dynamic>.from(
          await api.post(
            'visits/$visitServerUuid/form-submissions',
            data: {
              'offline_uuid': offlineUuid,
              'template_id': row['template_uuid'],
              'template_version': row['template_version'],
              'submitted_at': row['submitted_at'],
              'answers': jsonDecode(row['answers_json'].toString()),
            },
          ) as Map,
        );

        await db.db.update(
          'local_visit_form_submissions',
          {
            'server_uuid': result['id']?.toString(),
            'sync_status': 'synced',
            'last_error': null,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'tenant_id=? AND id=?',
          whereArgs: [tenantId, row['id']],
        );
        await retry.clear(
          tenantId: tenantId,
          entityType: 'visit_form_submission',
          entityUuid: offlineUuid,
        );
      } catch (error) {
        final failure = await retry.recordFailure(
          tenantId: tenantId,
          entityType: 'visit_form_submission',
          entityUuid: offlineUuid,
          error: error,
        );
        await db.db.update(
          'local_visit_form_submissions',
          {
            'sync_status': failure.blocked ? 'blocked' : 'failed',
            'last_error': failure.message,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'tenant_id=? AND id=?',
          whereArgs: [tenantId, row['id']],
        );
      }
    }
  }

  Future<void> _syncPhotos(
    String tenantId,
    String visitOfflineUuid,
    String visitServerUuid,
  ) async {
    final rows = await db.db.query(
      'local_visit_photos',
      where: 'tenant_id=? AND visit_offline_uuid=? AND sync_status IN (?,?,?)',
      whereArgs: [tenantId, visitOfflineUuid, 'pending', 'failed', 'blocked'],
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
        try {
          final existing = Map<String, dynamic>.from(
            await api.post(
              'visits/$visitServerUuid/photos',
              data: {'client_uuid': clientUuid},
            ) as Map,
          );

          await db.db.update(
            'local_visit_photos',
            {
              'server_uuid': existing['id']?.toString(),
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
          continue;
        } on ApiException catch (error) {
          final missingOnServer = error.status == 422;
          final failure = await retry.recordFailure(
            tenantId: tenantId,
            entityType: 'visit_photo',
            entityUuid: clientUuid,
            error: missingOnServer
                ? StateError('Local photo file is unavailable.')
                : error,
            retryableOverride: missingOnServer ? false : null,
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
