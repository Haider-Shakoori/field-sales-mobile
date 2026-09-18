import 'package:field_sales_mobile/core/models/workday_window.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const epsilon = Duration(seconds: 1);
  final daytime = WorkdayWindow.parse('08:00', '17:00')!;
  final overnight = WorkdayWindow.parse('20:00', '04:00')!;

  DateTime at(int hour, int minute) => DateTime(2026, 9, 18, hour, minute);

  group('WORKDAY WINDOW — parse', () {
    test('rejects malformed boundaries', () {
      expect(WorkdayWindow.parse('8am', '17:00'), isNull);
      expect(WorkdayWindow.parse('08:00', '25:00'), isNull);
      expect(WorkdayWindow.parse('08:60', '17:00'), isNull);
    });

    test('rejects an empty (start == end) window', () {
      expect(WorkdayWindow.parse('09:00', '09:00'), isNull);
    });

    test('exposes labels and overnight flag', () {
      expect(daytime.startLabel, '08:00');
      expect(daytime.endLabel, '17:00');
      expect(daytime.isOvernight, isFalse);
      expect(overnight.isOvernight, isTrue);
    });
  });

  group('WORKDAY WINDOW — daytime 08:00 → 17:00', () {
    test('contains boundaries correctly', () {
      expect(daytime.contains(at(8, 0)), isTrue);
      expect(daytime.contains(at(10, 15)), isTrue);
      expect(daytime.contains(at(16, 59)), isTrue);
      expect(daytime.contains(at(17, 0)), isFalse);
      expect(daytime.contains(at(7, 59)), isFalse);
      expect(daytime.contains(at(19, 0)), isFalse);
    });

    test('isBeforeStart only before the window', () {
      expect(daytime.isBeforeStart(at(7, 30)), isTrue);
      expect(daytime.isBeforeStart(at(8, 0)), isFalse);
      expect(daytime.isBeforeStart(at(19, 0)), isFalse);
    });

    test('next boundary before the window is the start', () {
      expect(
        daytime.nextBoundaryDelay(at(7, 30)),
        const Duration(minutes: 30) + epsilon,
      );
    });

    test('next boundary inside the window is the end', () {
      expect(
        daytime.nextBoundaryDelay(at(10, 0)),
        const Duration(hours: 7) + epsilon,
      );
    });

    test('next boundary after the window is tomorrow start', () {
      expect(
        daytime.nextBoundaryDelay(at(19, 0)),
        const Duration(hours: 13) + epsilon,
      );
    });
  });

  group('WORKDAY WINDOW — overnight 20:00 → 04:00', () {
    test('contains before midnight', () {
      expect(overnight.contains(at(20, 0)), isTrue);
      expect(overnight.contains(at(23, 30)), isTrue);
    });

    test('contains after midnight', () {
      expect(overnight.contains(at(0, 30)), isTrue);
      expect(overnight.contains(at(3, 59)), isTrue);
    });

    test('midnight itself is not an end boundary', () {
      // Contains at 00:00 because the window runs across midnight.
      expect(overnight.contains(at(0, 0)), isTrue);
    });

    test('end boundary is exclusive', () {
      expect(overnight.contains(at(4, 0)), isFalse);
    });

    test('the daytime gap is outside', () {
      expect(overnight.contains(at(10, 0)), isFalse);
      expect(overnight.contains(at(19, 59)), isFalse);
    });

    test('isBeforeStart during the daytime gap', () {
      expect(overnight.isBeforeStart(at(10, 0)), isTrue);
      expect(overnight.isBeforeStart(at(19, 0)), isTrue);
      expect(overnight.isBeforeStart(at(23, 0)), isFalse);
    });

    test('next boundary before the window is tonight start', () {
      expect(
        overnight.nextBoundaryDelay(at(19, 0)),
        const Duration(hours: 1) + epsilon,
      );
    });

    test('next boundary before midnight is tomorrow end', () {
      expect(
        overnight.nextBoundaryDelay(at(22, 0)),
        const Duration(hours: 6) + epsilon,
      );
    });

    test('next boundary after midnight is today end', () {
      expect(
        overnight.nextBoundaryDelay(at(1, 0)),
        const Duration(hours: 3) + epsilon,
      );
    });

    test('next boundary during the gap is today start', () {
      expect(
        overnight.nextBoundaryDelay(at(10, 0)),
        const Duration(hours: 10) + epsilon,
      );
    });
  });
}
