import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:timezone/timezone.dart' as tz;

import '../core/api/api_exception.dart';
import '../core/config.dart';
import '../core/db/app_database.dart';
import '../features/attendance/attendance_repository.dart';
import '../features/diagnostics/diagnostic_reporter.dart';
import '../features/gps/gps_repository.dart';
import '../features/gps/tracking_service.dart';
import '../features/settings/attendance_tracking_settings.dart';
import '../features/settings/settings_repository.dart';
import 'app_state.dart';

@visibleForTesting
double? parseAttendanceNumber(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString().trim() ?? '');
}

@visibleForTesting
String friendlyAttendanceError(Object error) {
  if (error is ApiException) {
    return error.message.trim().isEmpty
        ? 'The server could not complete the attendance action. Please try again.'
        : error.message.trim();
  }

  var message = error.toString().trim();
  for (final prefix in ['Bad state: ', 'StateError: ', 'Exception: ']) {
    if (message.startsWith(prefix)) {
      message = message.substring(prefix.length).trim();
    }
  }

  final lower = message.toLowerCase();
  if (lower.contains('is not a subtype of') ||
      lower.contains('type cast') ||
      lower.contains('format exception') ||
      lower.contains('null check operator')) {
    return 'The saved attendance data could not be read safely. Refresh the page and try End Day again.';
  }

  return message.isEmpty
      ? 'End Day could not be completed. Please try again.'
      : message;
}

class DayClosingSummary {
  const DayClosingSummary({
    required this.visits,
    required this.activeVisits,
    required this.orders,
    required this.orderTotal,
    required this.collections,
    required this.collectionTotal,
    required this.expenses,
    required this.expenseTotal,
    required this.pendingSync,
  });

  final int visits;
  final int activeVisits;
  final int orders;
  final double orderTotal;
  final int collections;
  final double collectionTotal;
  final int expenses;
  final double expenseTotal;
  final int pendingSync;
}

class AttendanceController extends ChangeNotifier {
  AttendanceController({
    required this.appState,
    required this.attendance,
    required this.gps,
    required this.tracking,
    required this.settings,
    required this.db,
    required this.diagnostics,
  }) {
    attendance.api.onAuthRevoked = handleRevocation;
  }

  final AppState appState;
  final AttendanceRepository attendance;
  final GpsRepository gps;
  final TrackingService tracking;
  final SettingsRepository settings;
  final AppDatabase db;
  final DiagnosticReporter diagnostics;

  Map<String, dynamic>? session;
  bool restored = false;
  bool busy = false;
  String? message;
  Timer? _uploader;
  Timer? _boundary;
  bool _revoking = false;

  bool get working => session?['status'] == 'active';

  Future<void> restore() async {
    if (appState.session?.isSalesman != true) {
      session = null;
      restored = true;
      tracking.stop();
      _stopUploader();
      _boundary?.cancel();
      _boundary = null;
      notifyListeners();
      return;
    }

    final tenantId = appState.session?.tenantId;
    session = tenantId == null ? null : await attendance.active(tenantId);
    restored = true;
    if (appState.signedIn) {
      await appState.refreshPolicy();
      await _flushPending();
      await reconcile();
      await evaluateAutomaticPolicy();
    }
    notifyListeners();
  }

  Future<void> reconcile() async {
    final policy = appState.policy;
    final tenantId = appState.session?.tenantId;
    final sessionTenant = session?['tenant_id']?.toString();

    if (session != null &&
        tenantId != null &&
        sessionTenant == tenantId &&
        policy?.gpsTrackingEnabled == true) {
      await tracking.start(
        tenantId: tenantId,
        movingSeconds: policy!.movingSeconds,
      );
      _startUploader();
    } else {
      tracking.stop();
      _stopUploader();
    }
    _scheduleBoundary();
  }

  tz.TZDateTime? _tenantNow() {
    final policy = appState.policy;
    if (policy == null || policy.timezone.isEmpty) return null;
    try {
      return tz.TZDateTime.now(tz.getLocation(policy.timezone));
    } catch (_) {
      return null;
    }
  }

  String? get tenantDate => _tenantNow()?.toIso8601String().substring(0, 10);

  bool _insideWindow(tz.TZDateTime now, AttendanceTrackingSettings policy) {
    int minutes(String value) {
      final parts = value.split(':');
      return int.parse(parts[0]) * 60 + int.parse(parts[1]);
    }

    final current = now.hour * 60 + now.minute;
    final start = minutes(policy.workdayStartTime);
    final end = minutes(policy.workdayEndTime);
    if (start == end) return false;
    if (start < end) return current >= start && current < end;
    return current >= start || current < end;
  }

  Future<bool> hasPrivacyAck() async {
    final policy = appState.policy;
    final signedIn = appState.session;
    if (policy == null || signedIn == null) return false;
    final rows = await db.db.query(
      'privacy_acknowledgements',
      where: 'policy_version=? AND user_id=? AND tenant_id=?',
      whereArgs: [
        policy.privacyPolicyVersion,
        signedIn.userId,
        signedIn.tenantId,
      ],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> acknowledgePrivacy() async {
    final policy = appState.policy;
    final signedIn = appState.session;
    if (policy == null || signedIn == null) return;
    final at = DateTime.now().toUtc().toIso8601String();
    await db.db.insert('privacy_acknowledgements', {
      'policy_version': policy.privacyPolicyVersion,
      'acknowledged_at': at,
      'user_id': signedIn.userId,
      'tenant_id': signedIn.tenantId,
      'device_id': signedIn.deviceId,
      'app_version': AppConfig.appVersion,
      'sync_status': 'pending',
    });
    try {
      final data = Map<String, dynamic>.from(
        await settings.api.post(
          'gps/privacy-acknowledgement',
          data: {
            'policy_version': policy.privacyPolicyVersion,
            'acknowledged_at': at,
            'app_version': AppConfig.appVersion,
          },
        ),
      );
      await db.db.update(
        'privacy_acknowledgements',
        {
          'sync_status': 'synced',
          'server_id': data['id'],
          'server_uuid': data['uuid'],
        },
        where: 'policy_version=? AND user_id=? AND tenant_id=?',
        whereArgs: [
          policy.privacyPolicyVersion,
          signedIn.userId,
          signedIn.tenantId,
        ],
      );
    } catch (_) {}
    notifyListeners();
  }

  Future<void> startDay({
    String source = 'manual',
    String? vehicleReference,
    double? odometerStartKm,
  }) async {
    if (appState.session?.isSalesman != true || busy || working) return;
    busy = true;
    message = null;
    notifyListeners();
    try {
      final tenantId = appState.session?.tenantId;
      final date = tenantDate;
      if (tenantId == null) {
        throw StateError('Signed-in tenant is unavailable.');
      }
      if (date == null) throw StateError('Company timezone is unavailable.');
      if (await attendance.forDate(tenantId, date) != null) {
        throw StateError('Day completed or already started.');
      }
      if (!await hasPrivacyAck()) {
        throw StateError('Review tracking policy before starting.');
      }
      if (source == 'manual') await _requestNotificationPermission();
      final fix = await tracking.oneShot();
      if (fix == null) throw StateError('A usable GPS location is required.');
      await gps.store(
        tenantId: tenantId,
        latitude: fix.latitude,
        longitude: fix.longitude,
        accuracy: fix.accuracy,
        altitude: fix.altitude,
        speed: fix.speed,
        heading: fix.heading,
        isMock: fix.isMocked,
        recordedAt: fix.timestamp,
      );
      await attendance.start(
        tenantId: tenantId,
        date: date,
        at: DateTime.now(),
        lat: fix.latitude,
        lng: fix.longitude,
        accuracy: fix.accuracy,
        source: source,
        privacyAckAt: DateTime.now().toUtc().toIso8601String(),
        vehicleReference: vehicleReference,
        odometerStartKm: odometerStartKm,
      );
      session = await attendance.active(tenantId);
      await reconcile();
      unawaited(_flushPending());
    } catch (error) {
      message = '$error'.replaceFirst('Bad state: ', '');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> endDay({
    bool sync = true,
    String? vehicleReference,
    double? odometerEndKm,
  }) async {
    if (busy || !working) return;

    busy = true;
    message = null;
    notifyListeners();

    try {
      final tenantId = appState.session?.tenantId;
      if (tenantId == null) {
        throw StateError('Signed-in tenant is unavailable.');
      }

      final currentSession = session;
      if (currentSession == null) {
        throw StateError('No active work day was found.');
      }

      final startOdometer = parseAttendanceNumber(
        currentSession['odometer_start_km'],
      );
      if (odometerEndKm != null &&
          startOdometer != null &&
          odometerEndKm < startOdometer) {
        throw StateError(
          'End odometer must be greater than or equal to the start odometer.',
        );
      }

      // Flush older pending work first when requested. Failures remain queued
      // and must never prevent the local work day from being completed.
      if (sync) {
        await _flushPending();
      }

      final fix = await tracking.oneShot(timeout: const Duration(seconds: 10));

      double? latitude;
      double? longitude;
      double? accuracy;

      if (fix != null) {
        latitude = fix.latitude;
        longitude = fix.longitude;
        accuracy = fix.accuracy;
      } else {
        final points = await db.db.query(
          'local_gps_points',
          where: 'tenant_id=?',
          whereArgs: [tenantId],
          orderBy: 'recorded_at DESC',
          limit: 1,
        );

        if (points.isNotEmpty) {
          final row = points.first;
          final recordedAt = DateTime.tryParse(
            row['recorded_at']?.toString() ?? '',
          );
          final cachedLatitude = parseAttendanceNumber(row['latitude']);
          final cachedLongitude = parseAttendanceNumber(row['longitude']);
          final cachedAccuracy = parseAttendanceNumber(row['accuracy']);

          final fresh =
              recordedAt != null &&
              DateTime.now().difference(recordedAt.toLocal()).abs() <=
                  const Duration(minutes: 10);

          if (fresh &&
              cachedLatitude != null &&
              cachedLongitude != null &&
              cachedAccuracy != null) {
            latitude = cachedLatitude;
            longitude = cachedLongitude;
            accuracy = cachedAccuracy;
          }
        }

        latitude ??= parseAttendanceNumber(currentSession['start_latitude']);
        longitude ??= parseAttendanceNumber(currentSession['start_longitude']);
        accuracy ??= parseAttendanceNumber(currentSession['start_accuracy']);
      }

      if (latitude == null ||
          longitude == null ||
          accuracy == null ||
          latitude == 0 ||
          longitude == 0) {
        throw StateError(
          'A usable location is required to end the day. Turn on location services and try again.',
        );
      }

      await attendance.end(
        session: currentSession,
        at: DateTime.now(),
        lat: latitude,
        lng: longitude,
        accuracy: accuracy.clamp(0, 200).toDouble(),
        vehicleReference:
            vehicleReference ?? currentSession['vehicle_reference']?.toString(),
        odometerEndKm: odometerEndKm,
      );

      // Only stop tracking after the local End Day transaction succeeds.
      // If anything above fails, the active work day remains intact.
      tracking.stop();
      _stopUploader();
      session = null;
      message = null;

      if (sync) {
        unawaited(_flushPending());
      }

      _scheduleBoundary();
    } catch (error) {
      message = friendlyAttendanceError(error);
      unawaited(
        diagnostics.report(
          area: 'attendance.end_day',
          code: error is ApiException ? error.code : error.runtimeType.toString(),
          message: message!,
          screen: 'home',
          operation: 'end_day',
        ),
      );
      await reconcile();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<DayClosingSummary> dayClosingSummary() async {
    final tenantId = appState.session?.tenantId;
    final now = _tenantNow();

    if (tenantId == null || now == null) {
      return const DayClosingSummary(
        visits: 0,
        activeVisits: 0,
        orders: 0,
        orderTotal: 0,
        collections: 0,
        collectionTotal: 0,
        expenses: 0,
        expenseTotal: 0,
        pendingSync: 0,
      );
    }

    final start = tz.TZDateTime(
      now.location,
      now.year,
      now.month,
      now.day,
    ).toUtc();
    final end = start.add(const Duration(days: 1));
    final from = start.toIso8601String();
    final to = end.toIso8601String();

    Future<Map<String, Object?>> aggregate(
      String table,
      String dateColumn, {
      String? amountColumn,
      String? extraWhere,
      List<Object?> extraArgs = const [],
    }) async {
      final amountSql = amountColumn == null
          ? ''
          : ', COALESCE(SUM($amountColumn), 0) AS amount';
      final rows = await db.db.rawQuery(
        'SELECT COUNT(*) AS total$amountSql FROM $table '
        'WHERE tenant_id=? AND $dateColumn>=? AND $dateColumn<?'
        ${extraWhere == null ? "''" : "' AND '+extraWhere"},
        [tenantId, from, to, ...extraArgs],
      );

      return rows.first;
    }

    final visitsRow = await aggregate(
      'local_visits',
      'checked_in_at',
    );
    final activeVisitRows = await db.db.rawQuery(
      'SELECT COUNT(*) AS total FROM local_visits '
      'WHERE tenant_id=? AND status=?',
      [tenantId, 'active'],
    );
    final ordersRow = await aggregate(
      'local_orders',
      'ordered_at',
      amountColumn: 'grand_total',
    );
    final collectionsRow = await aggregate(
      'local_collections',
      'collected_at',
      amountColumn: 'amount',
    );
    final expensesRow = await aggregate(
      'local_expenses',
      'spent_at',
      amountColumn: 'amount',
    );
    final pendingRows = await db.db.rawQuery(
      'SELECT COUNT(*) AS total FROM sync_queue '
      'WHERE tenant_id=? AND status IN (?,?,?)',
      [tenantId, 'pending', 'failed', 'blocked'],
    );

    int count(Map<String, Object?> row) =>
        parseAttendanceNumber(row['total'])?.toInt() ?? 0;
    double amount(Map<String, Object?> row) =>
        parseAttendanceNumber(row['amount']) ?? 0;

    return DayClosingSummary(
      visits: count(visitsRow),
      activeVisits: count(activeVisitRows.first),
      orders: count(ordersRow),
      orderTotal: amount(ordersRow),
      collections: count(collectionsRow),
      collectionTotal: amount(collectionsRow),
      expenses: count(expensesRow),
      expenseTotal: amount(expensesRow),
      pendingSync: count(pendingRows.first),
    );
  }

  Future<void> evaluateAutomaticPolicy() async {
    final policy = appState.policy;
    final tenantId = appState.session?.tenantId;
    final now = _tenantNow();
    if (!appState.signedIn ||
        tenantId == null ||
        policy == null ||
        !policy.trusted ||
        now == null) {
      _scheduleBoundary();
      return;
    }
    final inside = _insideWindow(now, policy);
    if (working) {
      if (!policy.gpsTrackingEnabled) {
        tracking.stop();
        _stopUploader();
      } else if (!tracking.active) {
        await tracking.start(
          tenantId: tenantId,
          movingSeconds: policy.movingSeconds,
        );
        _startUploader();
      }
      if (policy.autoEndSession &&
          !inside &&
          _sessionStartedInsideWindow(policy)) {
        await endDay();
      }
      _scheduleBoundary();
      return;
    }
    if (policy.startMode == 'automatic' &&
        inside &&
        policy.gpsTrackingEnabled) {
      final date = tenantDate;
      if (date != null && await attendance.forDate(tenantId, date) == null) {
        if (!await hasPrivacyAck()) {
          message = 'Review tracking policy before automatic Start Day.';
        } else {
          await startDay(source: 'automatic');
        }
      }
    }
    _scheduleBoundary();
    notifyListeners();
  }

  bool _sessionStartedInsideWindow(AttendanceTrackingSettings policy) {
    final raw = session?['start_time'] as String?;
    if (raw == null || policy.timezone.isEmpty) return false;
    try {
      final location = tz.getLocation(policy.timezone);
      final instant = DateTime.parse(raw).toUtc();
      return _insideWindow(tz.TZDateTime.from(instant, location), policy);
    } catch (_) {
      return false;
    }
  }

  void _scheduleBoundary() {
    _boundary?.cancel();
    _boundary = null;
    final policy = appState.policy;
    final now = _tenantNow();
    if (!appState.signedIn ||
        policy == null ||
        !policy.trusted ||
        now == null) {
      return;
    }
    tz.TZDateTime at(String hm, int dayOffset) {
      final parts = hm.split(':');
      final base = now.add(Duration(days: dayOffset));
      return tz.TZDateTime(
        base.location,
        base.year,
        base.month,
        base.day,
        int.parse(parts[0]),
        int.parse(parts[1]),
      );
    }

    final candidates = <tz.TZDateTime>[
      at(policy.workdayStartTime, 0),
      at(policy.workdayEndTime, 0),
      at(policy.workdayStartTime, 1),
      at(policy.workdayEndTime, 1),
    ].where((v) => v.isAfter(now)).toList()..sort();
    if (candidates.isEmpty) return;
    _boundary = Timer(
      candidates.first.difference(now),
      () => unawaited(evaluateAutomaticPolicy()),
    );
  }

  Future<void> refreshPolicyAndEvaluate() async {
    await appState.refreshPolicy();
    final tenantId = appState.session?.tenantId;
    if (tenantId != null && session == null) {
      session = await attendance.active(tenantId);
    }
    await _flushPending();
    await reconcile();
    await evaluateAutomaticPolicy();
  }

  Future<void> _requestNotificationPermission() async {
    try {
      await const MethodChannel('field_sales/notifications')
          .invokeMethod<bool>('requestNotificationPermission')
          .timeout(const Duration(seconds: 15));
    } catch (_) {}
  }

  void _startUploader() {
    _uploader ??= Timer.periodic(
      const Duration(minutes: 5),
      (_) => unawaited(_flushPending()),
    );
  }

  void _stopUploader() {
    _uploader?.cancel();
    _uploader = null;
  }

  Future<void> _flushPending() async {
    if (appState.session?.isSalesman != true) return;

    final tenantId = appState.session?.tenantId;
    if (tenantId == null) return;

    try {
      await gps.uploadPrivacyAcknowledgements(tenantId);
      await attendance.drain(tenantId);
      if (appState.session?.tenantId == tenantId) {
        await gps.upload(tenantId);
      }
    } catch (_) {
      // Offline and transient API failures leave local rows pending for retry.
    }
  }

  Future<void> handleRevocation() async {
    if (_revoking) return;
    _revoking = true;
    tracking.stop();
    _stopUploader();
    _boundary?.cancel();
    _boundary = null;
    message = 'This device is no longer authorized. Local unsynced data has been preserved.';
    await appState.revokeLocal();
    _revoking = false;
    notifyListeners();
  }

  Future<void> logout() async {
    if (working && !busy) {
      try {
        await endDay();
      } catch (_) {}
      if (appState.signedIn) {
        try {
          await _flushPending();
        } catch (_) {}
      }
    }
    tracking.stop();
    _stopUploader();
    _boundary?.cancel();
    _boundary = null;
    await appState.logout();
    session = null;
    notifyListeners();
  }

  @override
  void dispose() {
    tracking.stop();
    _stopUploader();
    _boundary?.cancel();
    super.dispose();
  }
}
