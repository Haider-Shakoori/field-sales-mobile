import '../../core/models/attendance_tracking_settings.dart';

/// Configurable GPS tracking parameters.
///
/// Values follow the canonical GPS tracking design (`GPS_TRACKING_DESIGN.md`
/// §4/§5/§14) and the offline sync design's GPS batch cadence. Company
/// settings override the collection intervals through [fromSettings]; all
/// other values keep the canonical Batch 7 defaults.
class GpsTrackingConfig {
  const GpsTrackingConfig({
    this.movingInterval = const Duration(seconds: 15),
    this.stationaryInterval = const Duration(seconds: 60),
    this.movementSpeedThreshold = 0.5,
    this.maxAccuracyMeters = 100,
    this.debounceDistanceMeters = 5,
    this.debounceWindow = const Duration(seconds: 5),
    this.maxFutureSkew = const Duration(minutes: 5),
    this.startFixTimeout = const Duration(seconds: 20),
    this.endFixTimeout = const Duration(seconds: 10),
    this.recentFixMaxAge = const Duration(minutes: 10),
    this.batchFlushInterval = const Duration(minutes: 5),
    this.uploadedRetention = const Duration(days: 7),
    this.batchSize = 100,
  });

  /// Builds the effective tracking config from trusted company settings.
  factory GpsTrackingConfig.fromSettings(AttendanceTrackingSettings settings) {
    const fallback = GpsTrackingConfig();
    return GpsTrackingConfig(
      movingInterval: Duration(seconds: settings.gpsMovingIntervalSeconds),
      stationaryInterval: Duration(
        seconds: settings.gpsStationaryIntervalSeconds,
      ),
      movementSpeedThreshold: fallback.movementSpeedThreshold,
      maxAccuracyMeters: fallback.maxAccuracyMeters,
      debounceDistanceMeters: fallback.debounceDistanceMeters,
      debounceWindow: fallback.debounceWindow,
      maxFutureSkew: fallback.maxFutureSkew,
      startFixTimeout: fallback.startFixTimeout,
      endFixTimeout: fallback.endFixTimeout,
      recentFixMaxAge: fallback.recentFixMaxAge,
      batchFlushInterval: fallback.batchFlushInterval,
      uploadedRetention: fallback.uploadedRetention,
      batchSize: fallback.batchSize,
    );
  }

  /// Collection interval while the salesman is moving (canonical: 15s).
  final Duration movingInterval;

  /// Collection interval while stationary (canonical: 60s).
  final Duration stationaryInterval;

  /// Speed (m/s) at/above which the device is considered moving.
  final double movementSpeedThreshold;

  /// Client-side accuracy cut. The server rejects > 200 m; the tenant default
  /// (`min_accuracy_threshold`) is 100 m, so the client uses the stricter,
  /// documented value.
  final double maxAccuracyMeters;

  /// Debounce: skip a fix within this distance AND window of the previous
  /// accepted point.
  final double debounceDistanceMeters;
  final Duration debounceWindow;

  /// Reject fixes timestamped further than this into the future.
  final Duration maxFutureSkew;

  /// One-shot fix timeouts for Start Day / End Day.
  final Duration startFixTimeout;
  final Duration endFixTimeout;

  /// End Day may fall back to an accepted point no older than this.
  final Duration recentFixMaxAge;

  /// Dedicated GPS uploader flush cadence while tracking (canonical 300s).
  final Duration batchFlushInterval;

  /// Uploaded points older than this may be purged locally.
  final Duration uploadedRetention;

  /// Maximum points per upload request (contract hard limit is 100).
  final int batchSize;
}
