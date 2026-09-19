import 'package:field_sales_mobile/core/config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('debug configuration permits the emulator HTTP default', () {
    expect(() => AppConfig.validateForStartup(productMode: false), returnsNormally);
    expect(AppConfig.apiBaseUrl, endsWith('/api/v1'));
  });

  test('product validation fails closed without explicit release defines', () {
    expect(
      () => AppConfig.validateForStartup(productMode: true),
      throwsA(isA<StateError>()),
    );
  });
}
