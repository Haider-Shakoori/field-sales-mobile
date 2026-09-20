import 'package:field_sales_mobile/features/visits/visit_map_data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  const kabul = LatLng(34.5553, 69.2075);

  test('buildMapCustomers keeps only customers with valid coordinates', () {
    final result = buildMapCustomers(
      customers: [
        {'id': 'c1', 'name': 'Alpha', 'latitude': 34.56, 'longitude': 69.21},
        {'id': 'c2', 'name': 'No coordinates'},
        {
          'id': 'c3',
          'name': 'Bad latitude',
          'latitude': 123.0,
          'longitude': 69.0,
        },
        {
          'id': 'c4',
          'name': 'String coordinates',
          'latitude': '34.57',
          'longitude': '69.22',
        },
      ],
      routes: const [],
      routeCustomers: const [],
    );

    expect(result.map((customer) => customer.id), ['c1', 'c4']);
  });

  test('planned order and route name come from route assignments', () {
    final result = buildMapCustomers(
      customers: [
        {'id': 'c1', 'name': 'Alpha', 'latitude': 34.56, 'longitude': 69.21},
      ],
      routes: [
        {'id': 'r1', 'name': 'North Route'},
      ],
      routeCustomers: [
        {'id': 'c1', 'route_id': 'r1', 'route_sequence': 3},
      ],
    );

    expect(result.single.plannedOrder, 3);
    expect(result.single.routeName, 'North Route');
  });

  test('lowest sequence wins when a customer is on multiple routes', () {
    final result = buildMapCustomers(
      customers: [
        {'id': 'c1', 'name': 'Alpha', 'latitude': 34.56, 'longitude': 69.21},
      ],
      routes: [
        {'id': 'r1', 'name': 'North Route'},
        {'id': 'r2', 'name': 'South Route'},
      ],
      routeCustomers: [
        {'id': 'c1', 'route_id': 'r1', 'route_sequence': 5},
        {'id': 'c1', 'route_id': 'r2', 'route_sequence': 2},
      ],
    );

    expect(result.single.plannedOrder, 2);
    expect(result.single.routeName, 'South Route');
  });

  test('sortByDistance orders customers nearest first', () {
    final customers = buildMapCustomers(
      customers: [
        {'id': 'far', 'name': 'Far', 'latitude': 34.80, 'longitude': 69.40},
        {'id': 'near', 'name': 'Near', 'latitude': 34.56, 'longitude': 69.21},
      ],
      routes: const [],
      routeCustomers: const [],
    );

    final sorted = sortByDistance(customers, kabul);

    expect(sorted.map((customer) => customer.id), ['near', 'far']);
    expect(distanceMeters(sorted.last, kabul), greaterThan(1000));
  });

  test('sortByDistance falls back to planned order without a position', () {
    final customers = buildMapCustomers(
      customers: [
        {
          'id': 'second',
          'name': 'Second',
          'latitude': 34.60,
          'longitude': 69.30,
        },
        {'id': 'first', 'name': 'First', 'latitude': 34.56, 'longitude': 69.21},
        {
          'id': 'unplanned',
          'name': 'Unplanned',
          'latitude': 34.57,
          'longitude': 69.22,
        },
      ],
      routes: const [],
      routeCustomers: [
        {'id': 'first', 'route_id': 'r1', 'route_sequence': 1},
        {'id': 'second', 'route_id': 'r1', 'route_sequence': 2},
      ],
    );

    final sorted = sortByDistance(customers, null);

    expect(sorted.map((customer) => customer.id), [
      'first',
      'second',
      'unplanned',
    ]);
  });

  test('formatDistance renders meters and kilometers', () {
    expect(formatDistance(120), '120 m');
    expect(formatDistance(949), '949 m');
    expect(formatDistance(1500), '1.5 km');
    expect(formatDistance(null), '');
  });
}
