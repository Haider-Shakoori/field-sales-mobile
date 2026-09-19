import 'package:field_sales_mobile/core/api/api_client.dart';
import 'package:field_sales_mobile/core/storage/secret_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all master-data paths get exactly one base-url separator', () {
    final client = ApiClient(SecretStore());

    for (final path in [
      'customers',
      '/customers',
      'territories',
      'routes',
      'routes/route-uuid/customers',
      'products',
      'price-lists',
      'price-lists/price-list-uuid/items',
      'settings/attendance-tracking',
    ]) {
      final url = client.path(path);

      expect(url, contains('/api/v1/'));
      expect(url, isNot(contains('/api/v1customers')));
      expect(url, isNot(contains('/api/v1products')));
    }

    expect(client.path('customers'), endsWith('/api/v1/customers'));
    expect(client.path('/customers'), endsWith('/api/v1/customers'));
  });
}
