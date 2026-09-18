import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../core/api/api_client.dart';
import '../../core/db/app_database.dart';
import 'master_models.dart';

class MasterDataRepository {
  MasterDataRepository({required this.api, required this.db});

  final ApiClient api;
  final AppDatabase db;

  Future<void> refreshAll() async {
    await Future.wait([
      _refreshTable('customers', 'customers'),
      _refreshTable('territories', 'territories'),
      _refreshTable('routes', 'routes'),
      _refreshTable('products', 'products'),
      _refreshPriceLists(),
    ]);
    await db.setting('master_data_last_refresh', DateTime.now().toUtc().toIso8601String());
  }

  Future<void> _refreshTable(String table, String endpoint) async {
    final data = await api.get(endpoint);
    final rows = (data as List).cast<dynamic>();
    final now = DateTime.now().toUtc().toIso8601String();

    await db.db.transaction((txn) async {
      await txn.delete(table);
      for (final raw in rows) {
        final item = Map<String, dynamic>.from(raw as Map);
        await txn.insert(
          table,
          {
            'id': int.parse('${item['id']}'),
            'uuid': item['uuid']?.toString(),
            'payload': jsonEncode(item),
            'cached_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> _refreshPriceLists() async {
    final data = await api.get('price-lists');
    final rows = (data as List).cast<dynamic>();
    final now = DateTime.now().toUtc().toIso8601String();

    await db.db.transaction((txn) async {
      await txn.delete('price_lists');
      await txn.delete('price_list_items');

      for (final raw in rows) {
        final item = Map<String, dynamic>.from(raw as Map);
        final id = int.parse('${item['id']}');
        await txn.insert(
          'price_lists',
          {
            'id': id,
            'uuid': item['uuid']?.toString(),
            'payload': jsonEncode(item),
            'cached_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        for (final rawItem in (item['items'] as List? ?? const [])) {
          final priceItem = Map<String, dynamic>.from(rawItem as Map);
          final product = priceItem['product'] is Map
              ? Map<String, dynamic>.from(priceItem['product'] as Map)
              : <String, dynamic>{};
          await txn.insert(
            'price_list_items',
            {
              'id': int.parse('${priceItem['id']}'),
              'uuid': product['uuid']?.toString(),
              'payload': jsonEncode({
                ...priceItem,
                'price_list_id': id,
                'product_uuid': product['uuid'],
              }),
              'cached_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    });
  }

  Future<List<CustomerRecord>> customers() async {
    final rows = await db.db.query('customers', orderBy: 'id ASC');
    return rows.map((row) => CustomerRecord.fromJson(decodePayload(row['payload']))).toList();
  }

  Future<CustomerRecord?> customer(String uuid) async {
    final rows = await db.db.query('customers', where: 'uuid=?', whereArgs: [uuid], limit: 1);
    return rows.isEmpty ? null : CustomerRecord.fromJson(decodePayload(rows.first['payload']));
  }

  Future<List<ProductRecord>> products() async {
    final rows = await db.db.query('products', orderBy: 'id ASC');
    return rows.map((row) => ProductRecord.fromJson(decodePayload(row['payload']))).toList();
  }

  Future<List<RouteRecord>> routes() async {
    final rows = await db.db.query('routes', orderBy: 'id ASC');
    return rows.map((row) => RouteRecord.fromJson(decodePayload(row['payload']))).toList();
  }

  Future<List<CustomerRecord>> routeCustomers(RouteRecord route) async {
    try {
      final data = await api.get('routes/${route.uuid}/customers');
      final rows = (data as List).cast<dynamic>();
      final now = DateTime.now().toUtc().toIso8601String();
      await db.setting('route_customers_${route.uuid}', {
        'cached_at': now,
        'items': rows,
      });
      return rows
          .map((raw) => CustomerRecord.fromJson(Map<String, dynamic>.from(raw as Map)))
          .toList();
    } catch (_) {
      final cached = await db.readSetting('route_customers_${route.uuid}');
      if (cached is Map && cached['items'] is List) {
        return (cached['items'] as List)
            .map((raw) => CustomerRecord.fromJson(Map<String, dynamic>.from(raw as Map)))
            .toList();
      }
      final all = await customers();
      return all.where((customer) => customer.routeId == route.id).toList();
    }
  }

  Future<double> priceFor(String productUuid, {int? priceListId, double quantity = 1}) async {
    if (priceListId != null) {
      final rows = await db.db.query('price_list_items');
      final matches = rows
          .map((row) => decodePayload(row['payload']))
          .where((item) =>
              int.tryParse('${item['price_list_id']}') == priceListId &&
              '${item['product_uuid']}' == productUuid &&
              (double.tryParse('${item['min_quantity'] ?? 1}') ?? 1) <= quantity)
          .toList()
        ..sort((a, b) => (double.tryParse('${b['min_quantity'] ?? 1}') ?? 1)
            .compareTo(double.tryParse('${a['min_quantity'] ?? 1}') ?? 1));
      if (matches.isNotEmpty) {
        return double.tryParse('${matches.first['price']}') ?? 0;
      }
    }

    final productRows = await db.db.query('products', where: 'uuid=?', whereArgs: [productUuid], limit: 1);
    if (productRows.isEmpty) return 0;
    return ProductRecord.fromJson(decodePayload(productRows.first['payload'])).basePrice;
  }
}
