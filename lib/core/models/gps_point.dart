import 'time_utils.dart';

/// Hard limit on points per `POST /api/v1/gps/locations` request (contract §8.6).
const int kGpsUploadMaxBatchSize = 100;

/// Upload state of one locally buffered GPS point.
///
/// `pending` → not yet acknowledged by the server; `uploaded` → accepted or
/// deduplicated; `rejected` → the server refused it (diagnostic preserved,
/// never silently deleted).
enum GpsPointSyncStatus {
  pending,
  uploaded,
  rejected;

  static GpsPointSyncStatus from(String? value) =>
      GpsPointSyncStatus.values.firstWhere(
        (s) => s.name == value,
        orElse: () => GpsPointSyncStatus.pending,
      );
}

/// One accepted GPS fix persisted to SQLite immediately after capture.
///
/// [clientUuid] is a UUIDv4 generated client-side exactly once and reused on
/// every retry — it is the server-side deduplication key. [sequenceNumber] is
/// monotonically increasing within the local buffer so ordering survives
/// restarts.
class LocalGpsPoint {
  const LocalGpsPoint({
    this.localId,
    required this.clientUuid,
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.accuracy,
    this.speed,
    this.heading,
    this.batteryLevel,
    this.isCharging = false,
    this.networkStatus,
    this.isMockLocation = false,
    this.provider,
    required this.recordedAt,
    this.sequenceNumber = 0,
    this.batchUuid,
    this.syncStatus = GpsPointSyncStatus.pending,
    this.lastError,
    this.uploadedAt,
    required this.createdAt,
  });

  final int? localId;
  final String clientUuid;
  final double latitude;
  final double longitude;
  final double? altitude;
  final double? accuracy;
  final double? speed;
  final double? heading;
  final int? batteryLevel;
  final bool isCharging;
  final String? networkStatus;
  final bool isMockLocation;
  final String? provider;
  final DateTime recordedAt;
  final int sequenceNumber;
  final String? batchUuid;
  final GpsPointSyncStatus syncStatus;
  final String? lastError;
  final DateTime? uploadedAt;
  final DateTime createdAt;

  /// Payload shape mandated by `POST /api/v1/gps/locations` (contract §8.6).
  Map<String, dynamic> toApiJson() => {
    'client_uuid': clientUuid,
    'latitude': latitude,
    'longitude': longitude,
    if (altitude != null) 'altitude': altitude,
    if (accuracy != null) 'accuracy': accuracy,
    if (speed != null) 'speed': speed,
    if (heading != null) 'heading': heading,
    if (batteryLevel != null) 'battery_level': batteryLevel,
    'is_charging': isCharging,
    if (networkStatus != null) 'network_status': networkStatus,
    'is_mock_location': isMockLocation,
    if (provider != null) 'provider': provider,
    'recorded_at': utcIso(recordedAt),
    'sequence_number': sequenceNumber,
  };

  Map<String, Object?> toRow() => {
    if (localId != null) 'id': localId,
    'client_uuid': clientUuid,
    'latitude': latitude,
    'longitude': longitude,
    'altitude': altitude,
    'accuracy': accuracy,
    'speed': speed,
    'heading': heading,
    'battery_level': batteryLevel,
    'is_charging': isCharging ? 1 : 0,
    'network_status': networkStatus,
    'is_mock_location': isMockLocation ? 1 : 0,
    'provider': provider,
    'recorded_at': utcIso(recordedAt),
    'sequence_number': sequenceNumber,
    'batch_uuid': batchUuid,
    'sync_status': syncStatus.name,
    'last_error': lastError,
    'uploaded_at': uploadedAt == null ? null : utcIso(uploadedAt!),
    'created_at': utcIso(createdAt),
  };

  factory LocalGpsPoint.fromRow(Map<String, Object?> row) => LocalGpsPoint(
    localId: row['id'] as int?,
    clientUuid: row['client_uuid'] as String,
    latitude: (row['latitude'] as num).toDouble(),
    longitude: (row['longitude'] as num).toDouble(),
    altitude: (row['altitude'] as num?)?.toDouble(),
    accuracy: (row['accuracy'] as num?)?.toDouble(),
    speed: (row['speed'] as num?)?.toDouble(),
    heading: (row['heading'] as num?)?.toDouble(),
    batteryLevel: (row['battery_level'] as num?)?.toInt(),
    isCharging: (row['is_charging'] as int? ?? 0) == 1,
    networkStatus: row['network_status'] as String?,
    isMockLocation: (row['is_mock_location'] as int? ?? 0) == 1,
    provider: row['provider'] as String?,
    recordedAt: DateTime.parse(row['recorded_at'] as String),
    sequenceNumber: (row['sequence_number'] as int?) ?? 0,
    batchUuid: row['batch_uuid'] as String?,
    syncStatus: GpsPointSyncStatus.from(row['sync_status'] as String?),
    lastError: row['last_error'] as String?,
    uploadedAt: parseStoredTime(row['uploaded_at'] as String?),
    createdAt: DateTime.parse(row['created_at'] as String),
  );

  LocalGpsPoint copyWith({
    int? localId,
    int? sequenceNumber,
    String? batchUuid,
    GpsPointSyncStatus? syncStatus,
    String? lastError,
    DateTime? uploadedAt,
  }) => LocalGpsPoint(
    localId: localId ?? this.localId,
    clientUuid: clientUuid,
    latitude: latitude,
    longitude: longitude,
    altitude: altitude,
    accuracy: accuracy,
    speed: speed,
    heading: heading,
    batteryLevel: batteryLevel,
    isCharging: isCharging,
    networkStatus: networkStatus,
    isMockLocation: isMockLocation,
    provider: provider,
    recordedAt: recordedAt,
    sequenceNumber: sequenceNumber ?? this.sequenceNumber,
    batchUuid: batchUuid ?? this.batchUuid,
    syncStatus: syncStatus ?? this.syncStatus,
    lastError: lastError ?? this.lastError,
    uploadedAt: uploadedAt ?? this.uploadedAt,
    createdAt: createdAt,
  );
}

/// Server verdict for one uploaded GPS batch (contract §8.6 / sync design §4.3).
class GpsUploadResult {
  const GpsUploadResult({
    required this.accepted,
    required this.rejected,
    required this.duplicates,
    this.batchId,
    this.acceptedUuids = const [],
    this.rejectedUuids = const [],
    this.duplicateUuids = const [],
  });

  factory GpsUploadResult.fromJson(Map<String, dynamic> json) {
    List<String> uuidList(Object? value) {
      if (value is! List) {
        return const [];
      }
      return value.map((e) => e.toString()).toList();
    }

    return GpsUploadResult(
      accepted: (json['accepted'] as num?)?.toInt() ?? 0,
      rejected: (json['rejected'] as num?)?.toInt() ?? 0,
      duplicates: (json['duplicates'] as num?)?.toInt() ?? 0,
      batchId: (json['batch_id'] as num?)?.toInt(),
      acceptedUuids: uuidList(json['accepted_uuids']),
      rejectedUuids: uuidList(json['rejected_uuids']),
      duplicateUuids: uuidList(json['duplicate_uuids']),
    );
  }

  final int accepted;
  final int rejected;
  final int duplicates;
  final int? batchId;

  /// Optional per-point verdicts; the current contract returns aggregate
  /// counts only, but the parser accepts precise lists if the server adds
  /// them later.
  final List<String> acceptedUuids;
  final List<String> rejectedUuids;
  final List<String> duplicateUuids;

  bool get hasPerPointVerdicts =>
      acceptedUuids.isNotEmpty ||
      rejectedUuids.isNotEmpty ||
      duplicateUuids.isNotEmpty;

  int get uploadedCount => accepted + duplicates;

  bool get fullyUploaded => rejected == 0 && uploadedCount > 0;
}
