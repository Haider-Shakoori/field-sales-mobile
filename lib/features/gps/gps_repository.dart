import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/api/api_client.dart';
import '../../core/db/app_database.dart';
import '../../core/sync/sync_retry_store.dart';

class GpsRepository {
  GpsRepository({required this.api, required this.db})
      : retry = SyncRetryStore(db);

  final ApiClient api;
  final AppDatabase db;
  final SyncRetryStore retry;
  final _battery = Battery();

  Future<void> store({
    required String tenantId,
    required double latitude,
    required double longitude,
    required double accuracy,
    double? altitude,
    double? speed,
    double? heading,
    bool isMock = false,
    DateTime? recordedAt,
  }) async {
    if (tenantId.isEmpty ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        latitude.abs() > 90 ||
        longitude.abs() > 180 ||
        (latitude == 0 && longitude == 0) ||
        !accuracy.isFinite ||
        accuracy > 200 ||
        accuracy < 0 ||
        (speed != null && (!speed.isFinite || speed < 0 || speed > 55)) ||
        (heading != null &&
            (!heading.isFinite || heading < 0 || heading > 360))) {
      return;
    }

    final at = (recordedAt ?? DateTime.now()).toUtc();
    if (at.isAfter(DateTime.now().toUtc().add(const Duration(minutes: 5)))) {
      return;
    }

    final last = await db.db.query(
      'local_gps_points',
      where: 'tenant_id=?',
      whereArgs: [tenantId],
      orderBy: 'id DESC',
      limit: 1,
    );

    if (last.isNotEmpty) {
      final previous = last.first;
      final previousAt = DateTime.parse(previous['recorded_at'] as String);

      if (at.difference(previousAt).abs() < const Duration(seconds: 5) &&
          _distance(
                latitude,
                longitude,
                previous['latitude'] as double,
                previous['longitude'] as double,
              ) <
              5) {
        return;
      }
    }

    final battery = await _battery.batteryLevel;
    final charging = (await _battery.batteryState) == BatteryState.charging;
    final connectivity = await Connectivity().checkConnectivity();
    final network = connectivity.contains(ConnectivityResult.wifi)
        ? 'wifi'
        : connectivity.any((item) => item == ConnectivityResult.mobile)
        ? 'cellular'
        : 'offline';

    final maxSequence =
        Sqflite.firstIntValue(
          await db.db.rawQuery(
            'SELECT MAX(sequence_number) FROM local_gps_points '
            'WHERE tenant_id=?',
            [tenantId],
          ),
        ) ??
        0;

    await db.db.insert('local_gps_points', {
      'tenant_id': tenantId,
      'client_uuid': const Uuid().v4(),
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
      'accuracy': accuracy,
      'speed': speed,
      'heading': heading,
      'battery_level': battery,
      'is_charging': charging ? 1 : 0,
      'network_status': network,
      'is_mock_location': isMock ? 1 : 0,
      'provider': 'fused',
      'recorded_at': at.toIso8601String(),
      'sequence_number': maxSequence + 1,
      'sync_status': 'pending',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<int> pendingCount(String tenantId) async =>
      Sqflite.firstIntValue(
        await db.db.rawQuery(
          'SELECT COUNT(*) FROM local_gps_points '
          'WHERE tenant_id=? AND sync_status="pending"',
          [tenantId],
        ),
      ) ??
      0;

  Future<void> upload(String tenantId) async {
    if (tenantId.isEmpty) return;

    if (!await retry.shouldAttempt(
      tenantId: tenantId,
      entityType: 'gps',
      entityUuid: 'upload',
    )) {
      return;
    }

    try {
      final rows = await db.db.query(
      'local_gps_points',
      where: 'tenant_id=? AND sync_status=?',
      whereArgs: [tenantId, 'pending'],
      orderBy: 'sequence_number ASC',
      limit: 100,
    );

      if (rows.isEmpty) {
        await retry.clear(
          tenantId: tenantId,
          entityType: 'gps',
          entityUuid: 'upload',
        );
        return;
      }

      final batch = const Uuid().v4();
    final locations = rows
        .map(
          (row) => {
            'client_uuid': row['client_uuid'],
            'latitude': row['latitude'],
            'longitude': row['longitude'],
            'accuracy': row['accuracy'],
            'altitude': row['altitude'],
            'speed': row['speed'],
            'heading': row['heading'],
            'battery_level': row['battery_level'],
            'is_charging': row['is_charging'] == 1,
            'network_status': row['network_status'],
            'is_mock_location': row['is_mock_location'] == 1,
            'provider': row['provider'],
            'recorded_at': row['recorded_at'],
            'sequence_number': row['sequence_number'],
          },
        )
        .toList();

    final data = Map<String, dynamic>.from(
      await api.post(
        'gps/locations',
        data: {'batch_uuid': batch, 'locations': locations},
        headers: {'X-Idempotency-Key': batch},
      ),
    );

    final uploaded = <String>{
      ...List<String>.from(
        (data['accepted_uuids'] ?? []).map((value) => '$value'),
      ),
      ...List<String>.from(
        (data['duplicate_uuids'] ?? []).map((value) => '$value'),
      ),
    };

    final rejectedDetails = List<Map<String, dynamic>>.from(
      (data['rejected_details'] ?? []).map(
        (value) => Map<String, dynamic>.from(value),
      ),
    );
    final rejectedByUuid = <String, Map<String, dynamic>>{};

    for (final detail in rejectedDetails) {
      final uuid = '${detail['client_uuid']}';
      if (uuid != 'null' && uuid.isNotEmpty) {
        rejectedByUuid[uuid] = detail;
      }
    }

    for (final value in (data['rejected_uuids'] ?? [])) {
      final uuid = '$value';
      rejectedByUuid.putIfAbsent(
        uuid,
        () => {
          'client_uuid': uuid,
          'code': 'rejected',
          'reason': 'Server rejected this GPS point.',
        },
      );
    }

      await db.db.transaction((txn) async {
      final uploadedAt = DateTime.now().toUtc().toIso8601String();

      for (final uuid in uploaded) {
        await txn.update(
          'local_gps_points',
          {
            'sync_status': 'uploaded',
            'uploaded_at': uploadedAt,
            'batch_uuid': batch,
            'last_error': null,
          },
          where: 'tenant_id=? AND client_uuid=?',
          whereArgs: [tenantId, uuid],
        );
      }

      for (final entry in rejectedByUuid.entries) {
        final detail = entry.value;
        final code = '${detail['code'] ?? 'rejected'}';
        final reason =
            '${detail['reason'] ?? 'Server rejected this GPS point.'}';

        await txn.update(
          'local_gps_points',
          {
            'sync_status': 'rejected',
            'last_error': 'rejected: $code ($reason)',
            'batch_uuid': batch,
          },
          where: 'tenant_id=? AND client_uuid=?',
          whereArgs: [tenantId, entry.key],
        );
      }
    });

      await retry.clear(
        tenantId: tenantId,
        entityType: 'gps',
        entityUuid: 'upload',
      );
    } catch (error) {
      await retry.recordFailure(
        tenantId: tenantId,
        entityType: 'gps',
        entityUuid: 'upload',
        error: error,
      );
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> current({String? userId}) async {
    final data = await api.get(
      'gps/current',
      query: userId == null ? null : {'user_id': userId},
    );

    return data == null ? null : Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> history({String? date, String? userId}) async {
    final query = <String, dynamic>{};
    if (date != null) query['date'] = date;
    if (userId != null) query['user_id'] = userId;

    return Map<String, dynamic>.from(
      await api.get('gps/history', query: query.isEmpty ? null : query),
    );
  }

  double _distance(double a, double b, double c, double d) {
    const metresPerDegree = 111139.0;
    final dx = (a - c) * metresPerDegree;
    final dy = (b - d) * metresPerDegree;

    return (dx * dx + dy * dy).sqrt();
  }
}

extension on double {
  double sqrt() {
    var value = this;
    if (value <= 0) return 0;

    var estimate = value;
    for (var index = 0; index < 10; index++) {
      estimate = (estimate + value / estimate) / 2;
    }

    return estimate;
  }
}
