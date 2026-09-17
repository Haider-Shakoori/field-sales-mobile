import 'package:sqflite/sqflite.dart';

import '../api/api_client.dart';
import '../models/master_data.dart';
import '../storage/app_database.dart';

/// Offline-first cache for the four master-data domains (customers, routes,
/// products, price lists).
///
/// [refresh*] pulls EVERY page of the paginated API (defaulting to the server
/// cap `per_page=100`) then upserts into SQLite inside a transaction. Cache is
/// never cleared on failure: if a page request throws, previously stored rows
/// remain readable so the device stays usable offline. Screens read through
/// the `local*` getters, which never touch the network.
class MasterDataRepository {
  MasterDataRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  static const _pageSize = 100;

  /// Pulls all domains. Route membership follows the route list, so routes
  /// must be refreshed before [refreshRouteCustomers].
  Future<void> refreshAll({bool includeRouteCustomers = true}) async {
    await Future.wait([
      refreshCustomers(),
      refreshTerritories(),
      refreshRoutes(),
      refreshProducts(),
      refreshPriceLists(),
    ]);
    if (includeRouteCustomers) {
      await refreshRouteCustomers();
    }
  }

  Future<void> refreshCustomers() =>
      _paginateInto('customers', (data, txn, now) async {
        for (final item in data) {
          final dto = CustomerDto.fromJson(item);
          await txn.insert('customers', {
            'id': dto.id,
            'uuid': dto.uuid,
            'offline_uuid': dto.offlineUuid,
            'code': dto.code,
            'name': dto.name,
            'business_name': dto.businessName,
            'contact_person': dto.contactPerson,
            'phone': dto.phone,
            'whatsapp': dto.whatsapp,
            'email': dto.email,
            'address': dto.address,
            'province': dto.province,
            'district': dto.district,
            'latitude': dto.latitude,
            'longitude': dto.longitude,
            'geofence_radius': dto.geofenceRadius,
            'photo_url': dto.photoUrl,
            'branch_id': dto.branchId,
            'branch_name': dto.branchName,
            'category_id': dto.categoryId,
            'category_name': dto.categoryName,
            'territory_id': dto.territoryId,
            'territory_name': dto.territoryName,
            'route_id': dto.routeId,
            'route_name': dto.routeName,
            'assigned_salesman_id': dto.assignedSalesmanId,
            'assigned_salesman_name': dto.assignedSalesmanName,
            'credit_limit': dto.creditLimit,
            'outstanding_balance': dto.outstandingBalance,
            'price_list_id': dto.priceListId,
            'price_list_name': dto.priceListName,
            'visit_frequency': dto.visitFrequency,
            'is_active': dto.isActive == null ? null : (dto.isActive! ? 1 : 0),
            'notes': dto.notes,
            'updated_at': dto.updatedAt,
            'cached_at': now,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });

  Future<void> refreshTerritories() =>
      _paginateInto('territories', (data, txn, now) async {
        for (final item in data) {
          final dto = TerritoryDto.fromJson(item);
          await txn.insert('territories', {
            'id': dto.id,
            'uuid': dto.uuid,
            'code': dto.code,
            'name': dto.name,
            'description': dto.description,
            'branch_id': dto.branchId,
            'branch_name': dto.branchName,
            'latitude': dto.latitude,
            'longitude': dto.longitude,
            'radius_km': dto.radiusKm,
            'is_active': dto.isActive == null ? null : (dto.isActive! ? 1 : 0),
            'routes_count': dto.routesCount,
            'customers_count': dto.customersCount,
            'updated_at': dto.updatedAt,
            'cached_at': now,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });

  Future<void> refreshRoutes() =>
      _paginateInto('routes', (data, txn, now) async {
        for (final item in data) {
          final dto = RouteDto.fromJson(item);
          await txn.insert('routes', {
            'id': dto.id,
            'uuid': dto.uuid,
            'code': dto.code,
            'name': dto.name,
            'description': dto.description,
            'territory_id': dto.territoryId,
            'territory_name': dto.territoryName,
            'branch_id': dto.branchId,
            'branch_name': dto.branchName,
            'weekday': dto.weekday,
            'weekday_name': dto.weekdayName,
            'is_active': dto.isActive == null ? null : (dto.isActive! ? 1 : 0),
            'customer_count': dto.customerCount,
            'salesman_id': dto.salesmanId,
            'salesman_name': dto.salesmanName,
            'updated_at': dto.updatedAt,
            'cached_at': now,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });

  Future<void> refreshProducts() =>
      _paginateInto('products', (data, txn, now) async {
        for (final item in data) {
          final dto = ProductDto.fromJson(item);
          await txn.insert('products', {
            'id': dto.id,
            'uuid': dto.uuid,
            'sku': dto.sku,
            'name': dto.name,
            'category': dto.category,
            'unit': dto.unit,
            'price': dto.price,
            'is_active': dto.isActive == null ? null : (dto.isActive! ? 1 : 0),
            'updated_at': dto.updatedAt,
            'cached_at': now,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
          if (dto.priceLists.isNotEmpty) {
            for (final pl in dto.priceLists) {
              await txn.insert('price_list_items', {
                'price_list_id': pl.priceListId,
                'product_id': dto.id,
                'price': pl.price,
                'cached_at': now,
              }, conflictAlgorithm: ConflictAlgorithm.replace);
            }
          }
        }
      });

  Future<void> refreshPriceLists() => _paginateInto('price-lists', (
    data,
    txn,
    now,
  ) async {
    for (final item in data) {
      final dto = PriceListDto.fromJson(item);
      await txn.insert('price_lists', {
        'id': dto.id,
        'uuid': dto.uuid,
        'name': dto.name,
        'is_default': dto.isDefault == null ? null : (dto.isDefault! ? 1 : 0),
        'is_active': dto.isActive == null ? null : (dto.isActive! ? 1 : 0),
        'items_count': dto.itemsCount,
        'updated_at': dto.updatedAt,
        'cached_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  });

  /// Replaces route membership for every locally cached route by reading each
  /// route's `GET /routes/{route}/customers` list across all pages.
  Future<void> refreshRouteCustomers({List<int>? routeIds}) async {
    final db = await AppDatabase.instance;
    final ids =
        routeIds ??
        (await db.query(
          'routes',
          columns: ['id'],
        )).map((r) => (r['id'] as num).toInt()).toList();

    for (final routeId in ids) {
      var page = 1;
      final rows = <Map<String, dynamic>>[];
      while (true) {
        final envelope = await _apiClient.requestEnvelope(
          method: 'GET',
          path: 'routes/$routeId/customers',
          query: {'per_page': _pageSize, 'page': page},
        );
        final data = envelope.data;
        if (data is List) {
          rows.addAll(data.whereType<Map<String, dynamic>>());
        }
        if (page >= envelope.lastPage) {
          break;
        }
        page++;
      }

      await db.transaction((txn) async {
        await txn.delete(
          'route_customers',
          where: 'route_id = ?',
          whereArgs: [routeId],
        );
        final now = DateTime.now().toIso8601String();
        for (final item in rows) {
          final dto = RouteCustomerDto.fromJson(item, routeId: routeId);
          await txn.insert('route_customers', {
            'route_id': routeId,
            'customer_id': dto.customerId,
            'customer_name': dto.name,
            'customer_code': dto.code,
            'visit_order': dto.visitOrder,
            'route_customer_id': dto.routeCustomerId,
            'is_active': dto.isActive == null ? 1 : (dto.isActive! ? 1 : 0),
            'cached_at': now,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });
    }
  }

  /// Reads a single paginated collection and upserts every page inside one
  /// transaction. Throws (leaving existing cache intact) if any page fails.
  Future<void> _paginateInto(
    String path,
    Future<void> Function(
      List<Map<String, dynamic>> data,
      Transaction txn,
      String now,
    )
    upsert,
  ) async {
    final db = await AppDatabase.instance;
    final now = DateTime.now().toIso8601String();

    var page = 1;
    final all = <Map<String, dynamic>>[];
    while (true) {
      final envelope = await _apiClient.requestEnvelope(
        method: 'GET',
        path: path,
        query: {'per_page': _pageSize, 'page': page},
      );
      final data = envelope.data;
      if (data is List) {
        all.addAll(data.whereType<Map<String, dynamic>>());
      }
      if (page >= envelope.lastPage) {
        break;
      }
      page++;
    }

    await db.transaction((txn) => upsert(all, txn, now));
  }

  /// Local reads — never touch the network.

  Future<List<CustomerDto>> localCustomers({
    int? routeId,
    int? territoryId,
    String? search,
  }) async {
    final db = await AppDatabase.instance;
    final where = <String>[];
    final args = <Object?>[];
    if (routeId != null) {
      where.add('route_id = ?');
      args.add(routeId);
    }
    if (territoryId != null) {
      where.add('territory_id = ?');
      args.add(territoryId);
    }
    if (search != null && search.isNotEmpty) {
      where.add('(name LIKE ? OR code LIKE ? OR business_name LIKE ?)');
      final term = '%$search%';
      args.addAll([term, term, term]);
    }
    final rows = await db.query(
      'customers',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: where.isEmpty ? null : args,
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map((r) => _customerFromRow(r)).toList();
  }

  Future<List<TerritoryDto>> localTerritories() async {
    final db = await AppDatabase.instance;
    final rows = await db.query('territories', orderBy: 'name COLLATE NOCASE');
    return rows
        .map(
          (r) => TerritoryDto(
            id: (r['id'] as num).toInt(),
            uuid: r['uuid']?.toString(),
            code: r['code']?.toString(),
            name: r['name']?.toString(),
            branchId: (r['branch_id'] as num?)?.toInt(),
            branchName: r['branch_name']?.toString(),
          ),
        )
        .toList();
  }

  Future<List<RouteDto>> localRoutes({int? territoryId}) async {
    final db = await AppDatabase.instance;
    final where = territoryId == null ? null : 'territory_id = ?';
    final args = territoryId == null ? null : [territoryId];
    final rows = await db.query(
      'routes',
      where: where,
      whereArgs: args,
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(_routeFromRow).toList();
  }

  Future<List<RouteCustomerDto>> localRouteCustomers(int routeId) async {
    final db = await AppDatabase.instance;
    final rows = await db.query(
      'route_customers',
      where: 'route_id = ?',
      whereArgs: [routeId],
      orderBy: 'visit_order ASC, customer_name COLLATE NOCASE',
    );
    return rows
        .map(
          (r) => RouteCustomerDto(
            customerId: (r['customer_id'] as num).toInt(),
            routeId: routeId,
            name: r['customer_name']?.toString(),
            code: r['customer_code']?.toString(),
            visitOrder: (r['visit_order'] as num?)?.toInt(),
          ),
        )
        .toList();
  }

  Future<List<ProductDto>> localProducts({String? search}) async {
    final db = await AppDatabase.instance;
    final where = (search != null && search.isNotEmpty)
        ? '(name LIKE ? OR sku LIKE ?)'
        : null;
    final args = (search != null && search.isNotEmpty)
        ? ['%$search%', '%$search%']
        : null;
    final rows = await db.query(
      'products',
      where: where,
      whereArgs: args,
      orderBy: 'name COLLATE NOCASE',
    );
    return rows
        .map(
          (r) => ProductDto(
            id: (r['id'] as num).toInt(),
            uuid: r['uuid']?.toString(),
            sku: r['sku']?.toString(),
            name: r['name']?.toString(),
            category: r['category']?.toString(),
            unit: r['unit']?.toString(),
            price: (r['price'] as num?)?.toDouble(),
            isActive: r['is_active'] == null ? null : r['is_active'] == 1,
          ),
        )
        .toList();
  }

  Future<List<PriceListDto>> localPriceLists() async {
    final db = await AppDatabase.instance;
    final rows = await db.query('price_lists', orderBy: 'name COLLATE NOCASE');
    return rows
        .map(
          (r) => PriceListDto(
            id: (r['id'] as num).toInt(),
            uuid: r['uuid']?.toString(),
            name: r['name']?.toString(),
            isDefault: r['is_default'] == null ? null : r['is_default'] == 1,
            isActive: r['is_active'] == null ? null : r['is_active'] == 1,
            itemsCount: (r['items_count'] as num?)?.toInt(),
          ),
        )
        .toList();
  }

  Future<Map<String, int>> localCounts() async {
    final db = await AppDatabase.instance;
    Future<int> count(String table) async {
      final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
      return (rows.first['c'] as num?)?.toInt() ?? 0;
    }

    return {
      'customers': await count('customers'),
      'routes': await count('routes'),
      'products': await count('products'),
      'price_lists': await count('price_lists'),
    };
  }

  CustomerDto _customerFromRow(Map<String, Object?> r) => CustomerDto(
    id: (r['id'] as num).toInt(),
    uuid: r['uuid']?.toString(),
    offlineUuid: r['offline_uuid']?.toString(),
    code: r['code']?.toString(),
    name: r['name']?.toString(),
    businessName: r['business_name']?.toString(),
    contactPerson: r['contact_person']?.toString(),
    phone: r['phone']?.toString(),
    whatsapp: r['whatsapp']?.toString(),
    email: r['email']?.toString(),
    address: r['address']?.toString(),
    province: r['province']?.toString(),
    district: r['district']?.toString(),
    latitude: (r['latitude'] as num?)?.toDouble(),
    longitude: (r['longitude'] as num?)?.toDouble(),
    branchId: (r['branch_id'] as num?)?.toInt(),
    branchName: r['branch_name']?.toString(),
    categoryId: (r['category_id'] as num?)?.toInt(),
    categoryName: r['category_name']?.toString(),
    territoryId: (r['territory_id'] as num?)?.toInt(),
    territoryName: r['territory_name']?.toString(),
    routeId: (r['route_id'] as num?)?.toInt(),
    routeName: r['route_name']?.toString(),
    assignedSalesmanId: (r['assigned_salesman_id'] as num?)?.toInt(),
    assignedSalesmanName: r['assigned_salesman_name']?.toString(),
    creditLimit: (r['credit_limit'] as num?)?.toDouble(),
    outstandingBalance: (r['outstanding_balance'] as num?)?.toDouble(),
    priceListId: (r['price_list_id'] as num?)?.toInt(),
    priceListName: r['price_list_name']?.toString(),
    visitFrequency: r['visit_frequency']?.toString(),
    isActive: r['is_active'] == null ? null : r['is_active'] == 1,
    notes: r['notes']?.toString(),
    updatedAt: r['updated_at']?.toString(),
  );

  RouteDto _routeFromRow(Map<String, Object?> r) => RouteDto(
    id: (r['id'] as num).toInt(),
    uuid: r['uuid']?.toString(),
    code: r['code']?.toString(),
    name: r['name']?.toString(),
    description: r['description']?.toString(),
    territoryId: (r['territory_id'] as num?)?.toInt(),
    territoryName: r['territory_name']?.toString(),
    branchId: (r['branch_id'] as num?)?.toInt(),
    branchName: r['branch_name']?.toString(),
    weekday: (r['weekday'] as num?)?.toInt(),
    weekdayName: r['weekday_name']?.toString(),
    isActive: r['is_active'] == null ? null : r['is_active'] == 1,
    customerCount: (r['customer_count'] as num?)?.toInt(),
    salesmanId: (r['salesman_id'] as num?)?.toInt(),
    salesmanName: r['salesman_name']?.toString(),
    updatedAt: r['updated_at']?.toString(),
  );
}
