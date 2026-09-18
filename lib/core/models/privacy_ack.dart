import 'time_utils.dart';

/// Version of the GPS tracking disclosure the salesman must acknowledge.
///
/// Bump when the wording/policy materially changes; the acknowledgement row
/// stores the version so a later batch can trigger re-acknowledgement and push
/// the acceptance to the server audit log (`docs/SECURITY_PRIVACY.md` §8).
const String kGpsTrackingPolicyVersion = '1.0';

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
  });

  final String policyVersion;
  final DateTime acknowledgedAt;
  final int? userId;
  final int? tenantId;
  final String? deviceUuid;
  final String? appVersion;

  /// `pending` until the acknowledgement has been audited server-side.
  final String syncStatus;
  final int? serverId;

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
  };

  factory GpsPrivacyAcknowledgement.fromJson(Map<String, dynamic> json) =>
      GpsPrivacyAcknowledgement(
        policyVersion:
            json['policy_version']?.toString() ?? kGpsTrackingPolicyVersion,
        acknowledgedAt:
            DateTime.tryParse(json['acknowledged_at']?.toString() ?? '') ??
            DateTime.now().toUtc(),
        userId: (json['user_id'] as num?)?.toInt(),
        tenantId: (json['tenant_id'] as num?)?.toInt(),
        deviceUuid: json['device_uuid']?.toString(),
        appVersion: json['app_version']?.toString(),
        syncStatus: json['sync_status']?.toString() ?? 'pending',
        serverId: (json['server_id'] as num?)?.toInt(),
      );

  GpsPrivacyAcknowledgement copyWith({String? syncStatus, int? serverId}) =>
      GpsPrivacyAcknowledgement(
        policyVersion: policyVersion,
        acknowledgedAt: acknowledgedAt,
        userId: userId,
        tenantId: tenantId,
        deviceUuid: deviceUuid,
        appVersion: appVersion,
        syncStatus: syncStatus ?? this.syncStatus,
        serverId: serverId ?? this.serverId,
      );
}
