import 'dart:math' as math;

import '../../core/api/api_client.dart';
import '../../core/db/app_database.dart';
import '../../core/sync/connectivity_gate.dart';

class MileageRepository {
  MileageRepository({required this.api, required this.db});

  final ApiClient api;
  final AppDatabase db;

  Future<List<Map<String, dynamic>>> history(String tenantId) async {
    if (await ConnectivityGate.instance.isOnline()) {
      try {
        final data = await api.get('mileage/history');

        if (data is List) {
          return data
              .whereType<Map>()
              .map(
                (row) => <String, dynamic>{
                  ...Map<String, dynamic>.from(row),
                  'source': 'server',
                },
              )
              .toList();
        }
      } catch (_) {
        // The offline summary below keeps the feature usable without network.
      }
    }

    return localHistory(tenantId);
  }

  Future<Map<String, dynamic>?> today(String tenantId) async {
    if (await ConnectivityGate.instance.isOnline()) {
      try {
        final data = await api.get('mileage/today');

        if (data is Map) {
          return <String, dynamic>{
            ...Map<String, dynamic>.from(data),
            'source': 'server',
          };
        }
      } catch (_) {
        // Fall through to local computation.
      }
    }

    final rows = await localHistory(tenantId);
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, dynamic>>> localHistory(String tenantId) async {
    final sessions = await db.db.query(
      'local_work_sessions',
      where: 'tenant_id=?',
      whereArgs: [tenantId],
      orderBy: 'date DESC, start_time DESC',
      limit: 30,
    );
    final expenses = await db.db.query(
      'local_expenses',
      where: 'tenant_id=? AND category=? AND status NOT IN (?,?)',
      whereArgs: [tenantId, 'fuel', 'rejected', 'cancelled'],
      orderBy: 'spent_at DESC',
    );

    final rows = <Map<String, dynamic>>[];

    for (final session in sessions) {
      final start = DateTime.tryParse('${session['start_time']}');
      if (start == null) continue;

      final rawEnd = session['end_time']?.toString();
      final end = rawEnd == null || rawEnd.isEmpty
          ? DateTime.now().toUtc()
          : DateTime.tryParse(rawEnd)?.toUtc() ?? DateTime.now().toUtc();
      final gpsDistance = await _gpsDistance(tenantId, start.toUtc(), end);
      final odometerStart = _number(session['odometer_start_km']);
      final odometerEnd = _number(session['odometer_end_km']);
      final odometerDistance =
          odometerStart != null &&
              odometerEnd != null &&
              odometerEnd >= odometerStart
          ? _round(odometerEnd - odometerStart, 2)
          : null;
      final effectiveDistance = odometerDistance ?? gpsDistance;

      final sessionFuel = expenses.where((expense) {
        final at = DateTime.tryParse('${expense['spent_at']}')?.toUtc();
        return at != null && !at.isBefore(start.toUtc()) && !at.isAfter(end);
      }).toList();

      final fuelLiters = _round(
        sessionFuel.fold<double>(
          0,
          (sum, expense) => sum + (_number(expense['fuel_liters']) ?? 0),
        ),
        3,
      );
      final costs = <String, double>{};

      for (final expense in sessionFuel) {
        final currency = expense['currency']?.toString() ?? 'UNKNOWN';
        costs[currency] =
            (costs[currency] ?? 0) + (_number(expense['amount']) ?? 0);
      }

      rows.add({
        'session_uuid': session['offline_uuid'],
        'date': session['date'],
        'status': session['status'],
        'vehicle_reference': session['vehicle_reference'],
        'odometer_start_km': odometerStart,
        'odometer_end_km': odometerEnd,
        'gps_distance_km': gpsDistance,
        'odometer_distance_km': odometerDistance,
        'effective_distance_km': _round(effectiveDistance, 3),
        'distance_variance_km': odometerDistance == null
            ? null
            : _round(odometerDistance - gpsDistance, 3),
        'fuel_liters': fuelLiters,
        'fuel_cost_by_currency': costs.map(
          (currency, amount) => MapEntry(currency, _round(amount, 4)),
        ),
        'km_per_liter': fuelLiters > 0
            ? _round(effectiveDistance / fuelLiters, 2)
            : null,
        'cost_per_km': effectiveDistance > 0
            ? costs.map(
                (currency, amount) =>
                    MapEntry(currency, _round(amount / effectiveDistance, 4)),
              )
            : <String, double>{},
        'source': 'local',
      });
    }

    return rows;
  }

  Future<double> _gpsDistance(
    String tenantId,
    DateTime start,
    DateTime end,
  ) async {
    final points = await db.db.query(
      'local_gps_points',
      columns: [
        'latitude',
        'longitude',
        'accuracy',
        'is_mock_location',
        'recorded_at',
      ],
      where:
          'tenant_id=? AND recorded_at>=? AND recorded_at<=? '
          'AND accuracy<=? AND is_mock_location=0',
      whereArgs: [
        tenantId,
        start.toUtc().toIso8601String(),
        end.toUtc().toIso8601String(),
        50,
      ],
      orderBy: 'recorded_at ASC',
    );

    var distance = 0.0;

    for (var index = 1; index < points.length; index++) {
      final previous = points[index - 1];
      final current = points[index];
      final previousAt = DateTime.tryParse('${previous['recorded_at']}');
      final currentAt = DateTime.tryParse('${current['recorded_at']}');
      if (previousAt == null || currentAt == null) continue;

      final kilometres = _distance(
        _number(previous['latitude']) ?? 0,
        _number(previous['longitude']) ?? 0,
        _number(current['latitude']) ?? 0,
        _number(current['longitude']) ?? 0,
      );
      final seconds = math.max(1, currentAt.difference(previousAt).inSeconds);
      final speedKmh = kilometres / (seconds / 3600);

      if (speedKmh <= 200) {
        distance += kilometres;
      }
    }

    return _round(distance, 3);
  }

  double _distance(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371.0;
    final dLat = _radians(lat2 - lat1);
    final dLon = _radians(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_radians(lat1)) *
            math.cos(_radians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  double _radians(double degrees) => degrees * math.pi / 180;

  double? _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  double _round(double value, int places) {
    final factor = math.pow(10, places).toDouble();
    return (value * factor).round() / factor;
  }
}
