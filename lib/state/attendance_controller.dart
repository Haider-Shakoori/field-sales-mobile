import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:timezone/timezone.dart' as tz;

import '../core/config.dart';
import '../core/db/app_database.dart';
import '../features/attendance/attendance_repository.dart';
import '../features/gps/gps_repository.dart';
import '../features/gps/tracking_service.dart';
import '../features/settings/attendance_tracking_settings.dart';
import '../features/settings/settings_repository.dart';
import 'app_state.dart';

class AttendanceController extends ChangeNotifier {
  AttendanceController({
    required this.appState,
    required this.attendance,
    required this.gps,
    required this.tracking,
    required this.settings,
    required this.db,
  }) {
    attendance.api.onAuthRevoked = handleRevocation;
  }

  final AppState appState;
  final AttendanceRepository attendance;
  final GpsRepository gps;
  final TrackingService tracking;
  final SettingsRepository settings;
  final AppDatabase db;

  Map<String, dynamic>? session;
  bool restored = false;
  bool busy = false;
  String? message;
  Timer? _uploader;
  Timer? _boundary;
  bool _revoking = false;

  bool get working => session?['status'] == 'active';

  Future<void> restore() async {
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

  Future<void> startDay({String source = 'manual'}) async {
    if (busy || working) return;
    busy = true;
    message = null;
    notifyListeners();
    try {
      final tenantId = appState.session?.tenantId;
      final date = tenantDate;
      if (tenantId == null) throw StateError('Signed-in tenant is unavailable.');
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

  Future<void> endDay() async {
    if (busy || !working) return;
    busy = true;
    notifyListeners();
    try {
      final tenantId = appState.session?.tenantId;
      if (tenantId == null) throw StateError('Signed-in tenant is unavailable.');
      final fix = await tracking.oneShot(timeout: const Duration(seconds: 10));
      late final double latitude;
      late final double longitude;
      late final double accuracy;
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
        if (points.isNotEmpty &&
            DateTime.now().difference(
                  DateTime.parse(points.first['recorded_at'] as String),
                ) <=
                const Duration(minutes: 10)) {
          latitude = points.first['latitude'] as double;
          longitude = points.first['longitude'] as double;
          accuracy = points.first['accuracy'] as double;
        } else {
          latitude = session!['start_latitude'] as double;
          longitude = session!['start_longitude'] as double;
          accuracy = session!['start_accuracy'] as double;
        }
      }
      tracking.stop();
      _stopUploader();
      await attendance.end(
        session: session!,
        at: DateTime.now(),
        lat: latitude,
        lng: longitude,
        accuracy: accuracy,
      );
      session = null;
      unawaited(_flushPending());
      _scheduleBoundary();
    } catch (error) {
      message = '$error';
    } finally {
      busy = false;
      notifyListeners();
    }
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
      if (date != null &&
          await attendance.forDate(tenantId, date) == null) {
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
          .invokeMethod<bool>('requestNotificationPermission');
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
    final tenantId = appState.session?.tenantId;
    if (tenantId == null) return;

    try {
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
