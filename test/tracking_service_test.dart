import 'package:field_sales_mobile/features/gps/tracking_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tracking watchdog waits long enough for normal moving intervals', () {
    expect(trackingStaleThresholdSeconds(15), 90);
    expect(trackingStaleThresholdSeconds(30), 180);
    expect(trackingStaleThresholdSeconds(60), 360);
  });
}
