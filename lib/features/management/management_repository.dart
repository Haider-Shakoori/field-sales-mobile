import '../../core/api/api_client.dart';

class ManagementRepository {
  ManagementRepository(this.api);

  final ApiClient api;

  Future<Map<String, dynamic>> overview() async {
    return Map<String, dynamic>.from(
      await api.get('mobile/team/overview') as Map,
    );
  }
}
