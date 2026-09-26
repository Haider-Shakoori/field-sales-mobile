import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mobile diagnostics are best-effort and wired to End Day and sync', () {
    final reporter = File('lib/features/diagnostics/diagnostic_reporter.dart')
        .readAsStringSync();
    final attendance = File('lib/state/attendance_controller.dart')
        .readAsStringSync();
    final sync = File('lib/state/sync_controller.dart').readAsStringSync();
    final mainSource = File('lib/main.dart').readAsStringSync();

    expect(reporter, contains("api.post("));
    expect(reporter, contains("'mobile/diagnostics'"));
    expect(reporter, contains('Bearer [redacted]'));
    expect(reporter, contains('Diagnostics'));
    expect(attendance, contains("area: 'attendance.end_day'"));
    expect(attendance, contains("area: 'attendance.end_day_preview'"));
    expect(sync, contains("area: 'sync.cycle'"));
    expect(
      mainSource,
      contains('final diagnostics = DiagnosticReporter(api);'),
    );
    expect(mainSource, contains('diagnostics: diagnostics'));
  });
}
