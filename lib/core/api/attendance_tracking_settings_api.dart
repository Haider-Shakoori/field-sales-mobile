import '../models/attendance_tracking_settings.dart';
import '../storage/attendance_tracking_settings_repository.dart';
import 'api_client.dart';

/// Real mobile gateway for company attendance/tracking policy.
///
/// `GET /api/v1/settings/attendance-tracking` is read-only for mobile and
/// requires the standard device headers + bearer token already applied by
/// [ApiClient].
class AttendanceTrackingSettingsApi {
  AttendanceTrackingSettingsApi({required ApiClient apiClient})
    : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<AttendanceTrackingSettings> fetch() async {
    final data = await _apiClient.request(
      method: 'GET',
      path: '/settings/attendance-tracking',
    );
    return AttendanceTrackingSettings.fromApiJson(data as Map<String, dynamic>);
  }
}

/// Binds the real Laravel endpoint to the repository's refresh seam.
class HttpAttendanceTrackingSettingsSource
    implements AttendanceTrackingSettingsSource {
  HttpAttendanceTrackingSettingsSource({
    required AttendanceTrackingSettingsApi api,
  }) : _api = api;

  final AttendanceTrackingSettingsApi _api;

  @override
  Future<AttendanceTrackingSettings?> fetch() => _api.fetch();
}
