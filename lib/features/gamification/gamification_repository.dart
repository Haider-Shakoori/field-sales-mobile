import '../../core/api/api_client.dart';

class GamificationRepository {
  GamificationRepository(this.api);
  final ApiClient api;

  Future<Map<String, dynamic>> load() async =>
      Map<String, dynamic>.from(await api.get('gamification'));
}
