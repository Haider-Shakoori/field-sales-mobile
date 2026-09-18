import 'dart:convert';

class CustomerRecord {
  const CustomerRecord({
    required this.id,
    required this.uuid,
    required this.code,
    required this.name,
    this.shopName,
    this.phone,
    this.address,
    this.latitude,
    this.longitude,
    required this.geofenceRadius,
    this.routeId,
    this.priceListId,
  });

  final int id;
  final String uuid;
  final String code;
  final String name;
  final String? shopName;
  final String? phone;
  final String? address;
  final double? latitude;
  final double? longitude;
  final int geofenceRadius;
  final int? routeId;
  final int? priceListId;

  String get displayName => (shopName?.trim().isNotEmpty ?? false) ? shopName! : name;

  factory CustomerRecord.fromJson(Map<String, dynamic> json) => CustomerRecord(
        id: int.parse('${json['id']}'),
        uuid: '${json['uuid']}',
        code: '${json['code'] ?? ''}',
        name: '${json['name'] ?? ''}',
        shopName: json['shop_name']?.toString(),
        phone: json['phone']?.toString(),
        address: json['address']?.toString(),
        latitude: _double(json['latitude']),
        longitude: _double(json['longitude']),
        geofenceRadius: int.tryParse('${json['geofence_radius'] ?? 100}') ?? 100,
        routeId: int.tryParse('${json['route_id'] ?? ''}'),
        priceListId: int.tryParse('${json['price_list_id'] ?? ''}'),
      );

  static double? _double(dynamic value) => value == null ? null : double.tryParse('$value');
}

class ProductRecord {
  const ProductRecord({
    required this.id,
    required this.uuid,
    required this.sku,
    required this.name,
    required this.unit,
    required this.basePrice,
    required this.currency,
  });

  final int id;
  final String uuid;
  final String sku;
  final String name;
  final String unit;
  final double basePrice;
  final String currency;

  factory ProductRecord.fromJson(Map<String, dynamic> json) => ProductRecord(
        id: int.parse('${json['id']}'),
        uuid: '${json['uuid']}',
        sku: '${json['sku'] ?? ''}',
        name: '${json['name'] ?? ''}',
        unit: '${json['unit'] ?? 'pcs'}',
        basePrice: double.tryParse('${json['base_price'] ?? 0}') ?? 0,
        currency: '${json['currency'] ?? 'AFN'}',
      );
}

class RouteRecord {
  const RouteRecord({required this.id, required this.uuid, required this.code, required this.name});

  final int id;
  final String uuid;
  final String code;
  final String name;

  factory RouteRecord.fromJson(Map<String, dynamic> json) => RouteRecord(
        id: int.parse('${json['id']}'),
        uuid: '${json['uuid']}',
        code: '${json['code'] ?? ''}',
        name: '${json['name'] ?? ''}',
      );
}

Map<String, dynamic> decodePayload(Object? value) =>
    Map<String, dynamic>.from(jsonDecode(value as String) as Map);
