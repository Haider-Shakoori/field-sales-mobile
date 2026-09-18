import 'time_utils.dart';

/// Version of the GPS tracking disclosure the salesman must acknowledge.
///
/// Mirrors Laravel's `AttendanceTrackingSettings::POLICY_VERSION` fallback;
/// trusted server settings override it through their `privacy_policy_version`.
/// Bump when the wording/policy materially changes.
const String kGpsTrackingPolicyVersion = '1';

/// Locally persisted GPS tracking acknowledgement.
///
/// The fields mirror what a future `POST` to the attendance/audit backend will
/// need (who acknowledged, which policy version, when, on which device), so the
/// record can be synchronized/reviewed server-side without a schema change.
class GpsPrivacyAcknowledgement {
  const GpsPrivacyAcknowledgement({
    this.policyVersion = kGpsTrackingPolicyVersion,
    required this.acknowledgedAt,
    this.userId,
    this.tenantId,
    this.deviceUuid,
    this.appVersion,
    this.syncStatus = 'pending',
    this.serverId,
    this.serverUuid,
  });

  final String policyVersion;
  final DateTime acknowledgedAt;
  final String? userId;
  final String? tenantId;
  final String? deviceUuid;
  final String? appVersion;

  /// `pending` until the acknowledgement has been audited server-side.
  final String syncStatus;
  final int? serverId;
  final String? serverUuid;

  bool get isSynced => syncStatus == 'synced';

  Map<String, dynamic> toJson() => {
    'policy_version': policyVersion,
    'acknowledged_at': utcIso(acknowledgedAt),
    'user_id': userId,
    'tenant_id': tenantId,
    'device_uuid': deviceUuid,
    'app_version': appVersion,
    'sync_status': syncStatus,
    'server_id': serverId,
    'server_uuid': serverUuid,
  };

  factory GpsPrivacyAcknowledgement.fromJson(Map<String, dynamic> json) =>
      GpsPrivacyAcknowledgement(
        policyVersion:
            json['policy_version']?.toString() ?? kGpsTrackingPolicyVersion,
        acknowledgedAt:
            DateTime.tryParse(json['acknowledged_at']?.toString() ?? '') ??
            DateTime.now().toUtc(),
        userId: json['user_id']?.toString(),
        tenantId: json['tenant_id']?.toString(),
        deviceUuid: json['device_uuid']?.toString(),
        appVersion: json['app_version']?.toString(),
        syncStatus: json['sync_status']?.toString() ?? 'pending',
        serverId: (json['server_id'] as num?)?.toInt(),
        serverUuid: json['server_uuid']?.toString(),
      );

  GpsPrivacyAcknowledgement copyWith({
    String? syncStatus,
    int? serverId,
    String? serverUuid,
  }) => GpsPrivacyAcknowledgement(
    policyVersion: policyVersion,
    acknowledgedAt: acknowledgedAt,
    userId: userId,
    tenantId: tenantId,
    deviceUuid: deviceUuid,
    appVersion: appVersion,
    syncStatus: syncStatus ?? this.syncStatus,
    serverId: serverId ?? this.serverId,
    serverUuid: serverUuid ?? this.serverUuid,
  );
}
