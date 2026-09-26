import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../core/db/app_database.dart';
import '../../core/db/local_first_transaction.dart';
import '../../core/sync/connectivity_gate.dart';
import '../../core/sync/sync_retry_store.dart';
import '../master_data/master_data_repository.dart';
import '../master_data/master_data_source.dart';

class CustomerRepository {
  CustomerRepository({
    required this.database,
    required this.transactions,
    required this.masterData,
    required this.source,
  }) : retry = SyncRetryStore(database);

  final AppDatabase database;
  final LocalFirstTransaction transactions;
  final MasterDataRepository masterData;
  final MasterDataSource source;
  final SyncRetryStore retry;

  Future<Map<String, dynamic>> createOffline({
    required String tenantId,
    required String name,
    String? code,
    String? phone,
    String? address,
    double? latitude,
    double? longitude,
  }) async {
    final uuid = const Uuid().v4();
    final now = DateTime.now().toUtc().toIso8601String();
    final payload = <String, dynamic>{
      'id': uuid,
      'offline_uuid': uuid,
      'code': code?.trim().isEmpty == true ? null : code?.trim(),
      'name': name.trim(),
      'phone': phone?.trim().isEmpty == true ? null : phone?.trim(),
      'address': address?.trim().isEmpty == true ? null : address?.trim(),
      'latitude': latitude,
      'longitude': longitude,
      'geofence_radius_meters': 100,
      'route_ids': <String>[],
      'is_active': true,
      'updated_at': now,
    };

    await transactions.run((transaction) async {
      await transaction.insert('customers', {
        'tenant_id': tenantId,
        'uuid': uuid,
        'payload': jsonEncode(payload),
        'cached_at': now,
        'source': 'local',
        'sync_status': 'pending',
      });

      await transactions.enqueue(
        transaction,
        tenantId: tenantId,
        entityType: 'customer',
        entityUuid: uuid,
        action: 'create',
        payload: jsonEncode({
          'offline_uuid': uuid,
          if (payload['code'] != null) 'code': payload['code'],
          'name': payload['name'],
          if (payload['phone'] != null) 'phone': payload['phone'],
          if (payload['address'] != null) 'address': payload['address'],
          'latitude': ?latitude,
          'longitude': ?longitude,
          'geofence_radius_meters': 100,
        }),
        priority: 20,
      );
    });

    return payload;
  }

  Future<Map<String, dynamic>> updateOffline({
    required String tenantId,
    required String customerUuid,
    required String name,
    String? code,
    String? phone,
    String? address,
    required double latitude,
    required double longitude,
  }) async {
    final rows = await database.db.query(
      'customers',
      where: 'tenant_id = ? AND uuid = ?',
      whereArgs: [tenantId, customerUuid],
      limit: 1,
    );

    if (rows.isEmpty) {
      throw StateError('Customer is not available offline.');
    }

    final existing = Map<String, dynamic>.from(
      jsonDecode(rows.first['payload'] as String) as Map,
    );
    final now = DateTime.now().toUtc().toIso8601String();
    final updated = <String, dynamic>{
      ...existing,
      'name': name.trim(),
      'code': code?.trim().isEmpty == true ? existing['code'] : code?.trim(),
      'phone': phone?.trim().isEmpty == true ? null : phone?.trim(),
      'address': address?.trim().isEmpty == true ? null : address?.trim(),
      'latitude': latitude,
      'longitude': longitude,
      'geofence_radius_meters': existing['geofence_radius_meters'] ?? 100,
      'updated_at': now,
    };

    final syncPayload = <String, dynamic>{
      'name': updated['name'],
      if (updated['code'] != null) 'code': updated['code'],
      'phone': updated['phone'],
      'address': updated['address'],
      'latitude': latitude,
      'longitude': longitude,
      'geofence_radius_meters': updated['geofence_radius_meters'],
    };

    await transactions.run((transaction) async {
      await transaction.update(
        'customers',
        {
          'payload': jsonEncode(updated),
          'cached_at': now,
          'source': 'local',
          'sync_status': 'pending',
        },
        where: 'tenant_id = ? AND uuid = ?',
        whereArgs: [tenantId, customerUuid],
      );

      final pendingCreates = await transaction.query(
        'sync_queue',
        where:
            'tenant_id = ? AND entity_type = ? AND entity_uuid = ? '
            'AND action = ? AND status IN (?,?,?)',
        whereArgs: [
          tenantId,
          'customer',
          customerUuid,
          'create',
          'pending',
          'failed',
          'blocked',
        ],
        orderBy: 'id ASC',
        limit: 1,
      );

      if (pendingCreates.isNotEmpty) {
        final createPayload = Map<String, dynamic>.from(
          jsonDecode(pendingCreates.first['payload'] as String) as Map,
        );

        await transaction.update(
          'sync_queue',
          {
            'payload': jsonEncode({...createPayload, ...syncPayload}),
            'status': 'pending',
            'attempts': 0,
            'error_message': null,
            'next_retry_at': null,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [pendingCreates.first['id']],
        );
      } else {
        await transactions.enqueue(
          transaction,
          tenantId: tenantId,
          entityType: 'customer',
          entityUuid: customerUuid,
          action: 'update',
          payload: jsonEncode(syncPayload),
          priority: 21,
        );
      }
    });

    return updated;
  }

  Future<CustomerSyncResult> syncPending(String tenantId) async {
    if (!await ConnectivityGate.instance.isOnline()) {
      return const CustomerSyncResult(synced: 0, failed: 0);
    }

    final rows = await database.db.query(
      'sync_queue',
      where:
          'tenant_id = ? AND entity_type = ? '
          'AND action IN (?,?) AND status IN (?,?,?)',
      whereArgs: [
        tenantId,
        'customer',
        'create',
        'update',
        'pending',
        'failed',
        'blocked',
      ],
      orderBy: 'priority ASC, created_at ASC',
    );

    var synced = 0;
    var failed = 0;

    for (final queueRow in rows) {
      final id = queueRow['id'] as int;
      final entityUuid = queueRow['entity_uuid'].toString();
      final action = queueRow['action']?.toString() ?? 'create';
      final retryUuid = '$entityUuid:$action';

      if (!await retry.shouldAttempt(
        tenantId: tenantId,
        entityType: 'customer',
        entityUuid: retryUuid,
      )) {
        continue;
      }

      final payload = Map<String, dynamic>.from(
        jsonDecode(queueRow['payload'] as String) as Map,
      );

      try {
        final server = action == 'update'
            ? await source.patch('customers/$entityUuid', payload)
            : await source.post('customers', payload);

        await database.db.transaction((transaction) async {
          await masterData.cacheServerRow(
            table: 'customers',
            tenantId: tenantId,
            row: server,
            executor: transaction,
          );

          await transaction.update(
            'sync_queue',
            {
              'status': 'done',
              'server_uuid': server['id']?.toString(),
              'error_message': null,
              'next_retry_at': null,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [id],
          );
        });

        await retry.clear(
          tenantId: tenantId,
          entityType: 'customer',
          entityUuid: retryUuid,
        );
        synced++;
      } catch (error) {
        final failure = await retry.recordFailure(
          tenantId: tenantId,
          entityType: 'customer',
          entityUuid: retryUuid,
          error: error,
        );
        await _markFailure(id, failure);
        failed++;
      }
    }

    return CustomerSyncResult(synced: synced, failed: failed);
  }

  Future<void> _markFailure(int id, SyncFailureState failure) async {
    await database.db.update(
      'sync_queue',
      {
        'status': failure.blocked ? 'blocked' : 'failed',
        'attempts': failure.attempts,
        'error_message': failure.message,
        'next_retry_at': failure.nextRetryAt?.toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id=?',
      whereArgs: [id],
    );
  }
}

class CustomerSyncResult {
  const CustomerSyncResult({required this.synced, required this.failed});

  final int synced;
  final int failed;
}
