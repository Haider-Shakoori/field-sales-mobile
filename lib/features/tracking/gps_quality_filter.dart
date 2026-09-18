import 'dart:math' as math;

import '../../core/location/location_fix.dart';
import '../../core/models/gps_point.dart';
import 'gps_tracking_config.dart';

/// Why a fix was not accepted into the local GPS buffer.
enum GpsRejectionReason {
  invalidCoordinates,
  emptyCoordinates,
  poorAccuracy,
  futureTimestamp,
  debounce;

  String get label => switch (this) {
    GpsRejectionReason.invalidCoordinates => 'invalid_coordinates',
    GpsRejectionReason.emptyCoordinates => 'empty_coordinates',
    GpsRejectionReason.poorAccuracy => 'poor_accuracy',
    GpsRejectionReason.futureTimestamp => 'future_timestamp',
    GpsRejectionReason.debounce => 'debounce',
  };
}

/// Client-side GPS quality gate.
///
/// Mirrors the canonical server rules that are cheap to apply on-device
/// (bounds, empty coordinates, accuracy, future timestamp) plus the documented
/// 5 m / 5 s debounce. The server validates everything again, so this filter
/// only protects local storage and upload bandwidth — it intentionally does
/// NOT do route smoothing.
class GpsQualityFilter {
  const GpsQualityFilter(this.config);

  final GpsTrackingConfig config;

  /// Returns null when [fix] is acceptable, otherwise the rejection reason.
  GpsRejectionReason? rejectionFor(
    LocationFix fix, {
    LocalGpsPoint? previous,
    DateTime? now,
  }) {
    if (fix.latitude < -90 ||
        fix.latitude > 90 ||
        fix.longitude < -180 ||
        fix.longitude > 180 ||
        fix.latitude.isNaN ||
        fix.longitude.isNaN) {
      return GpsRejectionReason.invalidCoordinates;
    }
    if (fix.latitude == 0 && fix.longitude == 0) {
      return GpsRejectionReason.emptyCoordinates;
    }

    final accuracy = fix.accuracy;
    if (accuracy != null && accuracy > config.maxAccuracyMeters) {
      return GpsRejectionReason.poorAccuracy;
    }

    final reference = now ?? DateTime.now().toUtc();
    if (fix.recordedAt.isAfter(reference.add(config.maxFutureSkew))) {
      return GpsRejectionReason.futureTimestamp;
    }

    if (previous != null) {
      final elapsed = fix.recordedAt.difference(previous.recordedAt).abs();
      final distance = haversineMeters(
        previous.latitude,
        previous.longitude,
        fix.latitude,
        fix.longitude,
      );
      if (distance <= config.debounceDistanceMeters &&
          elapsed <= config.debounceWindow) {
        return GpsRejectionReason.debounce;
      }
    }
    return null;
  }

  /// True when [fix] is considered movement (used for adaptive intervals).
  bool isMoving(LocationFix fix) {
    final speed = fix.speed;
    if (speed == null) {
      return false;
    }
    return speed >= config.movementSpeedThreshold;
  }

  Duration intervalFor({required bool moving}) =>
      moving ? config.movingInterval : config.stationaryInterval;
}

/// Great-circle distance in meters (haversine, R = 6,371,000 m).
double haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  const earthRadius = 6371000.0;
  final dLat = _radians(lat2 - lat1);
  final dLon = _radians(lon2 - lon1);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_radians(lat1)) *
          math.cos(_radians(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadius * c;
}

double _radians(double degrees) => degrees * math.pi / 180.0;
