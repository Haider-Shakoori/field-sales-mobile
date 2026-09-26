import 'dart:io';

import 'package:field_sales_mobile/state/attendance_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stored attendance numeric values accept sqlite-compatible types', () {
    expect(parseAttendanceNumber(34), 34.0);
    expect(parseAttendanceNumber(34.5553), 34.5553);
    expect(parseAttendanceNumber('69.2075'), 69.2075);
    expect(parseAttendanceNumber(' 8.5 '), 8.5);
    expect(parseAttendanceNumber(null), isNull);
    expect(parseAttendanceNumber('not-a-number'), isNull);
  });

  test('raw runtime type errors are converted to a recoverable message', () {
    final message = friendlyAttendanceError(
      StateError("type 'int' is not a subtype of type 'double'"),
    );

    expect(
      message,
      'The saved attendance data could not be read safely. Refresh the page and try End Day again.',
    );
  });

  test('End Day only stops tracking after local completion succeeds', () {
    final source = File('lib/state/attendance_controller.dart')
        .readAsStringSync();
    final endDayStart = source.indexOf('Future<void> endDay(');
    final attendanceEnd = source.indexOf('await attendance.end(', endDayStart);
    final stopTracking = source.indexOf('tracking.stop();', attendanceEnd);

    expect(endDayStart, greaterThanOrEqualTo(0));
    expect(attendanceEnd, greaterThan(endDayStart));
    expect(stopTracking, greaterThan(attendanceEnd));
    expect(
      source.substring(endDayStart, attendanceEnd),
      contains('parseAttendanceNumber'),
    );
    expect(
      source.substring(endDayStart, stopTracking),
      contains('message = null;'),
    );
  });
}
