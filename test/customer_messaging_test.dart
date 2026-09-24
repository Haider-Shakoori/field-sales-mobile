import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('customer screen offers WhatsApp and SMS composer', () {
    final source = File('lib/ui/customers_screen.dart').readAsStringSync();

    expect(source, contains("value: 'whatsapp'"));
    expect(source, contains("value: 'sms'"));
    expect(source, contains("Uri.https('wa.me'"));
    expect(source, contains("Uri(scheme: 'sms'"));
    expect(source, contains("tooltip: phone.isEmpty ? 'No phone' : 'Message'"));
    expect(source, contains('LaunchMode.externalApplication'));
  });
}
