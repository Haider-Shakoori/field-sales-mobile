import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../core/api/api_client.dart';
import '../../core/db/app_database.dart';

class CustomerCallRepository {
  CustomerCallRepository({required this.api, required this.db});

  final ApiClient api;
  final AppDatabase db;

  Future<String> log({
    required String customerUuid,
    required String phoneNumber,
    required DateTime initiatedAt,
    String? visitUuid,
    String? outcome,
    String? notes,
  }) async {
    final uuid = const Uuid().v4();
    final now = DateTime.now().toUtc().toIso8601String();

    await db.db.transaction((txn) async {
      await txn.insert('local_call_activities', {
        'offline_uuid': uuid,
        'customer_uuid': customerUuid,
        'visit_uuid': visitUuid,
        'phone_number': phoneNumber,
        'initiated_at': initiatedAt.toUtc().toIso8601String(),
        'outcome': outcome,
        'notes': notes,
        'sync_status': 'pending',
        'created_at': now,
        'updated_at': now,
      });

      await txn.insert('sync_queue', {
        'entity_type': 'customer_call',
        'entity_uuid': uuid,
        'action': 'create',
        'payload': jsonEncode({
          'offline_uuid': uuid,
          'customer_uuid': customerUuid,
          'visit_uuid': visitUuid,
          'phone_number': phoneNumber,
          'initiated_at': initiatedAt.toUtc().toIso8601String(),
          'outcome': outcome,
          'notes': notes,
        }),
        'priority': 60,
        'status': 'pending',
        'created_at': now,
        'updated_at': now,
      });
    });

    return uuid;
  }

  Future<List<Map<String, dynamic>>> history(String customerUuid) =>
      db.db.query(
        'local_call_activities',
        where: 'customer_uuid=?',
        whereArgs: [customerUuid],
        orderBy: 'initiated_at DESC',
      );

  Future<void> drain() async {
    final rows = await db.db.query(
      'sync_queue',
      where: 'entity_type=? AND status IN (?,?)',
      whereArgs: ['customer_call', 'pending', 'failed'],
      orderBy: 'id ASC',
    );

    for (final row in rows) {
      try {
        final result = Map<String, dynamic>.from(
          await api.post(
            'customer-calls',
            data: jsonDecode(row['payload'] as String),
          ),
        );

        await db.db.transaction((txn) async {
          await txn.update(
            'sync_queue',
            {
              'status': 'synced',
              'server_id': result['id'],
              'server_uuid': result['uuid'],
              'error_message': null,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            },
            where: 'id=?',
            whereArgs: [row['id']],
          );
          await txn.update(
            'local_call_activities',
            {'server_id': result['id'], 'sync_status': 'synced'},
            where: 'offline_uuid=?',
            whereArgs: [row['entity_uuid']],
          );
        });
      } catch (error) {
        await db.db.update(
          'sync_queue',
          {
            'status': 'failed',
            'attempts': (row['attempts'] as int) + 1,
            'error_message': '$error',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'id=?',
          whereArgs: [row['id']],
        );
        break;
      }
    }
  }
}
