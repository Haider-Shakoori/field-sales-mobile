import 'package:latlong2/latlong.dart';

class MapCustomer {
  const MapCustomer({
    required this.customer,
    required this.point,
    this.plannedOrder,
    this.routeName,
  });

  final Map<String, dynamic> customer;
  final LatLng point;
  final int? plannedOrder;
  final String? routeName;

  String get id => '${customer['id']}';
  String get name => '${customer['name'] ?? 'Customer'}';
  String get address => '${customer['address'] ?? ''}';
}

double? _coordinate(dynamic value) {
  if (value is num) {
    return value.toDouble();
  }

  return double.tryParse('$value');
}

List<MapCustomer> buildMapCustomers({
  required List<Map<String, dynamic>> customers,
  required List<Map<String, dynamic>> routes,
  required List<Map<String, dynamic>> routeCustomers,
}) {
  final routeNames = <String, String>{
    for (final route in routes)
      if (route['id'] != null) '${route['id']}': '${route['name'] ?? 'Route'}',
  };

  final planned = <String, ({int order, String? routeName})>{};

  for (final row in routeCustomers) {
    final customerId = row['id']?.toString();
    final sequence = row['route_sequence'];

    if (customerId == null || sequence is! num) {
      continue;
    }

    final order = sequence.toInt();
    final existing = planned[customerId];

    if (existing == null || order < existing.order) {
      planned[customerId] = (
        order: order,
        routeName: routeNames[row['route_id']?.toString()],
      );
    }
  }

  final result = <MapCustomer>[];

  for (final customer in customers) {
    final latitude = _coordinate(customer['latitude']);
    final longitude = _coordinate(customer['longitude']);

    if (latitude == null || longitude == null) {
      continue;
    }

    if (latitude.abs() > 90 || longitude.abs() > 180) {
      continue;
    }

    final plan = planned[customer['id']?.toString()];

    result.add(
      MapCustomer(
        customer: customer,
        point: LatLng(latitude, longitude),
        plannedOrder: plan?.order,
        routeName: plan?.routeName,
      ),
    );
  }

  return result;
}

double? distanceMeters(MapCustomer customer, LatLng? origin) {
  if (origin == null) {
    return null;
  }

  return const Distance().as(LengthUnit.Meter, origin, customer.point);
}

List<MapCustomer> sortByDistance(List<MapCustomer> customers, LatLng? origin) {
  final sorted = [...customers];

  if (origin == null) {
    sorted.sort((a, b) {
      final byOrder = (a.plannedOrder ?? 1 << 30).compareTo(
        b.plannedOrder ?? 1 << 30,
      );

      return byOrder != 0 ? byOrder : a.name.compareTo(b.name);
    });

    return sorted;
  }

  const distance = Distance();

  sorted.sort((a, b) {
    final aMeters = distance.as(LengthUnit.Meter, origin, a.point);
    final bMeters = distance.as(LengthUnit.Meter, origin, b.point);

    return aMeters.compareTo(bMeters);
  });

  return sorted;
}

String formatDistance(double? meters) {
  if (meters == null) {
    return '';
  }

  if (meters < 950) {
    return '${meters.round()} m';
  }

  return '${(meters / 1000).toStringAsFixed(1)} km';
}
