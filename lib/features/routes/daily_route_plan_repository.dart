import '../../core/api/api_client.dart';
import '../../core/db/app_database.dart';

class DailyRoutePlanRepository {
  DailyRoutePlanRepository({required this.api, required this.db});

  final ApiClient api;
  final AppDatabase db;

  String _cacheKey(String tenantId) => 'daily_route_plan:$tenantId';
  String _inclusionsKey(String tenantId) => 'daily_route_inclusions:$tenantId';

  Future<Map<String, dynamic>?> cached(String tenantId) async {
    final raw = await db.readSetting(_cacheKey(tenantId));

    if (raw is! Map || raw['plan'] is! Map) {
      return null;
    }

    return Map<String, dynamic>.from(raw['plan'] as Map);
  }

  Future<DateTime?> cachedAt(String tenantId) async {
    final raw = await db.readSetting(_cacheKey(tenantId));

    if (raw is! Map) {
      return null;
    }

    final value = raw['cached_at']?.toString();

    return value == null ? null : DateTime.tryParse(value);
  }

  Future<List<String>> includedOpportunityIds(String tenantId) async {
    final raw = await db.readSetting(_inclusionsKey(tenantId));

    if (raw is! Map) {
      return <String>[];
    }

    final date = raw['date']?.toString();
    final today = _localDateKey(DateTime.now());

    if (date != today || raw['ids'] is! List) {
      return <String>[];
    }

    return (raw['ids'] as List)
        .map((value) => value.toString())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
  }

  Future<void> includeOpportunity(String tenantId, String customerId) async {
    final ids = await includedOpportunityIds(tenantId);

    if (!ids.contains(customerId)) {
      ids.add(customerId);
    }

    await _saveInclusions(tenantId, ids);
  }

  Future<void> removeOpportunity(String tenantId, String customerId) async {
    final ids = await includedOpportunityIds(tenantId);
    ids.removeWhere((value) => value == customerId);

    await _saveInclusions(tenantId, ids);
  }

  Future<Map<String, dynamic>> refresh(
    String tenantId, {
    double? latitude,
    double? longitude,
    double? accuracy,
    double nearbyRadiusKm = 5,
  }) async {
    final includedIds = await includedOpportunityIds(tenantId);
    final result = await api.get(
      'route-plan/today',
      query: {
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'nearby_radius_km': nearbyRadiusKm,
        'include_customer_ids': includedIds.isEmpty
            ? null
            : includedIds.join(','),
      },
    );

    final plan = Map<String, dynamic>.from(result as Map);
    final dynamicRoute = plan['dynamic_route'];
    final serverIncluded = dynamicRoute is Map
        ? dynamicRoute['included_opportunity_ids']
        : null;

    if (serverIncluded is List) {
      await _saveInclusions(
        tenantId,
        serverIncluded
            .map((value) => value.toString())
            .where((value) => value.isNotEmpty)
            .toList(),
      );
    }

    await db.setting(_cacheKey(tenantId), {
      'cached_at': DateTime.now().toUtc().toIso8601String(),
      'plan': plan,
    });

    return plan;
  }

  Future<void> _saveInclusions(String tenantId, List<String> ids) => db.setting(
    _inclusionsKey(tenantId),
    {'date': _localDateKey(DateTime.now()), 'ids': ids.toSet().toList()},
  );

  String _localDateKey(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');

    return '${local.year}-$month-$day';
  }
}
