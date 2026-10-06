import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/api/api_client.dart';
import '../../core/db/app_database.dart';

typedef TrackingActiveReader = bool Function();

class DeviceHealthResult {
  const DeviceHealthResult({
    required this.metrics,
    required this.status,
    required this.issues,
    required this.collectedAt,
  });

  final Map<String, dynamic> metrics;
  final String status;
  final List<Map<String, dynamic>> issues;
  final DateTime collectedAt;

  DeviceHealthResult withServer({
    required String status,
    required List<Map<String, dynamic>> issues,
  }) => DeviceHealthResult(
    metrics: metrics,
    status: status,
    issues: issues,
    collectedAt: collectedAt,
  );
}

class DeviceHealthCollector {
  DeviceHealthCollector({
    Battery? battery,
    Connectivity? connectivity,
    DeviceInfoPlugin? deviceInfo,
    MethodChannel? diagnosticsChannel,
  }) : _battery = battery ?? Battery(),
       _connectivity = connectivity ?? Connectivity(),
       _deviceInfo = deviceInfo ?? DeviceInfoPlugin(),
       _diagnosticsChannel =
           diagnosticsChannel ??
           const MethodChannel('field_sales/device_diagnostics');

  final Battery _battery;
  final Connectivity _connectivity;
  final DeviceInfoPlugin _deviceInfo;
  final MethodChannel _diagnosticsChannel;

  Future<Map<String, dynamic>> collectPlatform() async {
    final values = <String, dynamic>{};

    try {
      values['battery_level'] = await _battery.batteryLevel;
      final state = await _battery.batteryState;
      values['is_charging'] =
          state == BatteryState.charging || state == BatteryState.full;
    } catch (_) {
      values['battery_level'] = null;
      values['is_charging'] = null;
    }

    try {
      final connectivity = await _connectivity.checkConnectivity();
      values['network_type'] = _networkType(connectivity);
    } catch (_) {
      values['network_type'] = 'unknown';
    }

    try {
      values['location_services_enabled'] =
          await Geolocator.isLocationServiceEnabled();
      values['location_permission'] = _locationPermission(
        await Geolocator.checkPermission(),
      );
    } catch (_) {
      values['location_services_enabled'] = null;
      values['location_permission'] = 'unknown';
    }

    try {
      if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        values['is_physical_device'] = info.isPhysicalDevice;
      } else if (Platform.isIOS) {
        final info = await _deviceInfo.iosInfo;
        values['is_physical_device'] = info.isPhysicalDevice;
      } else {
        values['is_physical_device'] = null;
      }
    } catch (_) {
      values['is_physical_device'] = null;
    }

    try {
      final native = await _diagnosticsChannel.invokeMapMethod<String, dynamic>(
        'snapshot',
      );
      if (native != null) {
        values.addAll(native);
      }
    } catch (_) {
      // Native diagnostics are best-effort so older builds/platforms remain usable.
    }

    values.putIfAbsent('power_save_mode', () => null);
    values.putIfAbsent('battery_optimization_exempt', () => null);
    values.putIfAbsent('background_restricted', () => null);
    values.putIfAbsent('background_location_permission', () {
      final permission = values['location_permission'];
      return permission == 'always' ? 'granted' : 'unknown';
    });
    values.putIfAbsent('notification_permission', () => 'unknown');
    values.putIfAbsent('storage_free_mb', () => null);
    values.putIfAbsent('storage_total_mb', () => null);
    values.putIfAbsent('root_signal_detected', () => null);

    return values;
  }

  Future<bool> openLocationSettings() =>
      _invokeSettingsAction('openLocationSettings');

  Future<bool> openAppSettings() => _invokeSettingsAction('openAppSettings');

  Future<bool> openBatterySettings() =>
      _invokeSettingsAction('openBatterySettings');

  Future<bool> _invokeSettingsAction(String method) async {
    try {
      return await _diagnosticsChannel.invokeMethod<bool>(method) ?? false;
    } catch (_) {
      return false;
    }
  }

  String _networkType(List<ConnectivityResult> values) {
    if (values.contains(ConnectivityResult.wifi)) return 'wifi';
    if (values.contains(ConnectivityResult.mobile)) return 'cellular';
    if (values.contains(ConnectivityResult.ethernet)) return 'ethernet';
    if (values.contains(ConnectivityResult.vpn)) return 'vpn';
    if (values.contains(ConnectivityResult.bluetooth)) return 'bluetooth';
    if (values.isEmpty ||
        values.every((value) => value == ConnectivityResult.none)) {
      return 'offline';
    }

    return 'other';
  }

  String _locationPermission(LocationPermission permission) =>
      switch (permission) {
        LocationPermission.always => 'always',
        LocationPermission.whileInUse => 'while_in_use',
        LocationPermission.denied => 'denied',
        LocationPermission.deniedForever => 'denied_forever',
        _ => 'unknown',
      };
}

class DeviceHealthRepository {
  DeviceHealthRepository({
    required this.api,
    required this.db,
    required this.trackingActive,
    DeviceHealthCollector? collector,
  }) : collector = collector ?? DeviceHealthCollector();

  final ApiClient api;
  final AppDatabase db;
  final TrackingActiveReader trackingActive;
  final DeviceHealthCollector collector;

  Future<bool> openLocationSettings() => collector.openLocationSettings();

  Future<bool> openAppSettings() => collector.openAppSettings();

  Future<bool> openBatterySettings() => collector.openBatterySettings();

  Future<DeviceHealthResult> collect(String tenantId) async {
    final metrics = await collector.collectPlatform();
    final sync = await _syncHealth(tenantId);
    final activeWorkday = await _hasActiveWorkday(tenantId);
    final gps = await _gpsHealth(tenantId);

    metrics.addAll(sync);
    metrics.addAll(gps);
    metrics['workday_active'] = activeWorkday;
    metrics['background_tracking_active'] = trackingActive();

    final classification = classifyDeviceHealth(metrics);

    return DeviceHealthResult(
      metrics: metrics,
      status: classification.status,
      issues: classification.issues,
      collectedAt: DateTime.now().toUtc(),
    );
  }

  Future<DeviceHealthResult> report(String tenantId) async {
    final result = await collect(tenantId);
    final response = Map<String, dynamic>.from(
      await api.post('device/health', data: _serverPayload(result.metrics)),
    );

    final issues = response['health_issues'] is List
        ? List<Map<String, dynamic>>.from(
            (response['health_issues'] as List).map(
              (issue) => Map<String, dynamic>.from(issue as Map),
            ),
          )
        : result.issues;

    return result.withServer(
      status: response['health_status']?.toString() ?? result.status,
      issues: issues,
    );
  }

  Future<DeviceHealthResult> current(String tenantId) async {
    final local = await collect(tenantId);

    try {
      final response = Map<String, dynamic>.from(
        await api.get('device/health'),
      );
      final issues = response['health_issues'] is List
          ? List<Map<String, dynamic>>.from(
              (response['health_issues'] as List).map(
                (issue) => Map<String, dynamic>.from(issue as Map),
              ),
            )
          : local.issues;

      return local.withServer(
        status: response['health_status']?.toString() ?? local.status,
        issues: issues,
      );
    } catch (_) {
      return local;
    }
  }

  Map<String, dynamic> _serverPayload(Map<String, dynamic> values) {
    const allowed = <String>{
      'battery_level',
      'is_charging',
      'power_save_mode',
      'battery_optimization_exempt',
      'background_restricted',
      'location_services_enabled',
      'location_permission',
      'background_location_permission',
      'notification_permission',
      'background_tracking_active',
      'workday_active',
      'network_type',
      'storage_free_mb',
      'storage_total_mb',
      'pending_sync_count',
      'failed_sync_count',
      'blocked_sync_count',
      'last_sync_at',
      'is_physical_device',
      'root_signal_detected',
      'mock_location_detected',
      'last_gps_fix_at',
      'last_gps_upload_at',
      'pending_gps_points',
      'gps_points_last_hour',
    };

    return {
      for (final entry in values.entries)
        if (allowed.contains(entry.key)) entry.key: entry.value,
    };
  }

  Future<bool> _hasActiveWorkday(String tenantId) async {
    if (tenantId.isEmpty) return false;

    final rows = await db.db.query(
      'local_work_sessions',
      columns: const ['id'],
      where: 'tenant_id=? AND status=?',
      whereArgs: [tenantId, 'active'],
      limit: 1,
    );

    return rows.isNotEmpty;
  }

  Future<Map<String, dynamic>> _gpsHealth(String tenantId) async {
    final latest = await db.db.query(
      'local_gps_points',
      columns: const ['recorded_at'],
      where: 'tenant_id=?',
      whereArgs: [tenantId],
      orderBy: 'id DESC',
      limit: 1,
    );

    final latestUpload = await db.db.query(
      'local_gps_points',
      columns: const ['uploaded_at'],
      where: 'tenant_id=? AND uploaded_at IS NOT NULL',
      whereArgs: [tenantId],
      orderBy: 'uploaded_at DESC',
      limit: 1,
    );

    final pendingGps =
        Sqflite.firstIntValue(
          await db.db.rawQuery(
            'SELECT COUNT(*) FROM local_gps_points '
            'WHERE tenant_id=? AND sync_status=?',
            [tenantId, 'pending'],
          ),
        ) ??
        0;

    final oneHourAgo = DateTime.now()
        .toUtc()
        .subtract(const Duration(hours: 1))
        .toIso8601String();
    final pointsLastHour =
        Sqflite.firstIntValue(
          await db.db.rawQuery(
            'SELECT COUNT(*) FROM local_gps_points '
            'WHERE tenant_id=? AND recorded_at>=?',
            [tenantId, oneHourAgo],
          ),
        ) ??
        0;

    final since = DateTime.now()
        .toUtc()
        .subtract(const Duration(hours: 24))
        .toIso8601String();
    final mock =
        Sqflite.firstIntValue(
          await db.db.rawQuery(
            'SELECT COUNT(*) FROM local_gps_points '
            'WHERE tenant_id=? AND is_mock_location=1 AND recorded_at>=?',
            [tenantId, since],
          ),
        ) ??
        0;

    return {
      'last_gps_fix_at': latest.isEmpty ? null : latest.first['recorded_at'],
      'last_gps_upload_at': latestUpload.isEmpty
          ? null
          : latestUpload.first['uploaded_at'],
      'pending_gps_points': pendingGps,
      'gps_points_last_hour': pointsLastHour,
      'mock_location_detected': mock > 0,
    };
  }

  Future<Map<String, dynamic>> _syncHealth(String tenantId) async {
    var pending = 0;

    final queue =
        Sqflite.firstIntValue(
          await db.db.rawQuery(
            'SELECT COUNT(*) FROM sync_queue '
            'WHERE tenant_id=? AND status IN (?,?,?,?)',
            [tenantId, 'pending', 'failed', 'blocked', 'retry_wait'],
          ),
        ) ??
        0;
    pending += queue;

    for (final table in const <String>[
      'local_gps_points',
      'privacy_acknowledgements',
      'local_visits',
      'local_visit_photos',
      'local_visit_voice_notes',
      'local_visit_form_submissions',
      'local_call_activities',
      'local_orders',
      'local_collections',
      'local_expenses',
      'local_sales_returns',
      'local_appointments',
      'local_leads',
      'local_lead_activities',
      'local_customer_follow_ups',
    ]) {
      try {
        final rows = await db.db.rawQuery(
          'SELECT COUNT(*) AS total FROM $table '
          'WHERE tenant_id=? AND sync_status NOT IN (?,?)',
          [tenantId, 'synced', 'uploaded'],
        );
        pending += rows.first['total'] as int? ?? 0;
      } catch (_) {
        // Older local schemas may not have a sync_status column on every table.
      }
    }

    final failed =
        Sqflite.firstIntValue(
          await db.db.rawQuery(
            'SELECT COUNT(*) FROM local_sync_failures '
            'WHERE tenant_id=? AND status=?',
            [tenantId, 'retry_wait'],
          ),
        ) ??
        0;
    final blocked =
        Sqflite.firstIntValue(
          await db.db.rawQuery(
            'SELECT COUNT(*) FROM local_sync_failures '
            'WHERE tenant_id=? AND status=?',
            [tenantId, 'blocked'],
          ),
        ) ??
        0;

    final latestCycle = await db.db.query(
      'local_sync_cycles',
      columns: const ['completed_at'],
      where: 'tenant_id=? AND completed_at IS NOT NULL',
      whereArgs: [tenantId],
      orderBy: 'completed_at DESC',
      limit: 1,
    );

    return {
      'pending_sync_count': pending,
      'failed_sync_count': failed,
      'blocked_sync_count': blocked,
      'last_sync_at': latestCycle.isEmpty
          ? null
          : latestCycle.first['completed_at'],
    };
  }
}

DeviceHealthClassification classifyDeviceHealth(Map<String, dynamic> metrics) {
  final issues = <Map<String, dynamic>>[];
  final workdayActive = metrics['workday_active'] == true;
  final charging = metrics['is_charging'] == true;
  final battery = _asInt(metrics['battery_level']);
  final storageFree = _asInt(metrics['storage_free_mb']);
  final pending = _asInt(metrics['pending_sync_count']) ?? 0;
  final failed = _asInt(metrics['failed_sync_count']) ?? 0;
  final blocked = _asInt(metrics['blocked_sync_count']) ?? 0;

  void add(String code, String severity, String message) {
    issues.add({'code': code, 'severity': severity, 'message': message});
  }

  if (battery != null && !charging) {
    if (battery <= 5) {
      add('battery_critical', 'critical', 'Battery is critically low.');
    } else if (battery <= 15) {
      add('battery_low', 'warning', 'Battery is low.');
    }
  }

  if (metrics['power_save_mode'] == true) {
    add(
      'power_save_mode',
      'warning',
      'Battery saver may delay background work.',
    );
  }

  if (workdayActive && metrics['battery_optimization_exempt'] == false) {
    add(
      'battery_optimization',
      'warning',
      'Battery optimization can restrict background tracking.',
    );
  }

  if (metrics['background_restricted'] == true) {
    add(
      'background_restricted',
      'warning',
      'Android is restricting background activity.',
    );
  }

  if (workdayActive && metrics['location_services_enabled'] == false) {
    add(
      'location_services_disabled',
      'critical',
      'Location services are disabled during the active work day.',
    );
  }

  final locationPermission =
      metrics['location_permission']?.toString().toLowerCase() ?? 'unknown';
  if (workdayActive &&
      const {
        'denied',
        'denied_forever',
        'restricted',
        'unknown',
      }.contains(locationPermission)) {
    add(
      'location_permission',
      'critical',
      'Location permission is not usable during the active work day.',
    );
  }

  final backgroundPermission =
      metrics['background_location_permission']?.toString().toLowerCase() ??
      'unknown';
  if (workdayActive &&
      !const {'granted', 'always'}.contains(backgroundPermission)) {
    add(
      'background_location_permission',
      'critical',
      'Background location permission is not fully enabled.',
    );
  }

  if (workdayActive && metrics['background_tracking_active'] == false) {
    add(
      'background_tracking_inactive',
      'critical',
      'Background tracking is inactive during the work day.',
    );
  }

  final lastGps = DateTime.tryParse(
    metrics['last_gps_fix_at']?.toString() ?? '',
  );
  if (workdayActive) {
    if (lastGps == null) {
      add('gps_fix_missing', 'critical', 'No usable GPS fix is available.');
    } else {
      final age = DateTime.now().toUtc().difference(lastGps.toUtc()).abs();
      if (age > const Duration(minutes: 10)) {
        add(
          'gps_fix_stale',
          'critical',
          'The latest GPS fix is over 10 minutes old.',
        );
      } else if (age > const Duration(minutes: 5)) {
        add('gps_fix_delayed', 'warning', 'The latest GPS fix is delayed.');
      }
    }
  }

  if (metrics['notification_permission'] == 'denied') {
    add(
      'notifications_denied',
      'warning',
      'Notification permission is disabled.',
    );
  }

  if (storageFree != null) {
    if (storageFree < 50) {
      add('storage_critical', 'critical', 'Device storage is critically low.');
    } else if (storageFree < 250) {
      add('storage_low', 'warning', 'Device storage is running low.');
    }
  }

  if (blocked > 0) {
    add(
      'sync_blocked',
      'critical',
      '$blocked sync item(s) require intervention.',
    );
  }
  if (failed > 0) {
    add(
      'sync_failures',
      'warning',
      '$failed sync item(s) are waiting after a failure.',
    );
  }
  if (pending >= 100) {
    add(
      'sync_backlog',
      'warning',
      '$pending items are waiting to synchronize.',
    );
  }

  if (metrics['mock_location_detected'] == true) {
    add(
      'mock_location_signal',
      'warning',
      'A mock-location signal was reported by the device.',
    );
  }
  if (metrics['root_signal_detected'] == true) {
    add(
      'root_signal',
      'warning',
      'A root/integrity warning signal was detected.',
    );
  }
  if (metrics['is_physical_device'] == false) {
    add(
      'non_physical_device',
      'info',
      'The app appears to be running on an emulator or simulator.',
    );
  }
  if (metrics['network_type'] == 'offline') {
    add(
      'network_offline',
      'warning',
      'No active network connection is available.',
    );
  }

  final status = issues.any((issue) => issue['severity'] == 'critical')
      ? 'critical'
      : issues.any((issue) => issue['severity'] == 'warning')
      ? 'warning'
      : 'healthy';

  return DeviceHealthClassification(status: status, issues: issues);
}

class DeviceHealthClassification {
  const DeviceHealthClassification({
    required this.status,
    required this.issues,
  });

  final String status;
  final List<Map<String, dynamic>> issues;
}

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}
