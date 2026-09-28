import 'dart:async';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

import '../../core/db/app_database.dart';
import 'gps_repository.dart';

int trackingStaleThresholdSeconds(int movingSeconds) =>
    math.max(90, movingSeconds * 6);

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

    final settings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
      intervalDuration: Duration(seconds: _movingSeconds),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'FieldPulse',
        notificationText: 'Workday location tracking is active',
        enableWakeLock: true,
        setOngoing: true,
      ),
    );

    _sub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (position) {
        _lastFixAt = DateTime.now().toUtc();
        unawaited(
          gpsRepository.store(
            tenantId: tenantId,
            latitude: position.latitude,
            longitude: position.longitude,
            accuracy: position.accuracy,
            altitude: position.altitude,
            speed: position.speed,
            heading: position.heading,
            isMock: position.isMocked,
            recordedAt: position.timestamp,
          ),
        );
      },
      onError: (_) => _scheduleRestart(),
      onDone: _scheduleRestart,
      cancelOnError: false,
    );
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
