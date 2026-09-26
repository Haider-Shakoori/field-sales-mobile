import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('customer cards keep identity and actions in separate responsive rows', () {
    final source = File('lib/ui/customers_screen.dart').readAsStringSync();

    expect(source, isNot(contains('trailing: Wrap(')));
    expect(source, contains('crossAxisAlignment: CrossAxisAlignment.stretch'));
    expect(source, contains('mainAxisAlignment: MainAxisAlignment.spaceAround'));
    expect(source, contains('maxLines: 2'));
    expect(source, contains('overflow: TextOverflow.ellipsis'));
    expect(source, contains('EdgeInsets.fromLTRB(16, 16, 16, 96)'));
  });
}
