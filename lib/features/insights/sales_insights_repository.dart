import '../../core/api/api_client.dart';
import '../../core/db/app_database.dart';
import '../../core/sync/connectivity_gate.dart';

class SalesInsightsRepository {
  SalesInsightsRepository({required this.api, required this.db});
  final ApiClient api;
  final AppDatabase db;

  Future<List<Map<String, dynamic>>> reorderRecommendations(
    String tenantId,
  ) async {
    const suffix = 'reorder-recommendations';
    final key = 'insights:$tenantId:$suffix';
    if (await ConnectivityGate.instance.isOnline()) {
      try {
        final data = await api.get('recommendations/reorders');
        final rows = (data as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        await db.setting(key, rows);
        return rows;
      } catch (_) {}
    }
    final cached = await db.readSetting(key);
    return (cached as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<Map<String, dynamic>> commissions(String tenantId) async {
    final key = 'insights:$tenantId:commissions';
    if (await ConnectivityGate.instance.isOnline()) {
      try {
        final data = Map<String, dynamic>.from(
          await api.get('commissions/me') as Map,
        );
        await db.setting(key, data);
        return data;
      } catch (_) {}
    }
    final cached = await db.readSetting(key);
    return cached is Map
        ? Map<String, dynamic>.from(cached)
        : {'summary': <String, dynamic>{}, 'earnings': <dynamic>[]};
  }
}
