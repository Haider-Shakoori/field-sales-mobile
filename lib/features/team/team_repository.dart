import '../../core/api/api_client.dart';

class TeamRepository {
  TeamRepository(this.api);

  final ApiClient api;

  Future<Map<String, dynamic>> overview() async {
    final data = await api.get('team/overview');

    return data is Map<String, dynamic>
        ? data
        : Map<String, dynamic>.from(data as Map);
  }

  Future<void> nudge(String salesmanId, String message) async {
    await api.post(
      'team/salesmen/$salesmanId/nudge',
      data: {'message': message},
    );
  }
}
