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
      orderBy: "CASE stage WHEN 'new' THEN 0 WHEN 'contacted' THEN 1 WHEN 'qualified' THEN 2 WHEN 'proposal' THEN 3 WHEN 'negotiation' THEN 4 WHEN 'won' THEN 5 ELSE 6 END, COALESCE(last_activity_at,created_at) DESC",
    );
    return rows.map(Map<String, dynamic>.from).toList();
  }

  Future<List<Map<String, dynamic>>> activities(
    String tenantId,
    String leadUuid,
  ) async {
    final rows = await db.db.query(
      'local_lead_activities',
      where: 'tenant_id=? AND lead_offline_uuid=?',
      whereArgs: [tenantId, leadUuid],
      orderBy: 'occurred_at DESC',
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
      'currency': currency.toUpperCase(),
      'probability': 10,
      'expected_close_date': expectedCloseDate
          ?.toIso8601String()
          .split('T')
          .first,
      'notes': _nullable(notes),
      'last_activity_at': now,
      'pending_conversion': 0,
      'sync_status': 'pending_create',
      'created_at': now,
      'updated_at': now,
    });
    return uuid;
  }

  Future<void> updateLocal({
    required String tenantId,
    required String offlineUuid,
    String? stage,
    String? priority,
    double? estimatedValue,
    String? currency,
    DateTime? expectedCloseDate,
    String? lostReason,
    String? notes,
  }) async {
    final rows = await db.db.query(
      'local_leads',
      columns: ['sync_status'],
      where: 'tenant_id=? AND offline_uuid=?',
      whereArgs: [tenantId, offlineUuid],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Lead not found.');
    final current = rows.first['sync_status']?.toString() ?? 'synced';
    final changes = <String, Object?>{
      'last_activity_at': DateTime.now().toUtc().toIso8601String(),
      'sync_status': current == 'pending_create' || current == 'failed_create'
          ? current
          : 'pending_update',
      'last_error': null,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (stage != null) {
      changes['stage'] = stage;
      changes['probability'] = _probability(stage);
      changes['lost_reason'] = stage == 'lost' ? _nullable(lostReason) : null;
    } else if (lostReason != null) {
      changes['lost_reason'] = _nullable(lostReason);
    }
    if (priority != null) changes['priority'] = priority;
    if (estimatedValue != null) changes['estimated_value'] = estimatedValue;
    if (currency != null) changes['currency'] = currency.toUpperCase();
    if (expectedCloseDate != null) {
      changes['expected_close_date'] = expectedCloseDate
          .toIso8601String()
          .split('T')
          .first;
    }
    if (notes != null) changes['notes'] = _nullable(notes);
    await db.db.update(
      'local_leads',
      changes,
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
    final uuid = const Uuid().v4();
    final now = DateTime.now().toUtc().toIso8601String();
    await db.db.insert('local_lead_activities', {
      'tenant_id': tenantId,
      'offline_uuid': uuid,
      'lead_offline_uuid': leadOfflineUuid,
      'type': type,
      'notes': notes.trim(),
      'occurred_at': now,
      'sync_status': 'pending',
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

  Future<void> requestConversion(String tenantId, String offlineUuid) async {
    await db.db.update(
      'local_leads',
      {
        'stage': 'won',
        'probability': 100,
        'pending_conversion': 1,
        'last_activity_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'tenant_id=? AND offline_uuid=?',
      whereArgs: [tenantId, offlineUuid],
    );
  }

  Future<int> pendingCount(String tenantId) async {
    final leads = await db.db.rawQuery(
      'SELECT COUNT(*) AS total FROM local_leads WHERE tenant_id=? AND (sync_status<>? OR pending_conversion=1)',
      [tenantId, 'synced'],
    );
    final activities = await db.db.rawQuery(
      'SELECT COUNT(*) AS total FROM local_lead_activities WHERE tenant_id=? AND sync_status<>?',
      [tenantId, 'synced'],
    );
    return (leads.first['total'] as int? ?? 0) +
        (activities.first['total'] as int? ?? 0);
  }

  Future<LeadSyncResult> syncPending(String tenantId) async {
    if (!await ConnectivityGate.instance.isOnline()) {
      return const LeadSyncResult(synced: 0, failed: 0);
    }
    var synced = 0;
    var failed = 0;
    final rows = await db.db.query(
      'local_leads',
      where: 'tenant_id=? AND (sync_status<>? OR pending_conversion=1)',
      whereArgs: [tenantId, 'synced'],
      orderBy: 'created_at ASC',
    );
    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw);
      final uuid = row['offline_uuid'].toString();
      if (!await retry.shouldAttempt(
        tenantId: tenantId,
        entityType: 'lead',
        entityUuid: uuid,
      )) {
        continue;
      }
      try {
        var serverUuid = row['server_uuid']?.toString();
        final status = row['sync_status']?.toString() ?? 'synced';
        if (status == 'pending_create' || status == 'failed_create') {
          final result = Map<String, dynamic>.from(
            await api.post('leads', data: _createPayload(row)) as Map,
          );
          serverUuid = result['id']?.toString() ?? uuid;
        } else if (status == 'pending_update' || status == 'failed_update') {
          serverUuid ??= uuid;
          await api.patch('leads/$serverUuid', data: _updatePayload(row));
        }
        if ((row['pending_conversion'] as int? ?? 0) == 1) {
          serverUuid ??= uuid;
          final result = Map<String, dynamic>.from(
            await api.post('leads/$serverUuid/convert', data: const {}) as Map,
          );
          await db.db.update(
            'local_leads',
            {
              'converted_customer_uuid': result['converted_customer_id']
                  ?.toString(),
              'converted_customer_name': result['converted_customer_name']
                  ?.toString(),
              'pending_conversion': 0,
              'stage': result['stage']?.toString() ?? 'won',
              'probability': result['probability'] ?? 100,
            },
            where: 'tenant_id=? AND offline_uuid=?',
            whereArgs: [tenantId, uuid],
          );
        }
        await db.db.update(
          'local_leads',
          {
            'server_uuid': serverUuid ?? uuid,
            'sync_status': 'synced',
            'last_error': null,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'tenant_id=? AND offline_uuid=?',
          whereArgs: [tenantId, uuid],
        );
        await retry.clear(
          tenantId: tenantId,
          entityType: 'lead',
          entityUuid: uuid,
        );
        synced++;
      } catch (error) {
        final failure = await retry.recordFailure(
          tenantId: tenantId,
          entityType: 'lead',
          entityUuid: uuid,
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
          whereArgs: [tenantId, uuid],
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
    for (final row in activities) {
      final activityUuid = row['offline_uuid'].toString();
      final leadRows = await db.db.query(
        'local_leads',
        columns: ['server_uuid', 'offline_uuid'],
        where: 'tenant_id=? AND offline_uuid=?',
        whereArgs: [tenantId, row['lead_offline_uuid']],
        limit: 1,
      );
      if (leadRows.isEmpty || leadRows.first['server_uuid'] == null) continue;
      if (!await retry.shouldAttempt(
        tenantId: tenantId,
        entityType: 'lead_activity',
        entityUuid: activityUuid,
      )) {
        continue;
      }
      try {
        final leadUuid = leadRows.first['server_uuid'].toString();
        final result = Map<String, dynamic>.from(
          await api.post(
            'leads/$leadUuid/activities',
            data: {
              'offline_uuid': activityUuid,
              'type': row['type'],
              'notes': row['notes'],
            },
          ) as Map,
        );
        await db.db.update(
          'local_lead_activities',
          {
            'server_uuid': result['id']?.toString() ?? activityUuid,
            'sync_status': 'synced',
            'last_error': null,
          },
          where: 'tenant_id=? AND offline_uuid=?',
          whereArgs: [tenantId, activityUuid],
        );
        await retry.clear(
          tenantId: tenantId,
          entityType: 'lead_activity',
          entityUuid: activityUuid,
        );
        synced++;
      } catch (error) {
        final failure = await retry.recordFailure(
          tenantId: tenantId,
          entityType: 'lead_activity',
          entityUuid: activityUuid,
          error: error,
        );
        await db.db.update(
          'local_lead_activities',
          {
            'sync_status': failure.blocked ? 'blocked' : 'failed',
            'last_error': failure.message,
          },
          where: 'tenant_id=? AND offline_uuid=?',
          whereArgs: [tenantId, activityUuid],
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
        columns: ['sync_status', 'offline_uuid'],
        where: 'tenant_id=? AND (server_uuid=? OR offline_uuid=?)',
        whereArgs: [tenantId, uuid, uuid],
        limit: 1,
      );
      if (existing.isNotEmpty && existing.first['sync_status'] != 'synced') {
        continue;
      }
      final offlineUuid = existing.isNotEmpty
          ? existing.first['offline_uuid'].toString()
          : uuid;
      await db.db.insert('local_leads', {
        'tenant_id': tenantId,
        'offline_uuid': offlineUuid,
        'server_uuid': uuid,
        'name': row['name'],
        'contact_person': row['contact_person'],
        'phone': row['phone'],
        'email': row['email'],
        'address': row['address'],
        'source': row['source'],
        'stage': row['stage'],
        'priority': row['priority'],
        'estimated_value': row['estimated_value'],
        'currency': row['currency'],
        'probability': row['probability'],
        'expected_close_date': row['expected_close_date'],
        'lost_reason': row['lost_reason'],
        'notes': row['notes'],
        'territory_uuid': row['territory_id'],
        'territory_name': row['territory_name'],
        'converted_customer_uuid': row['converted_customer_id'],
        'converted_customer_name': row['converted_customer_name'],
        'last_activity_at': row['last_activity_at'],
        'converted_at': row['converted_at'],
        'pending_conversion': 0,
        'sync_status': 'synced',
        'last_error': null,
        'created_at':
            row['updated_at'] ?? DateTime.now().toUtc().toIso8601String(),
        'updated_at':
            row['updated_at'] ?? DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
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

  int _probability(String stage) =>
      const {
        'new': 10,
        'contacted': 25,
        'qualified': 50,
        'proposal': 65,
        'negotiation': 80,
        'won': 100,
        'lost': 0,
      }[stage] ??
      10;
  String? _nullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

class LeadSyncResult {
  const LeadSyncResult({required this.synced, required this.failed});
  final int synced;
  final int failed;
}
