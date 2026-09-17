import 'package:field_sales_mobile/core/models/master_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MAPPING — CustomerDto', () {
    test('parses a full CustomerResource envelope', () {
      final dto = CustomerDto.fromJson({
        'id': 1,
        'uuid': 'uuid-1',
        'offline_uuid': 'uuid-1',
        'code': 'C-001',
        'name': 'Alpha Shop',
        'business_name': 'Alpha Shop',
        'contact_person': 'Jane',
        'phone': '555-0100',
        'whatsapp': '555-0100',
        'email': 'alpha@example.com',
        'address': '1 Main St',
        'province': 'PR',
        'district': 'DT',
        'latitude': 15.1,
        'longitude': 120.2,
        'geofence_radius': 500,
        'photo_url': null,
        'branch_id': 2,
        'branch': {'id': 2, 'name': 'Branch B'},
        'category_id': 3,
        'category': {'id': 3, 'name': 'Retail'},
        'territory_id': 4,
        'territory': {'id': 4, 'name': 'Central'},
        'route_id': 10,
        'route': {'id': 10, 'name': 'Route A'},
        'assigned_salesman_id': 7,
        'assigned_salesman': {
          'id': 7,
          'name': 'Sam Sales',
          'employee_code': 'E7',
        },
        'credit_limit': 5000.0,
        'outstanding_balance': 250.5,
        'price_list_id': 1,
        'price_list': {
          'id': 1,
          'name': 'Default',
          'is_default': true,
          'is_active': true,
        },
        'visit_frequency': 'weekly',
        'is_active': true,
        'notes': 'VIP',
        'created_at': '2026-01-01T00:00:00+00:00',
        'updated_at': '2026-01-02T00:00:00+00:00',
      });

      expect(dto.id, 1);
      expect(dto.uuid, 'uuid-1');
      expect(dto.offlineUuid, 'uuid-1');
      expect(dto.code, 'C-001');
      expect(dto.name, 'Alpha Shop');
      expect(dto.phone, '555-0100');
      expect(dto.address, '1 Main St');
      expect(dto.latitude, 15.1);
      expect(dto.longitude, 120.2);
      expect(dto.branchId, 2);
      expect(dto.branchName, 'Branch B');
      expect(dto.territoryName, 'Central');
      expect(dto.routeId, 10);
      expect(dto.routeName, 'Route A');
      expect(dto.assignedSalesmanId, 7);
      expect(dto.assignedSalesmanName, 'Sam Sales');
      expect(dto.creditLimit, 5000.0);
      expect(dto.outstandingBalance, 250.5);
      expect(dto.priceListId, 1);
      expect(dto.priceListName, 'Default');
      expect(dto.isActive, isTrue);
    });

    test('falls back to business_name when name is absent', () {
      final dto = CustomerDto.fromJson({
        'id': 2,
        'uuid': 'u2',
        'business_name': 'Beta Store',
        'is_active': true,
      });
      expect(dto.name, 'Beta Store');
    });
  });

  group('MAPPING — RouteController::customers rows', () {
    test('parses the flat custom row shape (route customer)', () {
      final dto = RouteCustomerDto.fromJson({
        'id': 9,
        'uuid': 'u9',
        'code': 'C-009',
        'name': 'Gamma Depot',
        'business_name': 'Gamma Depot',
        'contact_person': 'Bob',
        'phone': '555-0009',
        'address': '9 Side St',
        'latitude': 10.0,
        'longitude': 11.0,
        'is_active': true,
        'visit_order': 3,
        'effective_from': '2026-01-01',
        'effective_to': null,
        'route_customer_id': 900,
      }, routeId: 10);

      expect(dto.customerId, 9);
      expect(dto.routeId, 10);
      expect(dto.name, 'Gamma Depot');
      expect(dto.visitOrder, 3);
      expect(dto.routeCustomerId, 900);
      expect(dto.isActive, isTrue);
    });
  });

  group('MAPPING — Territory/Route', () {
    test('TerritoryDto parses nested branch', () {
      final dto = TerritoryDto.fromJson({
        'id': 4,
        'uuid': 't4',
        'code': 'T-4',
        'name': 'Central',
        'description': 'hub',
        'branch_id': 2,
        'branch': {'id': 2, 'name': 'Branch B'},
        'latitude': 14.0,
        'longitude': 121.0,
        'is_active': true,
        'routes_count': 5,
        'customers_count': 40,
      });
      expect(dto.name, 'Central');
      expect(dto.branchName, 'Branch B');
      expect(dto.latitude, 14.0);
      expect(dto.routesCount, 5);
    });

    test('RouteDto parses nested territory and salesman', () {
      final dto = RouteDto.fromJson({
        'id': 10,
        'uuid': 'r10',
        'code': 'R-10',
        'name': 'Route A',
        'territory_id': 4,
        'territory': {'id': 4, 'name': 'Central'},
        'weekday': 2,
        'is_active': true,
        'customer_count': 15,
        'salesman_id': 7,
        'salesman': {'id': 7, 'name': 'Sam Sales', 'employee_code': 'E7'},
      });
      expect(dto.name, 'Route A');
      expect(dto.territoryId, 4);
      expect(dto.territoryName, 'Central');
      expect(dto.weekday, 2);
      expect(dto.salesmanId, 7);
      expect(dto.salesmanName, 'Sam Sales');
    });
  });

  group('MAPPING — Product/PriceList', () {
    test('ProductDto parses base row and embedded price lists', () {
      final dto = ProductDto.fromJson({
        'id': 11,
        'uuid': 'p11',
        'sku': 'SKU-11',
        'name': 'Tea',
        'category': 'Grocery',
        'unit': 'pack',
        'price': 4.5,
        'is_active': true,
        'price_lists': [
          {'id': 1, 'name': 'Default', 'price': 4.0},
          {'id': 2, 'name': 'Promo', 'price': 3.5},
        ],
        'updated_at': '2026-01-02T00:00:00+00:00',
      });

      expect(dto.id, 11);
      expect(dto.sku, 'SKU-11');
      expect(dto.name, 'Tea');
      expect(dto.price, 4.5);
      expect(dto.priceLists, hasLength(2));
      expect(dto.priceLists.first.priceListId, 1);
      expect(dto.priceLists.first.price, 4.0);
    });

    test('PriceListDto parses default flag', () {
      final dto = PriceListDto.fromJson({
        'id': 1,
        'uuid': 'pl1',
        'name': 'Default',
        'is_default': true,
        'is_active': true,
        'items_count': 12,
      });
      expect(dto.isDefault, isTrue);
      expect(dto.itemsCount, 12);
    });

    test('numerics coerce from both int and double JSON', () {
      final asInt = CustomerDto.fromJson({
        'id': 1,
        'credit_limit': 100,
        'is_active': 1,
      });
      expect(asInt.creditLimit, 100.0);
      expect(asInt.isActive, isTrue);

      final asDouble = CustomerDto.fromJson({
        'id': 2,
        'credit_limit': 99.9,
        'is_active': 0,
      });
      expect(asDouble.creditLimit, 99.9);
      expect(asDouble.isActive, isFalse);
    });
  });
}
