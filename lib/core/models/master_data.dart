/// Mirrors the Laravel `CustomerResource` envelope.
class CustomerDto {
  const CustomerDto({
    required this.id,
    this.uuid,
    this.offlineUuid,
    this.code,
    this.name,
    this.businessName,
    this.contactPerson,
    this.phone,
    this.whatsapp,
    this.email,
    this.address,
    this.province,
    this.district,
    this.latitude,
    this.longitude,
    this.geofenceRadius,
    this.photoUrl,
    this.branchId,
    this.branchName,
    this.categoryId,
    this.categoryName,
    this.territoryId,
    this.territoryName,
    this.routeId,
    this.routeName,
    this.assignedSalesmanId,
    this.assignedSalesmanName,
    this.creditLimit,
    this.outstandingBalance,
    this.priceListId,
    this.priceListName,
    this.visitFrequency,
    this.isActive,
    this.notes,
    this.updatedAt,
  });

  final int id;
  final String? uuid;
  final String? offlineUuid;
  final String? code;
  final String? name;
  final String? businessName;
  final String? contactPerson;
  final String? phone;
  final String? whatsapp;
  final String? email;
  final String? address;
  final String? province;
  final String? district;
  final double? latitude;
  final double? longitude;
  final double? geofenceRadius;
  final String? photoUrl;
  final int? branchId;
  final String? branchName;
  final int? categoryId;
  final String? categoryName;
  final int? territoryId;
  final String? territoryName;
  final int? routeId;
  final String? routeName;
  final int? assignedSalesmanId;
  final String? assignedSalesmanName;
  final double? creditLimit;
  final double? outstandingBalance;
  final int? priceListId;
  final String? priceListName;
  final String? visitFrequency;
  final bool? isActive;
  final String? notes;
  final String? updatedAt;

  factory CustomerDto.fromJson(Map<String, dynamic> json) {
    final branch = json['branch'];
    final category = json['category'];
    final territory = json['territory'];
    final route = json['route'];
    final salesman = json['assigned_salesman'];
    final priceList = json['price_list'];

    return CustomerDto(
      id: (json['id'] as num).toInt(),
      uuid: json['uuid']?.toString(),
      offlineUuid: json['offline_uuid']?.toString(),
      code: json['code']?.toString(),
      name: json['name']?.toString() ?? json['business_name']?.toString(),
      businessName: json['business_name']?.toString(),
      contactPerson: json['contact_person']?.toString(),
      phone: json['phone']?.toString(),
      whatsapp: json['whatsapp']?.toString(),
      email: json['email']?.toString(),
      address: json['address']?.toString(),
      province: json['province']?.toString(),
      district: json['district']?.toString(),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      geofenceRadius: (json['geofence_radius'] as num?)?.toDouble(),
      photoUrl: json['photo_url']?.toString(),
      branchId: (json['branch_id'] as num?)?.toInt(),
      branchName: branch is Map<String, dynamic>
          ? branch['name']?.toString()
          : null,
      categoryId: (json['category_id'] as num?)?.toInt(),
      categoryName: category is Map<String, dynamic>
          ? category['name']?.toString()
          : null,
      territoryId: (json['territory_id'] as num?)?.toInt(),
      territoryName: territory is Map<String, dynamic>
          ? territory['name']?.toString()
          : null,
      routeId: (json['route_id'] as num?)?.toInt(),
      routeName: route is Map<String, dynamic>
          ? route['name']?.toString()
          : null,
      assignedSalesmanId: (json['assigned_salesman_id'] as num?)?.toInt(),
      assignedSalesmanName: salesman is Map<String, dynamic>
          ? salesman['name']?.toString()
          : null,
      creditLimit: (json['credit_limit'] as num?)?.toDouble() ?? 0,
      outstandingBalance:
          (json['outstanding_balance'] as num?)?.toDouble() ?? 0,
      priceListId: (json['price_list_id'] as num?)?.toInt(),
      priceListName: priceList is Map<String, dynamic>
          ? priceList['name']?.toString()
          : null,
      visitFrequency: json['visit_frequency']?.toString(),
      isActive: json['is_active'] == null
          ? null
          : json['is_active'] == true || json['is_active'] == 1,
      notes: json['notes']?.toString(),
      updatedAt: json['updated_at']?.toString(),
    );
  }
}

/// Mirrors the Laravel `TerritoryResource` envelope.
class TerritoryDto {
  const TerritoryDto({
    required this.id,
    this.uuid,
    this.code,
    this.name,
    this.description,
    this.branchId,
    this.branchName,
    this.latitude,
    this.longitude,
    this.radiusKm,
    this.isActive,
    this.routesCount,
    this.customersCount,
    this.updatedAt,
  });

  final int id;
  final String? uuid;
  final String? code;
  final String? name;
  final String? description;
  final int? branchId;
  final String? branchName;
  final double? latitude;
  final double? longitude;
  final double? radiusKm;
  final bool? isActive;
  final int? routesCount;
  final int? customersCount;
  final String? updatedAt;

  factory TerritoryDto.fromJson(Map<String, dynamic> json) {
    final branch = json['branch'];
    return TerritoryDto(
      id: (json['id'] as num).toInt(),
      uuid: json['uuid']?.toString(),
      code: json['code']?.toString(),
      name: json['name']?.toString(),
      description: json['description']?.toString(),
      branchId: (json['branch_id'] as num?)?.toInt(),
      branchName: branch is Map<String, dynamic>
          ? branch['name']?.toString()
          : null,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      radiusKm: (json['radius_km'] as num?)?.toDouble(),
      isActive: json['is_active'] == null
          ? null
          : json['is_active'] == true || json['is_active'] == 1,
      routesCount: (json['routes_count'] as num?)?.toInt(),
      customersCount: (json['customers_count'] as num?)?.toInt(),
      updatedAt: json['updated_at']?.toString(),
    );
  }
}

/// Mirrors the Laravel `RouteResource` envelope (base route row).
class RouteDto {
  const RouteDto({
    required this.id,
    this.uuid,
    this.code,
    this.name,
    this.description,
    this.territoryId,
    this.territoryName,
    this.branchId,
    this.branchName,
    this.weekday,
    this.weekdayName,
    this.isActive,
    this.customerCount,
    this.salesmanId,
    this.salesmanName,
    this.updatedAt,
  });

  final int id;
  final String? uuid;
  final String? code;
  final String? name;
  final String? description;
  final int? territoryId;
  final String? territoryName;
  final int? branchId;
  final String? branchName;
  final int? weekday;
  final String? weekdayName;
  final bool? isActive;
  final int? customerCount;
  final int? salesmanId;
  final String? salesmanName;
  final String? updatedAt;

  factory RouteDto.fromJson(Map<String, dynamic> json) {
    final territory = json['territory'];
    final salesman = json['salesman'];
    return RouteDto(
      id: (json['id'] as num).toInt(),
      uuid: json['uuid']?.toString(),
      code: json['code']?.toString(),
      name: json['name']?.toString(),
      description: json['description']?.toString(),
      territoryId: (json['territory_id'] as num?)?.toInt(),
      territoryName: territory is Map<String, dynamic>
          ? territory['name']?.toString()
          : null,
      branchId: (json['branch_id'] as num?)?.toInt(),
      branchName: json['branch']?.toString(),
      weekday: (json['weekday'] as num?)?.toInt(),
      weekdayName: json['weekday_name']?.toString(),
      isActive: json['is_active'] == null
          ? null
          : json['is_active'] == true || json['is_active'] == 1,
      customerCount: (json['customer_count'] as num?)?.toInt(),
      salesmanId: (json['salesman_id'] as num?)?.toInt(),
      salesmanName: salesman is Map<String, dynamic>
          ? salesman['name']?.toString()
          : null,
      updatedAt: json['updated_at']?.toString(),
    );
  }
}

/// A customer assigned to a route, as returned by
/// `GET /routes/{route}/customers`.
class RouteCustomerDto {
  const RouteCustomerDto({
    required this.customerId,
    required this.routeId,
    this.uuid,
    this.code,
    this.name,
    this.businessName,
    this.contactPerson,
    this.phone,
    this.address,
    this.latitude,
    this.longitude,
    this.isActive,
    this.visitOrder,
    this.routeCustomerId,
  });

  final int customerId;
  final int routeId;
  final String? uuid;
  final String? code;
  final String? name;
  final String? businessName;
  final String? contactPerson;
  final String? phone;
  final String? address;
  final double? latitude;
  final double? longitude;
  final bool? isActive;
  final int? visitOrder;
  final int? routeCustomerId;

  factory RouteCustomerDto.fromJson(
    Map<String, dynamic> json, {
    required int routeId,
  }) => RouteCustomerDto(
    customerId: (json['id'] as num).toInt(),
    routeId: routeId,
    uuid: json['uuid']?.toString(),
    code: json['code']?.toString(),
    name: json['name']?.toString() ?? json['business_name']?.toString(),
    businessName: json['business_name']?.toString(),
    contactPerson: json['contact_person']?.toString(),
    phone: json['phone']?.toString(),
    address: json['address']?.toString(),
    latitude: (json['latitude'] as num?)?.toDouble(),
    longitude: (json['longitude'] as num?)?.toDouble(),
    isActive: json['is_active'] == null
        ? null
        : json['is_active'] == true || json['is_active'] == 1,
    visitOrder: (json['visit_order'] as num?)?.toInt(),
    routeCustomerId: (json['route_customer_id'] as num?)?.toInt(),
  );
}

/// Mirrors the Laravel `ProductResource` envelope (base row; price-list
/// overrides ride along when the API includes `price_lists`).
class ProductDto {
  const ProductDto({
    required this.id,
    this.uuid,
    this.sku,
    this.name,
    this.category,
    this.unit,
    this.price,
    this.isActive,
    this.priceLists = const [],
    this.updatedAt,
  });

  final int id;
  final String? uuid;
  final String? sku;
  final String? name;
  final String? category;
  final String? unit;
  final double? price;
  final bool? isActive;
  final List<ProductPriceListDto> priceLists;
  final String? updatedAt;

  factory ProductDto.fromJson(Map<String, dynamic> json) => ProductDto(
    id: (json['id'] as num).toInt(),
    uuid: json['uuid']?.toString(),
    sku: json['sku']?.toString(),
    name: json['name']?.toString(),
    category: json['category']?.toString(),
    unit: json['unit']?.toString(),
    price: (json['price'] as num?)?.toDouble(),
    isActive: json['is_active'] == null
        ? null
        : json['is_active'] == true || json['is_active'] == 1,
    priceLists: (json['price_lists'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ProductPriceListDto.fromJson)
        .toList(),
    updatedAt: json['updated_at']?.toString(),
  );
}

/// A single price list entry embedded in a product (`price_lists` field).
class ProductPriceListDto {
  const ProductPriceListDto({required this.priceListId, this.name, this.price});

  final int priceListId;
  final String? name;
  final double? price;

  factory ProductPriceListDto.fromJson(Map<String, dynamic> json) =>
      ProductPriceListDto(
        priceListId: (json['id'] as num).toInt(),
        name: json['name']?.toString(),
        price: (json['price'] as num?)?.toDouble(),
      );
}

/// Mirrors the Laravel `PriceListResource` envelope.
class PriceListDto {
  const PriceListDto({
    required this.id,
    this.uuid,
    this.name,
    this.isDefault,
    this.isActive,
    this.itemsCount,
    this.updatedAt,
  });

  final int id;
  final String? uuid;
  final String? name;
  final bool? isDefault;
  final bool? isActive;
  final int? itemsCount;
  final String? updatedAt;

  factory PriceListDto.fromJson(Map<String, dynamic> json) => PriceListDto(
    id: (json['id'] as num).toInt(),
    uuid: json['uuid']?.toString(),
    name: json['name']?.toString(),
    isDefault: json['is_default'] == null
        ? null
        : json['is_default'] == true || json['is_default'] == 1,
    isActive: json['is_active'] == null
        ? null
        : json['is_active'] == true || json['is_active'] == 1,
    itemsCount: (json['items_count'] as num?)?.toInt(),
    updatedAt: json['updated_at']?.toString(),
  );
}
