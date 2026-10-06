import '../../core/api/api_client.dart';
import '../../core/db/app_database.dart';
import 'attendance_tracking_settings.dart';

class MobileConfigurationSnapshot {
  const MobileConfigurationSnapshot({
    required this.tracking,
    required this.features,
    required this.device,
    required this.fetchedAt,
    this.version,
    this.updatedAt,
  });

  final AttendanceTrackingSettings tracking;
  final Map<String, dynamic> features;
  final Map<String, dynamic> device;
  final DateTime fetchedAt;
  final String? version;
  final DateTime? updatedAt;
}

class SettingsRepository {
  SettingsRepository({required this.api, required this.db});

  final ApiClient api;
  final AppDatabase db;

  Future<Map<String, dynamic>> features({String? tenantId}) async {
    try {
      final values = Map<String, dynamic>.from(
        await api.get('settings/features'),
      );
      if (tenantId != null) {
        await _storeFeatures(tenantId, values);
      }
      return values;
    } catch (_) {
      return tenantId == null ? const {} : loadFeatures(tenantId);
    }
  }

  Future<Map<String, dynamic>> loadFeatures(String tenantId) async {
    final cached = await db.readSetting('mobile_feature_settings');
    if (cached is Map && cached['tenant_id'] == tenantId) {
      return Map<String, dynamic>.from(cached['values'] as Map? ?? const {});
    }

    return const {};
  }

  Future<Map<String, dynamic>> loadDevicePolicy(String tenantId) async {
    final cached = await db.readSetting('mobile_device_policy');
    if (cached is Map && cached['tenant_id'] == tenantId) {
      return Map<String, dynamic>.from(cached['values'] as Map? ?? const {});
    }

    return const {};
  }

  Future<Map<String, dynamic>> loadConfigurationMeta(String tenantId) async {
    final cached = await db.readSetting('mobile_configuration_meta');
    if (cached is Map && cached['tenant_id'] == tenantId) {
      return Map<String, dynamic>.from(cached);
    }

    return const {};
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
      final settings = AttendanceTrackingSettings.fromJson(
        data,
        tenantId: tenantId,
        trusted: true,
      );
      await db.setting('attendance_tracking_settings', settings.toJson());
      return settings;
    } catch (_) {
      return load(tenantId);
    }
  }

  Future<MobileConfigurationSnapshot> syncConfiguration(String tenantId) async {
    final fetchedAt = DateTime.now().toUtc();

    try {
      final data = Map<String, dynamic>.from(await api.get('settings/sync'));
      final trackingJson = Map<String, dynamic>.from(
        data['tracking'] as Map? ?? const {},
      );
      final featuresJson = Map<String, dynamic>.from(
        data['features'] as Map? ?? const {},
      );
      final deviceJson = Map<String, dynamic>.from(
        data['device'] as Map? ?? const {},
      );
      final tracking = AttendanceTrackingSettings.fromJson(
        trackingJson,
        tenantId: tenantId,
        trusted: true,
      );

      await db.setting('attendance_tracking_settings', tracking.toJson());
      await _storeFeatures(tenantId, featuresJson, fetchedAt: fetchedAt);
      await _storeDevicePolicy(tenantId, deviceJson, fetchedAt: fetchedAt);
      await _storeConfigurationMeta(
        tenantId,
        version: data['configuration_version']?.toString(),
        updatedAt: data['updated_at']?.toString(),
        fetchedAt: fetchedAt,
      );

      return MobileConfigurationSnapshot(
        tracking: tracking,
        features: featuresJson,
        device: deviceJson,
        version: data['configuration_version']?.toString(),
        updatedAt: DateTime.tryParse(data['updated_at']?.toString() ?? ''),
        fetchedAt: fetchedAt,
      );
    } catch (_) {
      // Older servers or temporary connectivity problems fall back to the
      // existing settings endpoints and the most recent trusted local cache.
      final tracking = await refresh(tenantId);
      final featureValues = await features(tenantId: tenantId);
      final deviceValues = await loadDevicePolicy(tenantId);
      final meta = await loadConfigurationMeta(tenantId);

      return MobileConfigurationSnapshot(
        tracking: tracking,
        features: featureValues,
        device: deviceValues,
        version: meta['configuration_version']?.toString(),
        updatedAt: DateTime.tryParse(meta['updated_at']?.toString() ?? ''),
        fetchedAt:
            DateTime.tryParse(meta['fetched_at']?.toString() ?? '') ??
            fetchedAt,
      );
    }
  }

  Future<void> _storeFeatures(
    String tenantId,
    Map<String, dynamic> values, {
    DateTime? fetchedAt,
  }) => db.setting('mobile_feature_settings', {
    'tenant_id': tenantId,
    'values': values,
    'fetched_at': (fetchedAt ?? DateTime.now().toUtc()).toIso8601String(),
  });

  Future<void> _storeDevicePolicy(
    String tenantId,
    Map<String, dynamic> values, {
    required DateTime fetchedAt,
  }) => db.setting('mobile_device_policy', {
    'tenant_id': tenantId,
    'values': values,
    'fetched_at': fetchedAt.toIso8601String(),
  });

  Future<void> _storeConfigurationMeta(
    String tenantId, {
    required String? version,
    required String? updatedAt,
    required DateTime fetchedAt,
  }) => db.setting('mobile_configuration_meta', {
    'tenant_id': tenantId,
    'configuration_version': version,
    'updated_at': updatedAt,
    'fetched_at': fetchedAt.toIso8601String(),
  });
}
