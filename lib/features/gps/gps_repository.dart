import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/api/api_client.dart';
import '../../core/db/app_database.dart';

class GpsRepository {
  GpsRepository({required this.api, required this.db});
  final ApiClient api;
  final AppDatabase db;
  final _battery = Battery();
  Future<void> store({
    required double latitude,
    required double longitude,
    required double accuracy,
    double? altitude,
    double? speed,
    double? heading,
    bool isMock = false,
    DateTime? recordedAt,
  }) async {
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude.abs() > 90 ||
        longitude.abs() > 180 ||
        (latitude == 0 && longitude == 0) ||
        accuracy > 100 ||
        accuracy < 0) {
      return;
    }
    final at = (recordedAt ?? DateTime.now()).toUtc();
    if (at.isAfter(DateTime.now().toUtc().add(const Duration(minutes: 5)))) {
      return;
    }
    final last = await db.db.query(
      'local_gps_points',
      orderBy: 'id DESC',
      limit: 1,
    );
    if (last.isNotEmpty) {
      final l = last.first;
      final lt = DateTime.parse(l['recorded_at'] as String);
      if (at.difference(lt).abs() < const Duration(seconds: 5) &&
          _distance(
                latitude,
                longitude,
                l['latitude'] as double,
                l['longitude'] as double,
              ) <
              5) {
        return;
      }
    }
    final battery = await _battery.batteryLevel;
    final charging = (await _battery.batteryState) == BatteryState.charging;
    final conn = await Connectivity().checkConnectivity();
    final net = conn.contains(ConnectivityResult.wifi)
        ? 'wifi'
        : conn.any((x) => x == ConnectivityResult.mobile)
        ? 'cellular'
        : 'offline';
    final max =
        Sqflite.firstIntValue(
          await db.db.rawQuery(
            'SELECT MAX(sequence_number) FROM local_gps_points',
          ),
        ) ??
        0;
    await db.db.insert('local_gps_points', {
      'client_uuid': const Uuid().v4(),
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
      'accuracy': accuracy,
      'speed': speed,
      'heading': heading,
      'battery_level': battery,
      'is_charging': charging ? 1 : 0,
      'network_status': net,
      'is_mock_location': isMock ? 1 : 0,
      'provider': 'fused',
      'recorded_at': at.toIso8601String(),
      'sequence_number': max + 1,
      'sync_status': 'pending',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<int> pendingCount() async =>
      Sqflite.firstIntValue(
        await db.db.rawQuery(
          'SELECT COUNT(*) FROM local_gps_points WHERE sync_status="pending"',
        ),
      ) ??
      0;
  Future<void> upload() async {
    final rows = await db.db.query(
      'local_gps_points',
      where: 'sync_status=?',
      whereArgs: ['pending'],
      orderBy: 'sequence_number ASC',
      limit: 100,
    );
    if (rows.isEmpty) return;
    final batch = const Uuid().v4();
    final locations = rows
        .map(
          (r) => {
            'client_uuid': r['client_uuid'],
            'latitude': r['latitude'],
            'longitude': r['longitude'],
            'accuracy': r['accuracy'],
            'altitude': r['altitude'],
            'speed': r['speed'],
            'heading': r['heading'],
            'battery_level': r['battery_level'],
            'is_charging': r['is_charging'] == 1,
            'network_status': r['network_status'],
            'is_mock_location': r['is_mock_location'] == 1,
            'provider': r['provider'],
            'recorded_at': r['recorded_at'],
            'sequence_number': r['sequence_number'],
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
    final accepted = {
      ...List<String>.from((data['accepted_uuids'] ?? []).map((x) => '$x')),
      ...List<String>.from((data['duplicate_uuids'] ?? []).map((x) => '$x')),
    };
    final rejected = List<Map<String, dynamic>>.from(
      (data['rejected_details'] ?? []).map((x) => Map<String, dynamic>.from(x)),
    );
    for (final id in accepted) {
      await db.db.update(
        'local_gps_points',
        {
          'sync_status': 'uploaded',
          'uploaded_at': DateTime.now().toUtc().toIso8601String(),
          'batch_uuid': batch,
        },
        where: 'client_uuid=?',
        whereArgs: [id],
      );
    }
    for (final item in rejected) {
      final id = '${item['client_uuid']}';
      if (id != 'null') {
        await db.db.update(
          'local_gps_points',
          {
            'sync_status': 'rejected',
            'last_error': '${item['code']}: ${item['reason']}',
            'batch_uuid': batch,
          },
          where: 'client_uuid=?',
          whereArgs: [id],
        );
      }
    }
  }

  double _distance(double a, double b, double c, double d) {
    const k = 111139.0;
    final dx = (a - c) * k, dy = (b - d) * k;
    return (dx * dx + dy * dy).sqrt();
  }
}

extension on double {
  double sqrt() {
    var x = this;
    if (x <= 0) return 0;
    var z = x;
    for (var i = 0; i < 10; i++) {
      z = (z + x / z) / 2;
    }
    return z;
  }
}
