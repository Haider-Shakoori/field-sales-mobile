import '../../core/api/api_client.dart';

class MasterPage {
  const MasterPage({
    required this.rows,
    required this.hasMore,
    required this.nextPage,
  });

  final List<Map<String, dynamic>> rows;
  final bool hasMore;
  final int? nextPage;
}

abstract class MasterDataSource {
  Future<MasterPage> fetchPage(
    String path, {
    int page = 1,
    int perPage = 100,
    String? updatedSince,
  });

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> payload,
  );
}

class ApiMasterDataSource implements MasterDataSource {
  const ApiMasterDataSource(this.api);

  final ApiClient api;

  @override
  Future<MasterPage> fetchPage(
    String path, {
    int page = 1,
    int perPage = 100,
    String? updatedSince,
  }) async {
    final envelope = await api.getEnvelope(
      path,
      query: {
        'page': page,
        'per_page': perPage,
        if (updatedSince != null) 'updated_since': updatedSince,
      },
    );

    final rows = (envelope.data as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final hasMore = envelope.meta['has_more'] == true;
    final nextPage = envelope.meta['next_page'];

    return MasterPage(
      rows: rows,
      hasMore: hasMore,
      nextPage: nextPage is int ? nextPage : int.tryParse('$nextPage'),
    );
  }

  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final data = await api.post(path, data: payload);

    return Map<String, dynamic>.from(data as Map);
  }
}
