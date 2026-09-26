import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mobile customer creation requires a map-selected shop location', () {
    final screen = File('lib/ui/customer_create_screen.dart')
        .readAsStringSync();
    final customers = File('lib/ui/customers_screen.dart').readAsStringSync();
    final controller = File('lib/state/master_data_controller.dart')
        .readAsStringSync();
    final repository = File('lib/features/customers/customer_repository.dart')
        .readAsStringSync();

    expect(screen, contains('FlutterMap('));
    expect(screen, contains('Shop location'));
    expect(screen, contains('My location'));
    expect(screen, contains('onTap: (_, point) => _selectLocation(point)'));
    expect(screen, contains('latitude: _shopLocation!.latitude'));
    expect(screen, contains('longitude: _shopLocation!.longitude'));
    expect(screen, contains('Select the exact shop location on the map'));
    expect(customers, contains('CustomerCreateScreen'));
    expect(controller, contains('double? latitude'));
    expect(controller, contains('double? longitude'));
    expect(repository, contains("'latitude': ?latitude"));
    expect(repository, contains("'longitude': ?longitude"));
  });
}
