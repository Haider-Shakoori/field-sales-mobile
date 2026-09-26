import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('completed same-day attendance can be reopened from Home', () {
    final controller = File('lib/state/attendance_controller.dart')
        .readAsStringSync();
    final repository = File(
      'lib/features/attendance/attendance_repository.dart',
    ).readAsStringSync();
    final home = File('lib/ui/home_tab.dart').readAsStringSync();

    expect(controller, contains('bool get canReopenToday'));
    expect(controller, contains('Future<void> reopenDay() async'));
    expect(controller, contains('await attendance.reopen('));
    expect(repository, contains("'action': 'reopen'"));
    expect(repository, contains("orderBy: 'id ASC'"));
    expect(home, contains('controller.canReopenToday'));
    expect(home, contains("const Text('Reopen Day')"));
    expect(home, contains('Your original '));
    expect(
      home,
      contains('Start Day time and existing visits, orders, collections'),
    );
  });
}
