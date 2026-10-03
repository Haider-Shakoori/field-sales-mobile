import 'package:field_sales_mobile/features/gps/tracking_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tracking watchdog waits long enough for normal moving intervals', () {
    expect(trackingStaleThresholdSeconds(15), 90);
    expect(trackingStaleThresholdSeconds(30), 180);
    expect(trackingStaleThresholdSeconds(60), 360);
  });

  test('iOS tracking enables background location updates', () {
    final settings = trackingLocationSettings(isIOS: true, movingSeconds: 15);

    expect(settings, isA<AppleSettings>());
    final apple = settings as AppleSettings;
    expect(apple.allowBackgroundLocationUpdates, isTrue);
    expect(apple.pauseLocationUpdatesAutomatically, isFalse);
    expect(apple.distanceFilter, 5);
  });

  test('Android tracking keeps the foreground service configuration', () {
    final settings = trackingLocationSettings(isIOS: false, movingSeconds: 15);

    expect(settings, isA<AndroidSettings>());
    final android = settings as AndroidSettings;
    expect(android.intervalDuration, const Duration(seconds: 15));
    expect(android.distanceFilter, 5);
  });
}
