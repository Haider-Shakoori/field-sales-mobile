/// Immutable location fix shape shared by the permission/source abstractions.
///
/// Widgets never touch plugin types directly; everything flows through
/// [LocationSource].
class LocationFix {
  const LocationFix({
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.accuracy,
    this.speed,
    this.heading,
    required this.recordedAt,
    this.isMocked = false,
    this.provider,
  });

  final double latitude;
  final double longitude;
  final double? altitude;
  final double? accuracy;
  final double? speed;
  final double? heading;
  final DateTime recordedAt;
  final bool isMocked;
  final String? provider;
}
