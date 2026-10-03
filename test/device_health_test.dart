import 'package:flutter_test/flutter_test.dart';

import 'package:field_sales_mobile/features/devices/device_health_repository.dart';

void main() {
  group('classifyDeviceHealth', () {
    test('inactive healthy device stays healthy', () {
      final result = classifyDeviceHealth({
        'battery_level': 80,
        'is_charging': false,
        'power_save_mode': false,
        'battery_optimization_exempt': true,
        'background_restricted': false,
        'location_services_enabled': true,
        'location_permission': 'always',
        'background_location_permission': 'granted',
        'notification_permission': 'granted',
        'background_tracking_active': false,
        'workday_active': false,
        'network_type': 'wifi',
        'storage_free_mb': 5000,
        'pending_sync_count': 4,
        'failed_sync_count': 0,
        'blocked_sync_count': 0,
        'is_physical_device': true,
        'root_signal_detected': false,
        'mock_location_detected': false,
      });

      expect(result.status, 'healthy');
      expect(result.issues, isEmpty);
    });

    test('active workday with broken tracking is critical', () {
      final result = classifyDeviceHealth({
        'battery_level': 4,
        'is_charging': false,
        'power_save_mode': true,
        'battery_optimization_exempt': false,
        'background_restricted': true,
        'location_services_enabled': false,
        'location_permission': 'denied',
        'background_location_permission': 'denied',
        'notification_permission': 'denied',
        'background_tracking_active': false,
        'workday_active': true,
        'network_type': 'cellular',
        'storage_free_mb': 40,
        'pending_sync_count': 150,
        'failed_sync_count': 3,
        'blocked_sync_count': 1,
        'last_gps_fix_at': DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 20))
            .toIso8601String(),
        'is_physical_device': true,
        'root_signal_detected': false,
        'mock_location_detected': true,
      });

      expect(result.status, 'critical');
      final codes = result.issues.map((issue) => issue['code']).toSet();
      expect(codes, contains('battery_critical'));
      expect(codes, contains('location_services_disabled'));
      expect(codes, contains('background_tracking_inactive'));
      expect(codes, contains('sync_blocked'));
      expect(codes, contains('mock_location_signal'));
    });

    test('integrity signals are warnings rather than proof of misuse', () {
      final result = classifyDeviceHealth({
        'battery_level': 60,
        'is_charging': false,
        'workday_active': false,
        'network_type': 'wifi',
        'storage_free_mb': 5000,
        'pending_sync_count': 0,
        'failed_sync_count': 0,
        'blocked_sync_count': 0,
        'is_physical_device': false,
        'root_signal_detected': true,
        'mock_location_detected': true,
      });

      expect(result.status, 'warning');
      expect(
        result.issues.firstWhere(
          (issue) => issue['code'] == 'root_signal',
        )['severity'],
        'warning',
      );
      expect(
        result.issues.firstWhere(
          (issue) => issue['code'] == 'non_physical_device',
        )['severity'],
        'info',
      );
    });
  });
}
