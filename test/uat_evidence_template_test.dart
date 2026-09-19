import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('UAT evidence template preserves not-executed manual boundary', () {
    final template = File('UAT_RESULTS_TEMPLATE.md').readAsStringSync();

    for (var i = 1; i <= 15; i++) {
      expect(template, contains('UAT-${i.toString().padLeft(2, '0')}'));
    }

    expect(template, contains('NOT EXECUTED'));
    expect(
      template,
      contains('Final decision: **NOT APPROVED / APPROVED FOR BATCH 20**'),
    );
    expect(
      template,
      isNot(contains('Final decision: **APPROVED FOR BATCH 20**')),
    );
  });
}
