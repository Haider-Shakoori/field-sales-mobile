import 'package:battery_plus/battery_plus.dart';

import '../../core/sync/connectivity_service.dart';

/// Device metadata attached to every GPS point (battery / network telemetry).
class DeviceTelemetry {
  const DeviceTelemetry({
    this.batteryLevel,
    this.isCharging = false,
    this.networkStatus,
  });

  final int? batteryLevel;
  final bool isCharging;
  final String? networkStatus;
}

/// Telemetry abstraction so tests do not touch battery/connectivity plugins.
abstract class DeviceTelemetryProvider {
  Future<DeviceTelemetry> read();
}

/// battery_plus + connectivity backed implementation.
///
/// Battery reads are best-effort: a missing plugin/permission yields nulls
/// rather than failing a GPS capture.
class PlatformDeviceTelemetryProvider implements DeviceTelemetryProvider {
  PlatformDeviceTelemetryProvider({
    required ConnectivityService connectivity,
    Battery? battery,
  }) : _connectivity = connectivity,
       _battery = battery ?? Battery();

  final ConnectivityService _connectivity;
  final Battery _battery;

  @override
  Future<DeviceTelemetry> read() async {
    int? level;
    var charging = false;
    try {
      level = await _battery.batteryLevel;
      final state = await _battery.batteryState;
      charging = state == BatteryState.charging || state == BatteryState.full;
    } catch (_) {
      // Telemetry is optional; never block a GPS capture on it.
    }
    return DeviceTelemetry(
      batteryLevel: level,
      isCharging: charging,
      networkStatus: _connectivity.connectionType,
    );
  }
}
