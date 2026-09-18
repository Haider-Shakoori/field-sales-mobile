import '../models/gps_point.dart';
import 'api_client.dart';

/// GPS bulk-upload gateway (`docs/API_CONTRACT.md` §8.6).
///
/// Dedicated transport for the local GPS buffer — this is intentionally NOT
/// part of the deferred Batch 12 `POST /api/v1/sync/push` engine.
class GpsApi {
  GpsApi({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  /// `POST /api/v1/gps/locations` with at most 100 points per request.
  ///
  /// The [batchUuid] doubles as the `X-Idempotency-Key`, so retrying the same
  /// batch is safe. Points keep their original `client_uuid`.
  Future<GpsUploadResult> uploadBatch({
    required String batchUuid,
    required List<LocalGpsPoint> points,
  }) async {
    if (points.length > kGpsUploadMaxBatchSize) {
      throw ArgumentError.value(
        points.length,
        'points',
        'GPS batch may not exceed $kGpsUploadMaxBatchSize points',
      );
    }

    final data = await _apiClient.request(
      method: 'POST',
      path: '/gps/locations',
      idempotencyKey: batchUuid,
      body: {
        'batch_uuid': batchUuid,
        'locations': points.map((p) => p.toApiJson()).toList(),
      },
    );
    return GpsUploadResult.fromJson(data as Map<String, dynamic>);
  }
}
