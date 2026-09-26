import 'package:latlong2/latlong.dart';

Map<String, dynamic>? detectTerritoryForPoint(
  List<Map<String, dynamic>> territories,
  LatLng point,
) {
  for (final territory in territories) {
    if (territoryContainsPoint(territory['polygon'], point)) {
      return territory;
    }
  }

  return null;
}

bool territoryContainsPoint(dynamic geometry, LatLng point) {
  final normalized = _normalizeGeometry(geometry);
  if (normalized == null) return false;

  final type = normalized['type']?.toString();
  final coordinates = normalized['coordinates'];

  if (type == 'Polygon' && coordinates is List) {
    return _polygonContains(coordinates, point);
  }

  if (type == 'MultiPolygon' && coordinates is List) {
    for (final polygon in coordinates) {
      if (polygon is List && _polygonContains(polygon, point)) {
        return true;
      }
    }
  }

  return false;
}

Map<String, dynamic>? _normalizeGeometry(dynamic geometry) {
  if (geometry is Map) {
    final map = Map<String, dynamic>.from(geometry);
    if (map['type'] != null && map['coordinates'] is List) {
      return map;
    }
  }

  if (geometry is List && geometry.length >= 3) {
    final ring = <List<double>>[];

    for (final raw in geometry) {
      if (raw is! List || raw.length < 2) continue;
      final latitude = _number(raw[0]);
      final longitude = _number(raw[1]);
      if (latitude == null || longitude == null) continue;
      ring.add([longitude, latitude]);
    }

    if (ring.length >= 3) {
      final first = ring.first;
      final last = ring.last;
      if (first[0] != last[0] || first[1] != last[1]) {
        ring.add([...first]);
      }

      return {
        'type': 'Polygon',
        'coordinates': [ring],
      };
    }
  }

  return null;
}

bool _polygonContains(List<dynamic> rings, LatLng point) {
  if (rings.isEmpty || rings.first is! List) return false;

  if (!_ringContains(List<dynamic>.from(rings.first as List), point)) {
    return false;
  }

  for (final hole in rings.skip(1)) {
    if (hole is List &&
        _ringContains(List<dynamic>.from(hole), point)) {
      return false;
    }
  }

  return true;
}

bool _ringContains(List<dynamic> ring, LatLng point) {
  final points = <LatLng>[];

  for (final raw in ring) {
    if (raw is! List || raw.length < 2) continue;
    final longitude = _number(raw[0]);
    final latitude = _number(raw[1]);
    if (latitude == null || longitude == null) continue;
    points.add(LatLng(latitude, longitude));
  }

  if (points.length < 3) return false;

  var inside = false;

  for (var i = 0, j = points.length - 1; i < points.length; j = i++) {
    final a = points[i];
    final b = points[j];

    if (_pointOnSegment(point, a, b)) return true;

    final crosses =
        ((a.latitude > point.latitude) != (b.latitude > point.latitude)) &&
        (point.longitude <
            (b.longitude - a.longitude) *
                    (point.latitude - a.latitude) /
                    ((b.latitude - a.latitude).abs() < 1e-12
                        ? 1e-12
                        : b.latitude - a.latitude) +
                a.longitude);

    if (crosses) inside = !inside;
  }

  return inside;
}

bool _pointOnSegment(LatLng point, LatLng a, LatLng b) {
  final cross =
      (point.longitude - a.longitude) * (b.latitude - a.latitude) -
      (point.latitude - a.latitude) * (b.longitude - a.longitude);

  if (cross.abs() > 1e-9) return false;

  final lengthSquared =
      (b.longitude - a.longitude) * (b.longitude - a.longitude) +
      (b.latitude - a.latitude) * (b.latitude - a.latitude);

  if (lengthSquared <= 1e-18) {
    final dx = point.longitude - a.longitude;
    final dy = point.latitude - a.latitude;
    return dx * dx + dy * dy <= 1e-18;
  }

  final dot =
      (point.longitude - a.longitude) * (b.longitude - a.longitude) +
      (point.latitude - a.latitude) * (b.latitude - a.latitude);

  if (dot < -1e-9) return false;

  return dot <= lengthSquared + 1e-9;
}

double? _number(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}
