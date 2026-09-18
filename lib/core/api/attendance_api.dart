import '../models/attendance.dart';
import 'api_client.dart';

/// Attendance / work-session gateway (`docs/API_CONTRACT.md` §8.5).
///
/// The mobile app is offline-first: these methods are only called
/// opportunistically by the dedicated attendance outbox drain. A missing or
/// unreachable backend never blocks Start Day / End Day locally.
class AttendanceApi {
  AttendanceApi({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  /// `POST /api/v1/attendance/start` — idempotent by [offlineUuid].
  Future<AttendanceSession> start({
    required String offlineUuid,
    required double latitude,
    required double longitude,
    double? accuracy,
  }) async {
    final data = await _apiClient.request(
      method: 'POST',
      path: '/attendance/start',
      idempotencyKey: offlineUuid,
      body: {
        'offline_uuid': offlineUuid,
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': ?accuracy,
      },
    );
    return AttendanceSession.fromJson(data as Map<String, dynamic>);
  }

  /// `POST /api/v1/attendance/end` — ends the server-side active session.
  Future<AttendanceSession> end({
    required double latitude,
    required double longitude,
    double? accuracy,
    String? sessionOfflineUuid,
  }) async {
    final data = await _apiClient.request(
      method: 'POST',
      path: '/attendance/end',
      idempotencyKey: sessionOfflineUuid == null
          ? null
          : '$sessionOfflineUuid:end',
      body: {
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': ?accuracy,
      },
    );
    return AttendanceSession.fromJson(data as Map<String, dynamic>);
  }

  /// `GET /api/v1/attendance/today` — null when no session exists server side.
  Future<AttendanceSession?> today() async {
    final data = await _apiClient.request(
      method: 'GET',
      path: '/attendance/today',
    );
    if (data is! Map<String, dynamic>) {
      return null;
    }
    return AttendanceSession.fromJson(data);
  }

  /// `GET /api/v1/attendance/history` — paginated newest-first.
  Future<List<AttendanceSession>> history({
    int page = 1,
    int perPage = 25,
  }) async {
    final data = await _apiClient.request(
      method: 'GET',
      path: '/attendance/history',
      query: {'page': page, 'per_page': perPage},
    );
    if (data is! List) {
      return const [];
    }
    return data
        .whereType<Map<String, dynamic>>()
        .map(AttendanceSession.fromJson)
        .toList();
  }
}
