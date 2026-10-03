import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

import '../../core/db/app_database.dart';
import 'gps_repository.dart';

int trackingStaleThresholdSeconds(int movingSeconds) =>
    math.max(90, movingSeconds * 6);

LocationSettings trackingLocationSettings({
  required bool isIOS,
  required int movingSeconds,
}) {
  if (isIOS) {
    return AppleSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 5,
      activityType: ActivityType.otherNavigation,
      pauseLocationUpdatesAutomatically: false,
      showBackgroundLocationIndicator: true,
      allowBackgroundLocationUpdates: true,
    );
  }

  return AndroidSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 5,
    intervalDuration: Duration(seconds: math.max(5, movingSeconds)),
    foregroundNotificationConfig: const ForegroundNotificationConfig(
      notificationTitle: 'FieldPulse',
      notificationText: 'Workday location tracking is active',
      enableWakeLock: true,
      setOngoing: true,
    ),
  );
}

class TrackingService {
  TrackingService({required this.db, required this.gpsRepository});

  final AppDatabase db;
  final GpsRepository gpsRepository;

  StreamSubscription<Position>? _sub;
  Timer? _watchdog;
  String? _tenantId;
  int _movingSeconds = 15;
  DateTime? _lastFixAt;
  bool _restartInFlight = false;
  bool _uploadInFlight = false;
  DateTime? _lastUploadAttemptAt;

  bool get active => _sub != null;

  Future<void> start({
    required String tenantId,
    required int movingSeconds,
  }) async {
    _tenantId = tenantId;
    _movingSeconds = math.max(5, movingSeconds);

    if (!await _hasActiveSession(tenantId)) {
      stop();
      return;
    }

    if (_sub == null) {
      await _openStream();
    }

    _startWatchdog();
  }

  Future<bool> _hasActiveSession(String tenantId) async {
    final session = await db.db.query(
      'local_work_sessions',
      where: 'tenant_id=? AND status=?',
      whereArgs: [tenantId, 'active'],
      limit: 1,
    );

    return session.isNotEmpty;
  }

  Future<void> _openStream() async {
    final tenantId = _tenantId;
    if (tenantId == null || !await _hasActiveSession(tenantId)) return;
    if (!await Geolocator.isLocationServiceEnabled()) return;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    final previous = _sub;
    _sub = null;
    await previous?.cancel();

    final settings = trackingLocationSettings(
      isIOS: Platform.isIOS,
      movingSeconds: _movingSeconds,
    );

    _sub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (position) {
        _lastFixAt = DateTime.now().toUtc();
        unawaited(_storeAndMaybeUpload(tenantId, position));
      },
      onError: (_) => _scheduleRestart(),
      onDone: _scheduleRestart,
      cancelOnError: false,
    );
  }

  Future<void> _storeAndMaybeUpload(String tenantId, Position position) async {
    await gpsRepository.store(
      tenantId: tenantId,
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      altitude: position.altitude,
      speed: position.speed,
      heading: position.heading,
      isMock: position.isMocked,
      recordedAt: position.timestamp,
    );

    final now = DateTime.now().toUtc();
    if (_uploadInFlight ||
        (_lastUploadAttemptAt != null &&
            now.difference(_lastUploadAttemptAt!).abs() <
                const Duration(minutes: 1))) {
      return;
    }

    _uploadInFlight = true;
    _lastUploadAttemptAt = now;

    try {
      await gpsRepository.upload(tenantId);
    } catch (_) {
      // Local-first storage already succeeded. A later sync cycle will retry.
    } finally {
      _uploadInFlight = false;
    }
  }

  void _startWatchdog() {
    _watchdog ??= Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_ensureHealthy()),
    );
  }

  Future<void> _ensureHealthy() async {
    final tenantId = _tenantId;
    if (tenantId == null) return;

    if (!await _hasActiveSession(tenantId)) {
      stop();
      return;
    }

    if (!await Geolocator.isLocationServiceEnabled()) return;

    final staleAfter = Duration(
      seconds: trackingStaleThresholdSeconds(_movingSeconds),
    );
    final stale =
        _lastFixAt == null ||
        DateTime.now().toUtc().difference(_lastFixAt!).abs() > staleAfter;

    if (_sub == null || stale) {
      await _restartStream();
    }
  }

  void _scheduleRestart() {
    unawaited(
      Future<void>.delayed(const Duration(seconds: 3)).then((_) async {
        if (_tenantId != null) {
          await _restartStream();
        }
      }),
    );
  }

  Future<void> _restartStream() async {
    if (_restartInFlight || _tenantId == null) return;
    _restartInFlight = true;

    try {
      final current = _sub;
      _sub = null;
      await current?.cancel();
      await _openStream();
    } catch (_) {
      // The watchdog keeps retrying while the local workday remains active.
    } finally {
      _restartInFlight = false;
    }
  }

  void stop() {
    _watchdog?.cancel();
    _watchdog = null;

    final subscription = _sub;
    _sub = null;
    _tenantId = null;
    _lastFixAt = null;
    _lastUploadAttemptAt = null;
    _uploadInFlight = false;
    unawaited(subscription?.cancel());
  }

  Future<Position?> oneShot({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(timeout);

      return position.accuracy <= 200 ? position : null;
    } catch (_) {
      return null;
    }
  }
}
