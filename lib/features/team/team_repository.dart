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

  Future<Map<String, dynamic>> referralPortfolio({
    int page = 1,
    int perPage = 30,
  }) async {
    final envelope = await api.getEnvelope(
      'referrals/me',
      query: {'page': page, 'per_page': perPage},
    );
    final data = envelope.data is Map<String, dynamic>
        ? Map<String, dynamic>.from(envelope.data as Map<String, dynamic>)
        : Map<String, dynamic>.from(envelope.data as Map);

    data['_meta'] = envelope.meta;
    return data;
  }

  Future<void> nudge(String salesmanId, String message) async {
    await api.post(
      'team/salesmen/$salesmanId/nudge',
      data: {'message': message},
    );
  }
}
