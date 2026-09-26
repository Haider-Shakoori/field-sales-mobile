class CustomerTerritoryMatch {
  const CustomerTerritoryMatch({
    required this.id,
    required this.name,
    this.code,
  });

  final String id;
  final String name;
  final String? code;
}

CustomerTerritoryMatch? locateCustomerTerritory(
  List<Map<String, dynamic>> territories,
  double latitude,
  double longitude,
) {
  for (final territory in territories) {
    final geometry = territory['polygon'];
    if (_geometryContains(geometry, latitude, longitude)) {
      final id = territory['id']?.toString();
      if (id == null || id.isEmpty) continue;

      return CustomerTerritoryMatch(
        id: id,
        name: territory['name']?.toString() ?? 'Territory',
        code: territory['code']?.toString(),
      );
    }
  }

  return null;
}

bool _geometryContains(dynamic geometry, double latitude, double longitude) {
  if (geometry is! Map && geometry is! List) return false;

  // Legacy FieldPulse geometry: [[lat, lng], ...].
  if (geometry is List && geometry.length >= 3) {
    final ring = geometry
        .whereType<List>()
        .where((point) => point.length >= 2)
        .map(
          (point) => <double>[
            _number(point[1]) ?? double.nan,
            _number(point[0]) ?? double.nan,
          ],
        )
        .where((point) => point.every((value) => value.isFinite))
        .toList();

    return _polygonContains([ring], latitude, longitude);
  }

  if (geometry is! Map) return false;
  final type = geometry['type']?.toString();
  final coordinates = geometry['coordinates'];
  if (coordinates is! List) return false;

  if (type == 'Polygon') {
    return _polygonContains(_rings(coordinates), latitude, longitude);
  }

  if (type == 'MultiPolygon') {
    for (final polygon in coordinates) {
      if (polygon is List &&
          _polygonContains(_rings(polygon), latitude, longitude)) {
        return true;
      }
    }
  }

  return false;
}

List<List<List<double>>> _rings(List<dynamic> raw) {
  return raw
      .whereType<List>()
      .map(
        (ring) => ring
            .whereType<List>()
            .where((point) => point.length >= 2)
            .map(
              (point) => <double>[
                _number(point[0]) ?? double.nan,
                _number(point[1]) ?? double.nan,
              ],
            )
            .where((point) => point.every((value) => value.isFinite))
            .toList(),
      )
      .where((ring) => ring.length >= 3)
      .toList();
}

bool _polygonContains(
  List<List<List<double>>> rings,
  double latitude,
  double longitude,
) {
  if (rings.isEmpty || !_ringContains(rings.first, latitude, longitude)) {
    return false;
  }

  for (final hole in rings.skip(1)) {
    if (_ringContains(hole, latitude, longitude)) {
      return false;
    }
  }

  return true;
}

bool _ringContains(
  List<List<double>> ring,
  double latitude,
  double longitude,
) {
  if (ring.length < 3) return false;

  var inside = false;

  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final xi = ring[i][0];
    final yi = ring[i][1];
    final xj = ring[j][0];
    final yj = ring[j][1];

    if (_pointOnSegment(longitude, latitude, xi, yi, xj, yj)) {
      return true;
    }

    final crosses =
        ((yi > latitude) != (yj > latitude)) &&
        (longitude <
            ((xj - xi) * (latitude - yi) / ((yj - yi).abs() < 1e-12 ? 1e-12 : (yj - yi))) +
                xi);

    if (crosses) inside = !inside;
  }

  return inside;
}

bool _pointOnSegment(
  double x,
  double y,
  double x1,
  double y1,
  double x2,
  double y2,
) {
  final cross = (x - x1) * (y2 - y1) - (y - y1) * (x2 - x1);
  if (cross.abs() > 1e-9) return false;

  final lengthSquared = (x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1);
  if (lengthSquared <= 1e-18) {
    final dx = x - x1;
    final dy = y - y1;
    return dx * dx + dy * dy <= 1e-18;
  }

  final dot = (x - x1) * (x2 - x1) + (y - y1) * (y2 - y1);
  if (dot < -1e-9) return false;

  return dot <= lengthSquared + 1e-9;
}

double? _number(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}
