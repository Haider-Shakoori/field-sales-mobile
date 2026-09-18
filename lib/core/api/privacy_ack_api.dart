import '../models/time_utils.dart';
import 'api_client.dart';

/// Server acknowledgement record returned by
/// `POST /api/v1/gps/privacy-acknowledgement`.
class PrivacyAcknowledgementResponse {
  const PrivacyAcknowledgementResponse({
    required this.id,
    this.uuid,
    this.policyVersion,
    this.acknowledgedAt,
  });

  factory PrivacyAcknowledgementResponse.fromJson(Map<String, dynamic> json) =>
      PrivacyAcknowledgementResponse(
        id: (json['id'] as num?)?.toInt() ?? 0,
        uuid: json['uuid']?.toString(),
        policyVersion: json['policy_version']?.toString(),
        acknowledgedAt: json['acknowledged_at'] == null
            ? null
            : DateTime.tryParse(json['acknowledged_at'].toString()),
      );

  final int id;
  final String? uuid;
  final String? policyVersion;
  final DateTime? acknowledgedAt;
}

/// GPS tracking policy acknowledgement gateway.
///
/// Identity (tenant/user/device) is derived server-side from the authenticated
/// device-bound request; only the policy version, acknowledgement instant and
/// app version are sent.
class PrivacyAcknowledgementApi {
  PrivacyAcknowledgementApi({required ApiClient apiClient})
    : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<PrivacyAcknowledgementResponse> acknowledge({
    required String policyVersion,
    required DateTime acknowledgedAt,
    required String appVersion,
  }) async {
    final data = await _apiClient.request(
      method: 'POST',
      path: '/gps/privacy-acknowledgement',
      body: {
        'policy_version': policyVersion,
        'acknowledged_at': utcIso(acknowledgedAt),
        'app_version': appVersion,
      },
    );
    return PrivacyAcknowledgementResponse.fromJson(
      data as Map<String, dynamic>,
    );
  }
}
