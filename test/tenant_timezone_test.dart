import 'package:field_sales_mobile/core/models/workday_window.dart';
import 'package:field_sales_mobile/core/time/tenant_time.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_harness.dart';

void main() {
  const epsilon = Duration(seconds: 1);

  group('TENANT TIME RESOLVER', () {
    test('validates IANA zones and rejects invalid/missing values', () {
      final resolver = TenantTimeResolver();

      expect(resolver.isValidTimezone('UTC'), isTrue);
      expect(resolver.isValidTimezone('Asia/Kabul'), isTrue);
      expect(resolver.isValidTimezone('Asia/Karachi'), isTrue);
      expect(resolver.isValidTimezone('Europe/London'), isTrue);
      expect(resolver.isValidTimezone('America/Toronto'), isTrue);
      expect(resolver.isValidTimezone('Not/AZone'), isFalse);
      expect(resolver.isValidTimezone(null), isFalse);
      expect(resolver.isValidTimezone(''), isFalse);
    });

    test('converts one instant into tenant wall time', () {
      final resolver = TenantTimeResolver(
        clock: TestClock(DateTime.utc(2026, 9, 18, 10)),
      );

      final kabul = resolver.nowIn('Asia/Kabul');
      expect(kabul, isNotNull);
      expect(kabul!.hour, 14);
      expect(kabul.minute, 30);

      final utc = resolver.nowIn('UTC');
      expect(utc!.hour, 10);
      expect(utc.minute, 0);

      expect(resolver.nowIn(null), isNull);
      expect(resolver.nowIn('Not/AZone'), isNull);
    });

    test('applies DST via the IANA database (London BST vs GMT)', () {
      final july = TenantTimeResolver(
        clock: TestClock(DateTime.utc(2026, 7, 1, 12)),
      ).nowIn('Europe/London')!;
      expect(july.hour, 13, reason: 'BST is UTC+1 in July');

      final january = TenantTimeResolver(
        clock: TestClock(DateTime.utc(2026, 1, 15, 12)),
      ).nowIn('Europe/London')!;
      expect(january.hour, 12, reason: 'GMT is UTC+0 in January');
    });

    test('atIn converts an arbitrary instant into tenant wall time', () {
      final resolver = TenantTimeResolver(
        clock: TestClock(DateTime.utc(2026, 1, 1)),
      );

      final kabul = resolver.atIn(
        'Asia/Kabul',
        DateTime.utc(2026, 9, 18, 16, 30),
      )!;
      expect(kabul.hour, 21);
      expect(kabul.minute, 0);
      expect(resolver.atIn('Not/AZone', DateTime.utc(2026, 9, 18)), isNull);
    });

    test('computes the next boundary in the tenant zone (daytime)', () {
      // 03:00 UTC = 07:30 Kabul; the 08:00 boundary is 30 minutes away.
      final resolver = TenantTimeResolver(
        clock: TestClock(DateTime.utc(2026, 9, 18, 3)),
      );
      final window = WorkdayWindow.parse('08:00', '17:00')!;

      expect(
        resolver.nextBoundaryDelay(window, 'Asia/Kabul'),
        const Duration(minutes: 30) + epsilon,
      );
      expect(resolver.nextBoundaryDelay(window, null), isNull);
      expect(resolver.nextBoundaryDelay(window, 'Not/AZone'), isNull);
    });

    test('computes the next boundary in the tenant zone (overnight)', () {
      // 16:30 UTC = 21:00 Kabul; the overnight window ends at 04:00 Kabul,
      // which is 7 hours away (23:30 UTC), not tomorrow's 20:00 start.
      final resolver = TenantTimeResolver(
        clock: TestClock(DateTime.utc(2026, 9, 18, 16, 30)),
      );
      final window = WorkdayWindow.parse('20:00', '04:00')!;

      expect(
        resolver.nextBoundaryDelay(window, 'Asia/Kabul'),
        const Duration(hours: 7) + epsilon,
      );
    });

    test('boundary delay is DST-aware (London BST)', () {
      // 10:00 UTC = 11:00 London; the 17:00 BST end boundary is at 16:00 UTC.
      final resolver = TenantTimeResolver(
        clock: TestClock(DateTime.utc(2026, 7, 1, 10)),
      );
      final window = WorkdayWindow.parse('08:00', '17:00')!;

      expect(
        resolver.nextBoundaryDelay(window, 'Europe/London'),
        const Duration(hours: 6) + epsilon,
      );
    });
  });
}
