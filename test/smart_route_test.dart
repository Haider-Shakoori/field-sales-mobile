import 'dart:io';

import 'package:field_sales_mobile/core/api/api_client.dart';
import 'package:field_sales_mobile/core/db/app_database.dart';
import 'package:field_sales_mobile/core/storage/secret_store.dart';
import 'package:field_sales_mobile/features/routes/daily_route_plan_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<String> _databasePath() async =>
    p.join(await getDatabasesPath(), 'field_sales.db');

class _SmartRouteApi extends ApiClient {
  _SmartRouteApi() : super(SecretStore());

  Map<String, dynamic>? lastQuery;

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    expect(path, 'route-plan/today');
    lastQuery = query;

    return {
      'date': '2026-09-24',
      'source': {'type': 'route', 'id': 'route-1', 'name': 'Kabul Route'},
      'start_location': {
        'latitude': query?['latitude'],
        'longitude': query?['longitude'],
        'accuracy': query?['accuracy'],
        'source': 'device_current',
      },
      'summary': {
        'total_stops': 1,
        'remaining': 1,
        'visited': 0,
        'urgent': 0,
        'high': 0,
      },
      'stops': [
        {
          'customer_id': 'customer-1',
          'customer_name': 'Customer One',
          'recommended_order': 1,
          'priority': 'normal',
          'reasons': ['Regular route stop'],
          'visited_today': false,
        },
      ],
      'approximate_air_distance_km': 1.2,
      'distance_method': 'straight_line',
      'warnings': ['distance_estimate_is_straight_line'],
    };
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    await deleteDatabase(await _databasePath());
  });

  test('smart route sends current position and caches the plan', () async {
    final db = AppDatabase();
    await db.open();

    final api = _SmartRouteApi();
    final repository = DailyRoutePlanRepository(api: api, db: db);

    final plan = await repository.refresh(
      'tenant-1',
      latitude: 34.555,
      longitude: 69.207,
      accuracy: 7.5,
    );

    expect(api.lastQuery?['latitude'], 34.555);
    expect(api.lastQuery?['longitude'], 69.207);
    expect(api.lastQuery?['accuracy'], 7.5);
    expect(plan['stops'], isNotEmpty);

    final cached = await repository.cached('tenant-1');
    expect(cached?['date'], '2026-09-24');
    expect(
      ((cached?['stops'] as List).single as Map)['customer_id'],
      'customer-1',
    );
    expect(await repository.cachedAt('tenant-1'), isNotNull);

    await db.db.close();
  });

  test('smart route cache remains tenant scoped', () async {
    final db = AppDatabase();
    await db.open();

    final repository = DailyRoutePlanRepository(api: _SmartRouteApi(), db: db);

    await repository.refresh('tenant-a');

    expect(await repository.cached('tenant-a'), isNotNull);
    expect(await repository.cached('tenant-b'), isNull);

    await db.db.close();
  });
}
