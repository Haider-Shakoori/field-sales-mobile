import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('customer screen offers WhatsApp and SMS composer', () {
    final source = File('lib/ui/customers_screen.dart').readAsStringSync();
    final compact = source.replaceAll(RegExp(r'\s+'), ' ');

    expect(source, contains("value: 'whatsapp'"));
    expect(source, contains("value: 'sms'"));
    expect(source, contains("Uri.https('wa.me'"));
    expect(source, contains("Uri(scheme: 'sms'"));
    expect(compact, contains("tooltip: phone.isEmpty ? 'No phone' : 'Message'"));
    expect(source, contains('LaunchMode.externalApplication'));
  });
}
