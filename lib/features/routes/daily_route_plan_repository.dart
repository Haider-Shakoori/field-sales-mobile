import '../../core/api/api_client.dart';
import '../../core/db/app_database.dart';

class DailyRoutePlanRepository {
  DailyRoutePlanRepository({required this.api, required this.db});

  final ApiClient api;
  final AppDatabase db;

  String _cacheKey(String tenantId) => 'daily_route_plan:$tenantId';

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

  Future<Map<String, dynamic>> refresh(
    String tenantId, {
    double? latitude,
    double? longitude,
    double? accuracy,
  }) async {
    final result = await api.get(
      'route-plan/today',
      query: {
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
      },
    );

    final plan = Map<String, dynamic>.from(result as Map);

    await db.setting(_cacheKey(tenantId), {
      'cached_at': DateTime.now().toUtc().toIso8601String(),
      'plan': plan,
    });

    return plan;
  }
}
