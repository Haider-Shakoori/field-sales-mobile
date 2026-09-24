import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/api/api_client.dart';
import '../../core/db/app_database.dart';
import '../../core/sync/connectivity_gate.dart';
import '../../core/sync/sync_retry_store.dart';

class LeadRepository {
  LeadRepository({required this.api, required this.db})
    : retry = SyncRetryStore(db);

  final ApiClient api;
  final AppDatabase db;
  final SyncRetryStore retry;

  Future<List<Map<String, dynamic>>> list(String tenantId) async {
    final rows = await db.db.query(
      'local_leads',
      where: 'tenant_id=?',
      whereArgs: [tenantId],
      orderBy: 'COALESCE(last_activity_at, updated_at) DESC, id DESC',
    );
    return rows.map(Map<String, dynamic>.from).toList();
  }

  Future<List<Map<String, dynamic>>> activities(
    String tenantId,
    String leadOfflineUuid,
  ) async {
    final rows = await db.db.query(
      'local_lead_activities',
      where: 'tenant_id=? AND lead_offline_uuid=?',
      whereArgs: [tenantId, leadOfflineUuid],
      orderBy: 'occurred_at DESC, id DESC',
    );
    return rows.map(Map<String, dynamic>.from).toList();
  }

  Future<String> createLocal({
    required String tenantId,
    required String name,
    String? contactPerson,
    String? phone,
    String? email,
    String? address,
    String source = 'field',
    String priority = 'normal',
    double? estimatedValue,
    String currency = 'AFN',
    DateTime? expectedCloseDate,
    String? notes,
  }) async {
    final uuid = const Uuid().v4();
    final now = DateTime.now().toUtc().toIso8601String();

    await db.db.insert('local_leads', {
      'tenant_id': tenantId,
      'offline_uuid': uuid,
      'name': name.trim(),
      'contact_person': _nullable(contactPerson),
      'phone': _nullable(phone),
      'email': _nullable(email),
      'address': _nullable(address),
      'source': source,
      'stage': 'new',
      'priority': priority,
      'estimated_value': estimatedValue,
      'currency': currency.trim().toUpperCase(),
      'probability': 10,
      'expected_close_date': expectedCloseDate == null
          ? null
          : _dateKey(expectedCloseDate),
      'notes': _nullable(notes),
      'last_activity_at': now,
      'sync_status': 'pending_create',
      'pending_conversion': 0,
      'created_at': now,
      'updated_at': now,
    });

    return uuid;
  }

  Future<void> updateStageLocal({
    required String tenantId,
    required String offlineUuid,
    required String stage,
    String? lostReason,
  }) async {
    final row = await _lead(tenantId, offlineUuid);
    final current = row['sync_status']?.toString() ?? 'synced';
    final next = current.contains('create')
        ? 'pending_create'
        : 'pending_update';
    final now = DateTime.now().toUtc().toIso8601String();

    await db.db.update(
      'local_leads',
      {
        'stage': stage,
        'probability': _probability(stage),
        'lost_reason': stage == 'lost' ? _nullable(lostReason) : null,
        'sync_status': next,
        'last_error': null,
        'last_activity_at': now,
        'updated_at': now,
      },
      where: 'tenant_id=? AND offline_uuid=?',
      whereArgs: [tenantId, offlineUuid],
    );
  }

  Future<String> addActivityLocal({
    required String tenantId,
    required String leadOfflineUuid,
    required String type,
    required String notes,
  }) async {
    await _lead(tenantId, leadOfflineUuid);
    final uuid = const Uuid().v4();
    final now = DateTime.now().toUtc().toIso8601String();

    await db.db.insert('local_lead_activities', {
      'tenant_id': tenantId,
      'offline_uuid': uuid,
      'lead_offline_uuid': leadOfflineUuid,
      'type': type,
      'notes': notes.trim(),
      'occurred_at': now,
      'sync_status': 'pending_create',
      'created_at': now,
      'updated_at': now,
    });
    await db.db.update(
      'local_leads',
      {'last_activity_at': now, 'updated_at': now},
      where: 'tenant_id=? AND offline_uuid=?',
      whereArgs: [tenantId, leadOfflineUuid],
    );

    return uuid;
  }

  Future<void> convertLocal({
    required String tenantId,
    required String offlineUuid,
  }) async {
    await _lead(tenantId, offlineUuid);
    final now = DateTime.now().toUtc().toIso8601String();
    await db.db.update(
      'local_leads',
      {
        'stage': 'won',
        'probability': 100,
        'pending_conversion': 1,
        'last_activity_at': now,
        'last_error': null,
        'updated_at': now,
      },
      where: 'tenant_id=? AND offline_uuid=?',
      whereArgs: [tenantId, offlineUuid],
    );
  }

  Future<int> pendingCount(String tenantId) async {
    final leadRows = await db.db.rawQuery(
      'SELECT COUNT(*) AS total FROM local_leads '
      'WHERE tenant_id=? AND (sync_status<>? OR pending_conversion=1)',
      [tenantId, 'synced'],
    );
    final activityRows = await db.db.rawQuery(
      'SELECT COUNT(*) AS total FROM local_lead_activities '
      'WHERE tenant_id=? AND sync_status<>?',
      [tenantId, 'synced'],
    );
    return (leadRows.first['total'] as int? ?? 0) +
        (activityRows.first['total'] as int? ?? 0);
  }

  Future<LeadSyncResult> syncPending(String tenantId) async {
    if (!await ConnectivityGate.instance.isOnline()) {
      return const LeadSyncResult(synced: 0, failed: 0);
    }

    var synced = 0;
    var failed = 0;
    final leads = await db.db.query(
      'local_leads',
      where: 'tenant_id=? AND (sync_status<>? OR pending_conversion=1)',
      whereArgs: [tenantId, 'synced'],
      orderBy: 'created_at ASC',
    );

    for (final raw in leads) {
      final row = Map<String, dynamic>.from(raw);
      final offlineUuid = row['offline_uuid'].toString();
      if (!await retry.shouldAttempt(
        tenantId: tenantId,
        entityType: 'lead',
        entityUuid: offlineUuid,
      )) {
        continue;
      }

      try {
        var serverUuid = row['server_uuid']?.toString();
        var result = <String, dynamic>{};
        final status = row['sync_status']?.toString() ?? 'synced';

        if (status == 'pending_create' || status == 'failed_create') {
          result = Map<String, dynamic>.from(
            await api.post('leads', data: _createPayload(row)) as Map,
          );
          serverUuid = result['id']?.toString() ?? offlineUuid;
        } else if (status == 'pending_update' || status == 'failed_update') {
          serverUuid ??= offlineUuid;
          result = Map<String, dynamic>.from(
            await api.patch('leads/$serverUuid', data: _updatePayload(row))
                as Map,
          );
        }

        if ((row['pending_conversion'] as int? ?? 0) == 1) {
          serverUuid ??= offlineUuid;
          result = Map<String, dynamic>.from(
            await api.post('leads/$serverUuid/convert') as Map,
          );
        }

        await _saveServerLead(
          tenantId,
          offlineUuid,
          result.isEmpty ? row : result,
          serverUuid: serverUuid ?? offlineUuid,
          synced: true,
        );
        await retry.clear(
          tenantId: tenantId,
          entityType: 'lead',
          entityUuid: offlineUuid,
        );
        synced++;
      } catch (error) {
        final failure = await retry.recordFailure(
          tenantId: tenantId,
          entityType: 'lead',
          entityUuid: offlineUuid,
          error: error,
        );
        final status = row['sync_status']?.toString() ?? '';
        await db.db.update(
          'local_leads',
          {
            'sync_status': status.contains('create')
                ? 'failed_create'
                : 'failed_update',
            'last_error': failure.message,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'tenant_id=? AND offline_uuid=?',
          whereArgs: [tenantId, offlineUuid],
        );
        failed++;
      }
    }

    final activities = await db.db.query(
      'local_lead_activities',
      where: 'tenant_id=? AND sync_status<>?',
      whereArgs: [tenantId, 'synced'],
      orderBy: 'occurred_at ASC',
    );

    for (final raw in activities) {
      final row = Map<String, dynamic>.from(raw);
      final offlineUuid = row['offline_uuid'].toString();
      final leadOfflineUuid = row['lead_offline_uuid'].toString();
      final lead = await _lead(tenantId, leadOfflineUuid);
      final leadServerUuid = lead['server_uuid']?.toString();

      if (leadServerUuid == null || leadServerUuid.isEmpty) {
        continue;
      }
      if (!await retry.shouldAttempt(
        tenantId: tenantId,
        entityType: 'lead_activity',
        entityUuid: offlineUuid,
      )) {
        continue;
      }

      try {
        final result = Map<String, dynamic>.from(
          await api.post(
            'leads/$leadServerUuid/activities',
            data: {
              'offline_uuid': offlineUuid,
              'type': row['type'],
              'notes': row['notes'],
            },
          ) as Map,
        );
        await db.db.update(
          'local_lead_activities',
          {
            'server_uuid': result['id']?.toString() ?? offlineUuid,
            'sync_status': 'synced',
            'last_error': null,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'tenant_id=? AND offline_uuid=?',
          whereArgs: [tenantId, offlineUuid],
        );
        await retry.clear(
          tenantId: tenantId,
          entityType: 'lead_activity',
          entityUuid: offlineUuid,
        );
        synced++;
      } catch (error) {
        final failure = await retry.recordFailure(
          tenantId: tenantId,
          entityType: 'lead_activity',
          entityUuid: offlineUuid,
          error: error,
        );
        await db.db.update(
          'local_lead_activities',
          {
            'sync_status': 'failed_create',
            'last_error': failure.message,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'tenant_id=? AND offline_uuid=?',
          whereArgs: [tenantId, offlineUuid],
        );
        failed++;
      }
    }

    return LeadSyncResult(synced: synced, failed: failed);
  }

  Future<void> refresh(String tenantId) async {
    if (!await ConnectivityGate.instance.isOnline()) return;
    final data = await api.get('leads');
    final rows = (data as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();

    for (final row in rows) {
      final uuid = row['id']?.toString();
      if (uuid == null || uuid.isEmpty) continue;
      final existing = await db.db.query(
        'local_leads',
        where: 'tenant_id=? AND (server_uuid=? OR offline_uuid=?)',
        whereArgs: [tenantId, uuid, uuid],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final local = existing.first;
        if (local['sync_status']?.toString() != 'synced' ||
            (local['pending_conversion'] as int? ?? 0) == 1) {
          continue;
        }
        await _saveServerLead(
          tenantId,
          local['offline_uuid'].toString(),
          row,
          serverUuid: uuid,
          synced: true,
        );
      } else {
        await _insertServerLead(tenantId, uuid, row);
      }
    }
  }

  Future<void> refreshDetails(String tenantId, String offlineUuid) async {
    if (!await ConnectivityGate.instance.isOnline()) return;
    final local = await _lead(tenantId, offlineUuid);
    final serverUuid = local['server_uuid']?.toString() ?? offlineUuid;
    final data = Map<String, dynamic>.from(
      await api.get('leads/$serverUuid') as Map,
    );
    await _saveServerLead(
      tenantId,
      offlineUuid,
      data,
      serverUuid: serverUuid,
      synced: local['sync_status']?.toString() == 'synced',
    );

    final activities = (data['activities'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row));
    for (final activity in activities) {
      final uuid = activity['id']?.toString();
      if (uuid == null || uuid.isEmpty) continue;
      final existing = await db.db.query(
        'local_lead_activities',
        columns: ['sync_status'],
        where: 'tenant_id=? AND (server_uuid=? OR offline_uuid=?)',
        whereArgs: [tenantId, uuid, uuid],
        limit: 1,
      );
      if (existing.isNotEmpty && existing.first['sync_status'] != 'synced') {
        continue;
      }
      await db.db.insert('local_lead_activities', {
        'tenant_id': tenantId,
        'offline_uuid': uuid,
        'server_uuid': uuid,
        'lead_offline_uuid': offlineUuid,
        'type': activity['type'] ?? 'note',
        'notes': activity['notes'],
        'occurred_at':
            activity['occurred_at'] ?? DateTime.now().toUtc().toIso8601String(),
        'sync_status': 'synced',
        'created_at':
            activity['occurred_at'] ?? DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<Map<String, dynamic>> _lead(
    String tenantId,
    String offlineUuid,
  ) async {
    final rows = await db.db.query(
      'local_leads',
      where: 'tenant_id=? AND offline_uuid=?',
      whereArgs: [tenantId, offlineUuid],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Lead not found.');
    return Map<String, dynamic>.from(rows.first);
  }

  Map<String, dynamic> _createPayload(Map<String, dynamic> row) => {
    'offline_uuid': row['offline_uuid'],
    'name': row['name'],
    if (row['contact_person'] != null) 'contact_person': row['contact_person'],
    if (row['phone'] != null) 'phone': row['phone'],
    if (row['email'] != null) 'email': row['email'],
    if (row['address'] != null) 'address': row['address'],
    'source': row['source'],
    'stage': row['stage'],
    'priority': row['priority'],
    if (row['estimated_value'] != null)
      'estimated_value': row['estimated_value'],
    'currency': row['currency'],
    if (row['expected_close_date'] != null)
      'expected_close_date': row['expected_close_date'],
    if (row['notes'] != null) 'notes': row['notes'],
  };

  Map<String, dynamic> _updatePayload(Map<String, dynamic> row) => {
    'stage': row['stage'],
    'priority': row['priority'],
    if (row['estimated_value'] != null)
      'estimated_value': row['estimated_value'],
    'currency': row['currency'],
    if (row['expected_close_date'] != null)
      'expected_close_date': row['expected_close_date'],
    if (row['lost_reason'] != null) 'lost_reason': row['lost_reason'],
    if (row['notes'] != null) 'notes': row['notes'],
  };

  Future<void> _insertServerLead(
    String tenantId,
    String uuid,
    Map<String, dynamic> row,
  ) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await db.db.insert('local_leads', {
      'tenant_id': tenantId,
      'offline_uuid': uuid,
      'server_uuid': uuid,
      ..._serverColumns(row),
      'sync_status': 'synced',
      'pending_conversion': 0,
      'created_at': now,
      'updated_at': row['updated_at'] ?? now,
    });
  }

  Future<void> _saveServerLead(
    String tenantId,
    String offlineUuid,
    Map<String, dynamic> row, {
    required String serverUuid,
    required bool synced,
  }) async {
    await db.db.update(
      'local_leads',
      {
        'server_uuid': serverUuid,
        ..._serverColumns(row),
        if (synced) 'sync_status': 'synced',
        if (synced) 'pending_conversion': 0,
        if (synced) 'last_error': null,
        'updated_at':
            row['updated_at'] ?? DateTime.now().toUtc().toIso8601String(),
      },
      where: 'tenant_id=? AND offline_uuid=?',
      whereArgs: [tenantId, offlineUuid],
    );
  }

  Map<String, dynamic> _serverColumns(Map<String, dynamic> row) => {
    if (row.containsKey('name')) 'name': row['name'],
    if (row.containsKey('contact_person'))
      'contact_person': row['contact_person'],
    if (row.containsKey('phone')) 'phone': row['phone'],
    if (row.containsKey('email')) 'email': row['email'],
    if (row.containsKey('address')) 'address': row['address'],
    if (row.containsKey('source')) 'source': row['source'],
    if (row.containsKey('stage')) 'stage': row['stage'],
    if (row.containsKey('priority')) 'priority': row['priority'],
    if (row.containsKey('estimated_value'))
      'estimated_value': row['estimated_value'],
    if (row.containsKey('currency')) 'currency': row['currency'],
    if (row.containsKey('probability')) 'probability': row['probability'],
    if (row.containsKey('expected_close_date'))
      'expected_close_date': row['expected_close_date'],
    if (row.containsKey('lost_reason')) 'lost_reason': row['lost_reason'],
    if (row.containsKey('notes')) 'notes': row['notes'],
    if (row.containsKey('territory_id')) 'territory_uuid': row['territory_id'],
    if (row.containsKey('territory_name'))
      'territory_name': row['territory_name'],
    if (row.containsKey('converted_customer_id'))
      'converted_customer_uuid': row['converted_customer_id'],
    if (row.containsKey('converted_customer_name'))
      'converted_customer_name': row['converted_customer_name'],
    if (row.containsKey('last_activity_at'))
      'last_activity_at': row['last_activity_at'],
    if (row.containsKey('converted_at')) 'converted_at': row['converted_at'],
  };

  int _probability(String stage) => switch (stage) {
    'new' => 10,
    'contacted' => 25,
    'qualified' => 50,
    'proposal' => 65,
    'negotiation' => 80,
    'won' => 100,
    'lost' => 0,
    _ => 10,
  };

  String? _nullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

class LeadSyncResult {
  const LeadSyncResult({required this.synced, required this.failed});
  final int synced;
  final int failed;
}
