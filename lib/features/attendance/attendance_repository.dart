import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../core/api/api_client.dart';
import '../../core/db/app_database.dart';

class AttendanceRepository {
  AttendanceRepository({required this.api, required this.db});
  final ApiClient api;
  final AppDatabase db;
  Future<Map<String, dynamic>?> active() async {
    final r = await db.db.query(
      'local_work_sessions',
      where: 'status=?',
      whereArgs: ['active'],
      limit: 1,
    );
    return r.isEmpty ? null : r.first;
  }

  Future<Map<String, dynamic>?> forDate(String date) async {
    final r = await db.db.query(
      'local_work_sessions',
      where: 'date=?',
      whereArgs: [date],
      limit: 1,
    );
    return r.isEmpty ? null : r.first;
  }

  Future<String> start({
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
        where: 'id=?',
        whereArgs: [session['id']],
      );
      await txn.insert('sync_queue', {
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

  Future<void> drain() async {
    final rows = await db.db.query(
      'sync_queue',
      where: 'entity_type=? AND status IN (?,?)',
      whereArgs: ['attendance', 'pending', 'failed'],
      orderBy: 'priority ASC, id ASC',
    );
    for (final row in rows) {
      try {
        final action = '${row['action']}';
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
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            },
            where: 'id=?',
            whereArgs: [row['id']],
          );
          await txn.update(
            'local_work_sessions',
            {
              'server_id': result['id'],
              'sync_status': 'synced',
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            },
            where: 'offline_uuid=?',
            whereArgs: [row['entity_uuid']],
          );
        });
      } catch (e) {
        await db.db.update(
          'sync_queue',
          {
            'status': 'failed',
            'attempts': (row['attempts'] as int) + 1,
            'error_message': '$e',
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
