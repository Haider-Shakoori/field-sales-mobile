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
    accuracy: LocationAccuracy.bestForNavigation,
    distanceFilter: 0,
    intervalDuration: Duration(seconds: math.max(5, movingSeconds)),
    foregroundNotificationConfig: const ForegroundNotificationConfig(
      notificationTitle: 'FieldPulse',
      notificationText: 'Workday location tracking is active',
      notificationChannelName: 'FieldPulse workday tracking',
      enableWakeLock: true,
      enableWifiLock: true,
      setOngoing: true,
    ),
  );
}

class TrackingService {
  TrackingService({required this.db, required this.gpsRepository});

  final AppDatabase db;
  final GpsRepository gpsRepository;

  StreamSubscription<Position>? _sub;
  StreamSubscription<ServiceStatus>? _serviceStatusSub;
  Timer? _watchdog;
  Timer? _restartTimer;
  String? _tenantId;
  int _movingSeconds = 15;
  DateTime? _lastFixAt;
  bool _restartInFlight = false;
  bool _uploadInFlight = false;
  bool _processingPosition = false;
  Position? _queuedPosition;
  DateTime? _lastUploadAttemptAt;
  int _restartAttempt = 0;

  bool get active => _sub != null;
  DateTime? get lastFixAt => _lastFixAt;

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

    _listenForServiceStatus();
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
        _restartAttempt = 0;
        _restartTimer?.cancel();
        _restartTimer = null;
        unawaited(_queuePosition(tenantId, position));
      },
      onError: (_) => _scheduleRestart(),
      onDone: _scheduleRestart,
      cancelOnError: false,
    );
  }

  Future<void> _queuePosition(String tenantId, Position position) async {
    if (_processingPosition) {
      _queuedPosition = position;
      return;
    }

    _processingPosition = true;
    var current = position;

    try {
      while (true) {
        try {
          await _storeAndMaybeUpload(tenantId, current);
        } catch (_) {
          // A single failed persistence/upload attempt must never terminate
          // the tracking stream. The next fix is still eligible to continue.
        }

        final next = _queuedPosition;
        _queuedPosition = null;
        if (next == null) break;
        current = next;
      }
    } finally {
      _processingPosition = false;
    }
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
      await gpsRepository.uploadAll(tenantId, maxBatches: 3);
    } catch (_) {
      // Local-first storage already succeeded. A later sync cycle will retry.
    } finally {
      _uploadInFlight = false;
    }
  }

  void _listenForServiceStatus() {
    _serviceStatusSub ??= Geolocator.getServiceStatusStream().listen(
      (status) {
        if (status == ServiceStatus.enabled && _tenantId != null) {
          unawaited(_restartStream());
        }
      },
      onError: (_) {
        // The watchdog remains the fallback if this platform stream fails.
      },
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
    if (_tenantId == null || _restartTimer != null) return;

    const delays = <Duration>[
      Duration(seconds: 3),
      Duration(seconds: 10),
      Duration(seconds: 30),
      Duration(minutes: 1),
      Duration(minutes: 2),
    ];
    final index = math.min(_restartAttempt, delays.length - 1);
    _restartAttempt++;

    _restartTimer = Timer(delays[index], () {
      _restartTimer = null;
      if (_tenantId != null) {
        unawaited(_restartStream());
      }
    });
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
    _restartTimer?.cancel();
    _restartTimer = null;

    final subscription = _sub;
    final serviceStatusSubscription = _serviceStatusSub;
    _sub = null;
    _serviceStatusSub = null;
    _tenantId = null;
    _lastFixAt = null;
    _lastUploadAttemptAt = null;
    _uploadInFlight = false;
    _processingPosition = false;
    _queuedPosition = null;
    _restartAttempt = 0;
    unawaited(subscription?.cancel());
    unawaited(serviceStatusSubscription?.cancel());
  }

  Future<String?> reliabilityWarning() async {
    if (!Platform.isAndroid) return null;

    try {
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always) {
        return 'Tracking reliability: set FieldPulse location permission to '
            '"Allow all the time" so workday GPS can continue after Android '
            'puts the app in the background.';
      }

      final accuracy = await Geolocator.getLocationAccuracy();
      if (accuracy == LocationAccuracyStatus.reduced) {
        return 'Tracking reliability: Precise location is disabled. Enable '
            'precise location for FieldPulse to improve route accuracy.';
      }
    } catch (_) {
      // Diagnostics will surface platform-specific problems separately.
    }

    return null;
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
