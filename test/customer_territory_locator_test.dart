import 'package:field_sales_mobile/features/customers/customer_territory_locator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('locates a customer inside a GeoJSON Polygon territory', () {
    final match = locateCustomerTerritory(
      [
        {
          'id': 'territory-1',
          'code': 'KBL-1',
          'name': 'Kabul One',
          'polygon': {
            'type': 'Polygon',
            'coordinates': [
              [
                [69.10, 34.50],
                [69.30, 34.50],
                [69.30, 34.70],
                [69.10, 34.70],
                [69.10, 34.50],
              ],
            ],
          },
        },
      ],
      34.60,
      69.20,
    );

    expect(match, isNotNull);
    expect(match!.id, 'territory-1');
    expect(match.name, 'Kabul One');
  });

  test(
    'supports legacy lat-lng territory arrays and rejects outside points',
    () {
      final territories = [
        {
          'id': 'legacy',
          'name': 'Legacy',
          'polygon': [
            [34.50, 69.10],
            [34.50, 69.30],
            [34.70, 69.30],
            [34.70, 69.10],
          ],
        },
      ];

      expect(locateCustomerTerritory(territories, 34.60, 69.20)?.id, 'legacy');
      expect(locateCustomerTerritory(territories, 35.0, 70.0), isNull);
    },
  );
}
