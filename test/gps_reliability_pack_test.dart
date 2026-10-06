import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('GPS reliability pack keeps tracking self-healing', () {
    final tracking =
        File('lib/features/gps/tracking_service.dart').readAsStringSync();
    final attendance =
        File('lib/state/attendance_controller.dart').readAsStringSync();
    final gps = File('lib/features/gps/gps_repository.dart').readAsStringSync();
    final native = File(
      'android/app/src/main/kotlin/com/businessos/fieldpulse/MainActivity.kt',
    ).readAsStringSync();
    final diagnostics =
        File('lib/ui/mobile_diagnostics_screen.dart').readAsStringSync();

    expect(tracking, contains('bool _processingPosition = false'));
    expect(tracking, contains('Position? _queuedPosition'));
    expect(tracking, contains('getServiceStatusStream()'));
    expect(tracking, contains('enableWakeLock: true'));
    expect(tracking, contains('enableWifiLock: true'));
    expect(tracking, contains('distanceFilter: 0'));
    expect(tracking, contains('Tracking reliability:'));
    expect(tracking, contains('Duration(minutes: 2)'));

    expect(attendance, contains('with WidgetsBindingObserver'));
    expect(attendance, contains('AppLifecycleState.resumed'));
    expect(attendance, contains('_recoverAfterResume()'));
    expect(attendance, contains('_refreshTrackingWarning()'));

    expect(gps, contains('Future<void> uploadAll('));
    expect(gps, contains("_telemetryCache"));
    expect(gps, contains('maxBatches = 5'));

    expect(native, contains('openLocationSettings'));
    expect(native, contains('openBatterySettings'));
    expect(native, contains('ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS'));

    expect(diagnostics, contains('Tracking reliability'));
    expect(diagnostics, contains('GPS points · last hour'));
    expect(diagnostics, contains('Pending GPS points'));
  });
}
