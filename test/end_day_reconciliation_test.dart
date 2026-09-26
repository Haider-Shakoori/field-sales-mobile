import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('End Day reconciliation previews operational totals and remarks', () {
    final home = File('lib/ui/home_tab.dart').readAsStringSync();
    final controller =
        File('lib/state/attendance_controller.dart').readAsStringSync();
    final repository =
        File('lib/features/attendance/attendance_repository.dart')
            .readAsStringSync();

    expect(home, contains('End Day Reconciliation'));
    expect(home, contains('Missed / remaining customers'));
    expect(home, contains('End-of-day remarks (optional)'));
    expect(home, contains("triggerSource: 'end-day'"));
    expect(home, contains('Confirm End Day'));
    expect(controller, contains('Future<Map<String, dynamic>> endDaySummary()'));
    expect(controller, contains("'local_pending': pending"));
    expect(repository, contains("api.get('attendance/end-day-preview')"));
    expect(repository, contains("'notes': _clean(notes)"));
  });
}
