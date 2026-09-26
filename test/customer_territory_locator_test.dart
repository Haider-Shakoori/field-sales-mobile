import 'package:field_sales_mobile/features/customers/territory_locator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  test('detects point inside GeoJSON Polygon and excludes outside point', () {
    final territories = <Map<String, dynamic>>[
      {
        'id': 't-1',
        'code': 'T-1',
        'name': 'Central',
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
    ];

    expect(
      detectTerritoryForPoint(territories, const LatLng(34.60, 69.20))?['id'],
      't-1',
    );
    expect(
      detectTerritoryForPoint(territories, const LatLng(34.80, 69.20)),
      isNull,
    );
  });

  test('supports MultiPolygon and legacy latitude-longitude arrays', () {
    final multi = {
      'type': 'MultiPolygon',
      'coordinates': [
        [
          [
            [69.0, 34.0],
            [69.1, 34.0],
            [69.1, 34.1],
            [69.0, 34.1],
            [69.0, 34.0],
          ],
        ],
        [
          [
            [69.2, 34.2],
            [69.3, 34.2],
            [69.3, 34.3],
            [69.2, 34.3],
            [69.2, 34.2],
          ],
        ],
      ],
    };

    expect(
      territoryContainsPoint(multi, const LatLng(34.25, 69.25)),
      isTrue,
    );

    final legacy = [
      [34.50, 69.10],
      [34.50, 69.30],
      [34.70, 69.30],
      [34.70, 69.10],
    ];

    expect(
      territoryContainsPoint(legacy, const LatLng(34.60, 69.20)),
      isTrue,
    );
  });

  test('polygon holes are excluded', () {
    final geometry = {
      'type': 'Polygon',
      'coordinates': [
        [
          [69.0, 34.0],
          [69.4, 34.0],
          [69.4, 34.4],
          [69.0, 34.4],
          [69.0, 34.0],
        ],
        [
          [69.1, 34.1],
          [69.3, 34.1],
          [69.3, 34.3],
          [69.1, 34.3],
          [69.1, 34.1],
        ],
      ],
    };

    expect(
      territoryContainsPoint(geometry, const LatLng(34.05, 69.05)),
      isTrue,
    );
    expect(
      territoryContainsPoint(geometry, const LatLng(34.20, 69.20)),
      isFalse,
    );
  });
}
