import 'package:geolocator/geolocator.dart';

import 'location_fix.dart';

/// Accuracy presets exposed to callers (kept package-agnostic).
enum LocationAccuracyPreset { balanced, high, best }

/// The app-facing location abstraction.
///
/// Production uses [GeolocatorLocationSource] (Android fused provider when
/// available); tests inject a fake so tracking/filtering/upload logic never
/// touches platform channels.
abstract class LocationSource {
  /// Whether the OS location service (GPS toggle) is enabled.
  Future<bool> isServiceEnabled();

  /// One-shot fix used for Start Day / End Day.
  ///
  /// Returns null when no fix could be obtained within [timeout] instead of
  /// throwing, so callers can apply their own fallback behavior.
  Future<LocationFix?> currentFix({
    Duration timeout = const Duration(seconds: 20),
    LocationAccuracyPreset accuracy = LocationAccuracyPreset.high,
  });

  /// Continuous fixes for active-session tracking.
  ///
  /// When [foregroundNotification] is true (production), Android runs the
  /// stream inside a foreground service with a persistent notification.
  Stream<LocationFix> fixes({
    required Duration interval,
    bool foregroundNotification = true,
  });
}

/// geolocator-backed implementation.
///
/// Android behavior: the default provider is the fused location provider when
/// Google Play services are available (the plugin falls back to
/// LocationManager otherwise). `provider` is reported as `fused` accordingly;
/// the plugin does not expose a per-fix provider string.
class GeolocatorLocationSource implements LocationSource {
  const GeolocatorLocationSource({
    this.notificationTitle = 'Field Sales',
    this.notificationText = 'Location tracking active',
    this.notificationChannelName = 'Field Sales Tracking',
  });

  final String notificationTitle;
  final String notificationText;
  final String notificationChannelName;

  @override
  Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();

  @override
  Future<LocationFix?> currentFix({
    Duration timeout = const Duration(seconds: 20),
    LocationAccuracyPreset accuracy = LocationAccuracyPreset.high,
  }) async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: AndroidSettings(
          accuracy: _accuracy(accuracy),
          timeLimit: timeout,
        ),
      );
      return _toFix(position);
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<LocationFix> fixes({
    required Duration interval,
    bool foregroundNotification = true,
  }) {
    final settings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,
      intervalDuration: interval,
      foregroundNotificationConfig: foregroundNotification
          ? ForegroundNotificationConfig(
              notificationTitle: notificationTitle,
              notificationText: notificationText,
              notificationChannelName: notificationChannelName,
              setOngoing: true,
              enableWakeLock: true,
            )
          : null,
    );
    return Geolocator.getPositionStream(locationSettings: settings).map(_toFix);
  }

  LocationAccuracy _accuracy(LocationAccuracyPreset preset) => switch (preset) {
    LocationAccuracyPreset.balanced => LocationAccuracy.medium,
    LocationAccuracyPreset.high => LocationAccuracy.high,
    LocationAccuracyPreset.best => LocationAccuracy.best,
  };

  LocationFix _toFix(Position position) => LocationFix(
    latitude: position.latitude,
    longitude: position.longitude,
    altitude: position.altitude,
    accuracy: position.accuracy,
    speed: position.speed,
    heading: position.heading,
    recordedAt: position.timestamp.toUtc(),
    isMocked: position.isMocked,
    provider: 'fused',
  );
}
