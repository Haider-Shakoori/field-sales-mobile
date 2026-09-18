import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/location/location_fix.dart';
import '../../core/location/location_source.dart';
import '../../core/models/gps_point.dart';
import '../../core/storage/gps_point_repository.dart';
import '../../core/storage/work_session_repository.dart';
import '../../core/time/clock.dart';
import 'device_telemetry.dart';
import 'gps_quality_filter.dart';
import 'gps_tracking_config.dart';

/// High-level state of the GPS collector.
enum TrackingState { idle, tracking, error }

/// Active-session GPS collector.
///
/// Lifecycle rule: there is NO continuous GPS tracking without a locally
/// ACTIVE work session — [start] refuses to run otherwise, and every stop path
/// (End Day, logout, device revocation, permission loss) cancels the stream,
/// which also stops the Android foreground service and its notification.
///
/// Widgets only observe this service; they never touch geolocator directly.
class GpsTrackingService extends ChangeNotifier {
  GpsTrackingService({
    required LocationSource locationSource,
    required WorkSessionRepository workSessions,
    required GpsPointRepository gpsPoints,
    required DeviceTelemetryProvider telemetry,
    this.config = const GpsTrackingConfig(),
    GpsQualityFilter? qualityFilter,
    Clock clock = const Clock(),
  }) : _locationSource = locationSource,
       _workSessions = workSessions,
       _gpsPoints = gpsPoints,
       _telemetry = telemetry,
       _clock = clock {
    _filter = qualityFilter ?? GpsQualityFilter(config);
  }

  final LocationSource _locationSource;
  final WorkSessionRepository _workSessions;
  final GpsPointRepository _gpsPoints;
  final DeviceTelemetryProvider _telemetry;
  final Clock _clock;

  /// Effective tracking config. Company settings may replace it at runtime via
  /// [applyConfig]; intervals are read live, so no tracking restart is needed
  /// when nothing changes.
  GpsTrackingConfig config;
  late GpsQualityFilter _filter;

  StreamSubscription<LocationFix>? _subscription;
  TrackingState _state = TrackingState.idle;
  bool _moving = false;
  bool _disposed = false;

  TrackingState get state => _state;
  bool get isTracking => _state == TrackingState.tracking;

  LocalGpsPoint? _lastAcceptedPoint;
  LocalGpsPoint? get lastAcceptedPoint => _lastAcceptedPoint;
  DateTime? get lastCapturedAt => _lastAcceptedPoint?.recordedAt;

  int _pendingCount = 0;
  int get pendingCount => _pendingCount;

  GpsRejectionReason? _lastRejection;
  GpsRejectionReason? get lastRejection => _lastRejection;

  String? _lastError;
  String? get lastError => _lastError;

  /// Starts collection for the active work session.
  ///
  /// [initialFix] (the Start Day fix) is accepted through the normal quality
  /// gate right after the stream is up, so it is persisted like any other
  /// point. Throws [StateError] when no local session is active.
  Future<void> start({LocationFix? initialFix}) async {
    if (_state == TrackingState.tracking) {
      return;
    }
    final session = await _workSessions.activeSession();
    if (session == null) {
      throw StateError(
        'GPS tracking refused: no active local work session. '
        'Start Day must create the session first.',
      );
    }

    _lastError = null;
    if (initialFix != null) {
      await _acceptFix(initialFix);
    }

    final moving = initialFix != null && _filter.isMoving(initialFix);
    await _subscribe(moving: moving);
    _state = TrackingState.tracking;
    await refreshPendingCount();
    _notify();
  }

  /// Applies company-settings-derived intervals while the service runs.
  ///
  /// When the collection interval actually changes, an active stream is
  /// resubscribed so the new interval takes effect; the foreground service and
  /// notification are re-established by the new subscription.
  void applyConfig(GpsTrackingConfig next) {
    final intervalChanged =
        next.movingInterval != config.movingInterval ||
        next.stationaryInterval != config.stationaryInterval;
    config = next;
    _filter = GpsQualityFilter(next);
    if (intervalChanged && _state == TrackingState.tracking) {
      unawaited(_subscribe(moving: _moving));
    }
  }

  /// Stops collection (End Day, logout, revocation, permission loss).
  ///
  /// Cancellation is not awaited: the stream subscription is detached
  /// immediately (no further fixes are accepted) and the platform-side cancel
  /// completes asynchronously.
  Future<void> stop() async {
    _cancelSubscription();
    if (_state != TrackingState.idle) {
      _state = TrackingState.idle;
      _notify();
    }
  }

  void _cancelSubscription() {
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
  }

  Future<void> _subscribe({required bool moving}) async {
    _cancelSubscription();
    _moving = moving;
    final interval = _filter.intervalFor(moving: moving);
    _subscription = _locationSource
        .fixes(interval: interval)
        .listen(
          (fix) async {
            await _acceptFix(fix);
          },
          onError: (Object error) {
            _lastError = error.toString();
            _state = TrackingState.error;
            _notify();
          },
          cancelOnError: false,
        );
  }

  Future<void> _acceptFix(LocationFix fix) async {
    if (_disposed) {
      return;
    }
    final now = _clock.now().toUtc();
    final rejection = _filter.rejectionFor(
      fix,
      previous: _lastAcceptedPoint,
      now: now,
    );
    if (rejection != null) {
      _lastRejection = rejection;
      _notify();
      return;
    }

    final telemetry = await _telemetry.read();
    final point = LocalGpsPoint(
      clientUuid: const Uuid().v4(),
      latitude: fix.latitude,
      longitude: fix.longitude,
      altitude: fix.altitude,
      accuracy: fix.accuracy,
      speed: fix.speed,
      heading: fix.heading,
      batteryLevel: telemetry.batteryLevel,
      isCharging: telemetry.isCharging,
      networkStatus: telemetry.networkStatus,
      isMockLocation: fix.isMocked,
      provider: fix.provider,
      recordedAt: fix.recordedAt,
      createdAt: now,
    );

    try {
      final stored = await _gpsPoints.insertPoint(point);
      _lastAcceptedPoint = stored;
      _pendingCount = await _gpsPoints.pendingCount();
      await _maybeAdaptInterval(fix);
    } catch (error) {
      _lastError = error.toString();
    }
    _notify();
  }

  /// Switches the collection interval between moving (15s) and stationary
  /// (60s) per the canonical design. Hysteresis (0.5× threshold to go back to
  /// stationary) avoids flapping on noisy speed readings.
  Future<void> _maybeAdaptInterval(LocationFix fix) async {
    final speed = fix.speed;
    if (speed == null || _subscription == null) {
      return;
    }
    final shouldBeMoving = _moving
        ? speed >= config.movementSpeedThreshold * 0.5
        : speed >= config.movementSpeedThreshold;
    if (shouldBeMoving != _moving) {
      await _subscribe(moving: shouldBeMoving);
    }
  }

  Future<void> refreshPendingCount() async {
    _pendingCount = await _gpsPoints.pendingCount();
    _notify();
  }

  /// Hydrates the in-memory "last captured" state from SQLite after an app
  /// restart, so the tracking UI and the debounce continue from the last
  /// persisted point instead of starting blank.
  Future<void> restoreLastPoint() async {
    _lastAcceptedPoint = await _gpsPoints.lastPoint();
    _notify();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelSubscription();
    super.dispose();
  }
}
