import '../../core/api/api_client.dart';
import '../../core/db/app_database.dart';
import 'attendance_tracking_settings.dart';

class SettingsRepository {
  SettingsRepository({required this.api, required this.db});
  final ApiClient api;
  final AppDatabase db;
  Future<Map<String, dynamic>> features() async {
    try {
      return Map<String, dynamic>.from(await api.get('settings/features'));
    } catch (_) {
      return const {};
    }
  }

  Future<AttendanceTrackingSettings> load(String tenantId) async {
    final cached = await db.readSetting('attendance_tracking_settings');
    if (cached is Map &&
        cached['tenant_id'] == tenantId &&
        cached['trusted'] == true) {
      return AttendanceTrackingSettings.fromJson(
        Map<String, dynamic>.from(cached),
        tenantId: tenantId,
        trusted: true,
      );
    }
    return AttendanceTrackingSettings.defaults(tenantId: tenantId);
  }

  Future<AttendanceTrackingSettings> refresh(String tenantId) async {
    try {
      final data = Map<String, dynamic>.from(
        await api.get('settings/attendance-tracking'),
      );
      final s = AttendanceTrackingSettings.fromJson(
        data,
        tenantId: tenantId,
        trusted: true,
      );
      await db.setting('attendance_tracking_settings', s.toJson());
      return s;
    } catch (_) {
      return load(tenantId);
    }
  }
}
