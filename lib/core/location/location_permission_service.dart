import 'package:device_info_plus/device_info_plus.dart';
import 'package:geolocator/geolocator.dart' as geo;

/// Foreground location permission states the UI cares about.
enum LocationPermissionStatus {
  denied,
  deniedForever,
  whileInUse,
  always,
  unableToDetermine;

  bool get granted =>
      this == LocationPermissionStatus.whileInUse ||
      this == LocationPermissionStatus.always;
}

/// Result of checking/requesting "Allow all the time" background access.
enum BackgroundLocationAccess {
  granted,

  /// Not granted but the user can grant it from app settings.
  denied,

  /// Android requires the user to change this in system settings (Android 11+).
  needsSettings,

  /// Android < 10 has no separate background permission concept.
  unsupported,
}

/// Location permission flow used contextually by Start Day.
///
/// Widgets/services depend on this abstraction so tests can drive every
/// branch (service disabled, denied, permanently denied, granted).
abstract class LocationPermissionService {
  Future<bool> isServiceEnabled();

  Future<LocationPermissionStatus> checkForeground();

  Future<LocationPermissionStatus> requestForeground();

  Future<BackgroundLocationAccess> checkBackground();

  /// Requests background access where the OS allows a request; on Android 11+
  /// the OS mandates a trip to Settings, reported as
  /// [BackgroundLocationAccess.needsSettings].
  Future<BackgroundLocationAccess> requestBackground();

  Future<bool> openAppSettings();

  Future<bool> openLocationSettings();
}

/// geolocator + device_info backed implementation.
///
/// Android-version aware: the separate background permission only exists from
/// Android 10 (API 29); on API 30+ it can only be granted from system settings.
/// Tracking itself uses a location foreground service, which keeps working
/// while the app is backgrounded even without the background permission.
class GeolocatorPermissionService implements LocationPermissionService {
  GeolocatorPermissionService({Future<int> Function()? androidSdkIntProvider})
    : _androidSdkIntProvider =
          androidSdkIntProvider ?? DeviceSdkInfo.androidSdkInt;

  final Future<int> Function() _androidSdkIntProvider;

  @override
  Future<bool> isServiceEnabled() => geo.Geolocator.isLocationServiceEnabled();

  @override
  Future<LocationPermissionStatus> checkForeground() async =>
      _map(await geo.Geolocator.checkPermission());

  @override
  Future<LocationPermissionStatus> requestForeground() async =>
      _map(await geo.Geolocator.requestPermission());

  @override
  Future<BackgroundLocationAccess> checkBackground() async {
    final sdkInt = await _androidSdkIntProvider();
    if (sdkInt < 29) {
      return BackgroundLocationAccess.unsupported;
    }
    final permission = await geo.Geolocator.checkPermission();
    return permission == geo.LocationPermission.always
        ? BackgroundLocationAccess.granted
        : BackgroundLocationAccess.denied;
  }

  @override
  Future<BackgroundLocationAccess> requestBackground() async {
    final sdkInt = await _androidSdkIntProvider();
    if (sdkInt < 29) {
      return BackgroundLocationAccess.unsupported;
    }
    final current = await checkBackground();
    if (current == BackgroundLocationAccess.granted) {
      return current;
    }
    // Android 11+ (API 30+) forbids a runtime dialog for background location;
    // the only path is the app settings screen. geolocator cannot request it.
    return BackgroundLocationAccess.needsSettings;
  }

  @override
  Future<bool> openAppSettings() => geo.Geolocator.openAppSettings();

  @override
  Future<bool> openLocationSettings() => geo.Geolocator.openLocationSettings();

  LocationPermissionStatus _map(geo.LocationPermission permission) =>
      switch (permission) {
        geo.LocationPermission.denied => LocationPermissionStatus.denied,
        geo.LocationPermission.deniedForever =>
          LocationPermissionStatus.deniedForever,
        geo.LocationPermission.whileInUse =>
          LocationPermissionStatus.whileInUse,
        geo.LocationPermission.always => LocationPermissionStatus.always,
        geo.LocationPermission.unableToDetermine =>
          LocationPermissionStatus.unableToDetermine,
      };
}

/// `device_info_plus` is a transitive dependency; this helper keeps the
/// Android API-level lookup in one place and compiles on non-Android hosts.
class DeviceSdkInfo {
  DeviceSdkInfo._();

  static Future<int> androidSdkInt() async {
    final info = DeviceInfoPlugin();
    final android = await info.androidInfo;
    return android.version.sdkInt;
  }
}
