import 'dart:convert';
import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/api/api_client.dart';
import '../../core/db/app_database.dart';
import '../master_data/master_models.dart';

class VisitRepository {
  VisitRepository({required this.api, required this.db});

  final ApiClient api;
  final AppDatabase db;

  Future<Map<String, dynamic>?> activeVisit() async {
    final rows = await db.db.query(
      'local_visits',
      where: 'status=?',
      whereArgs: ['checked_in'],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, dynamic>> checkIn({
    required CustomerRecord customer,
    required DateTime at,
    required double latitude,
    required double longitude,
    required double accuracy,
    String? routeUuid,
    bool isPlanned = true,
  }) async {
    final activeSession = await db.db.query(
      'local_work_sessions',
      where: 'status=?',
      whereArgs: ['active'],
      limit: 1,
    );
    if (activeSession.isEmpty) {
      throw StateError('Start your work day before checking in.');
    }

    if (await activeVisit() != null) {
      throw StateError('Another customer visit is already active.');
    }

    final uuid = const Uuid().v4();
    final now = DateTime.now().toUtc().toIso8601String();
    final checkedInAt = at.toUtc().toIso8601String();

    double? distance;
    bool? within;
    if (customer.latitude != null && customer.longitude != null) {
      distance = _distanceMeters(
        latitude,
        longitude,
        customer.latitude!,
        customer.longitude!,
      );
      within = distance <= customer.geofenceRadius;
    }

    await db.db.transaction((txn) async {
      await txn.insert('local_visits', {
        'offline_uuid': uuid,
        'customer_uuid': customer.uuid,
        'route_uuid': routeUuid,
        'work_session_uuid': activeSession.first['offline_uuid'],
        'is_planned': isPlanned ? 1 : 0,
        'status': 'checked_in',
        'checked_in_at': checkedInAt,
        'check_in_latitude': latitude,
        'check_in_longitude': longitude,
        'check_in_accuracy': accuracy,
        'within_geofence': within == null ? null : (within ? 1 : 0),
        'distance_from_customer_m': distance,
        'flags_json': jsonEncode(
          within == false ? ['outside_geofence'] : <String>[],
        ),
        'sync_status': 'pending',
        'created_at': now,
        'updated_at': now,
      });

      await txn.insert('sync_queue', {
        'entity_type': 'visit',
        'entity_uuid': uuid,
        'action': 'check_in',
        'payload': jsonEncode({
          'offline_uuid': uuid,
          'customer_uuid': customer.uuid,
          'route_uuid': routeUuid,
          'latitude': latitude,
          'longitude': longitude,
          'accuracy': accuracy,
          'checked_in_at': checkedInAt,
          'is_planned': isPlanned,
        }),
        'priority': 30,
        'status': 'pending',
        'created_at': now,
        'updated_at': now,
      });
    });

    final row = await activeVisit();
    return row!;
  }

  Future<void> checkOut({
    required Map<String, dynamic> visit,
    required DateTime at,
    required double latitude,
    required double longitude,
    required double accuracy,
    required String outcome,
    String? notes,
  }) async {
    final end = at.toUtc();
    final start = DateTime.parse(visit['checked_in_at'] as String).toUtc();
    if (end.isBefore(start)) {
      throw StateError('Check-out cannot be before check-in.');
    }

    final now = DateTime.now().toUtc().toIso8601String();
    final endedAt = end.toIso8601String();
    final duration = end.difference(start).inMinutes;

    await db.db.transaction((txn) async {
      await txn.update(
        'local_visits',
        {
          'status': 'completed',
          'checked_out_at': endedAt,
          'check_out_latitude': latitude,
          'check_out_longitude': longitude,
          'check_out_accuracy': accuracy,
          'duration_minutes': duration,
          'outcome': outcome,
          'notes': notes,
          'sync_status': 'pending',
          'updated_at': now,
        },
        where: 'offline_uuid=?',
        whereArgs: [visit['offline_uuid']],
      );

      await txn.insert('sync_queue', {
        'entity_type': 'visit',
        'entity_uuid': visit['offline_uuid'],
        'action': 'check_out',
        'payload': jsonEncode({
          'latitude': latitude,
          'longitude': longitude,
          'accuracy': accuracy,
          'checked_out_at': endedAt,
          'outcome': outcome,
          'notes': notes,
        }),
        'priority': 40,
        'status': 'pending',
        'created_at': now,
        'updated_at': now,
      });
    });
  }

  Future<List<Map<String, dynamic>>> history({String? customerUuid}) async {
    return db.db.query(
      'local_visits',
      where: customerUuid == null ? null : 'customer_uuid=?',
      whereArgs: customerUuid == null ? null : [customerUuid],
      orderBy: 'checked_in_at DESC',
    );
  }

  Future<void> drain() async {
    final rows = await db.db.query(
      'sync_queue',
      where: 'entity_type=? AND status IN (?,?)',
      whereArgs: ['visit', 'pending', 'failed'],
      orderBy: 'priority ASC, id ASC',
    );

    for (final row in rows) {
      try {
        final payload = jsonDecode(row['payload'] as String);
        final action = row['action'] as String;
        late Map<String, dynamic> result;

        if (action == 'check_in') {
          result = Map<String, dynamic>.from(
            await api.post('visits/check-in', data: payload),
          );
        } else {
          result = Map<String, dynamic>.from(
            await api.post(
              'visits/${row['entity_uuid']}/check-out',
              data: payload,
            ),
          );
        }

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
            'local_visits',
            {
              'server_id': result['id'],
              'within_geofence': result['within_geofence'] == null
                  ? null
                  : (result['within_geofence'] == true ? 1 : 0),
              'distance_from_customer_m': result['distance_from_customer_m'],
              'flags_json': jsonEncode(result['flags'] ?? const []),
              'sync_status': 'synced',
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            },
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

  double _distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earth = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return earth * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  double _rad(double degrees) => degrees * math.pi / 180;
}
