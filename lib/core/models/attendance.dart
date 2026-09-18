import '../sync/sync_status.dart';
import 'time_utils.dart';

/// Local lifecycle of a work session.
enum WorkSessionStatus {
  active,
  completed;

  static WorkSessionStatus from(String? value) =>
      WorkSessionStatus.values.firstWhere(
        (s) => s.name == value,
        orElse: () => WorkSessionStatus.active,
      );
}

/// How a local work session was started.
///
/// Local audit/UI metadata only — it is intentionally NOT added to the
/// attendance API payload before the Laravel contract reconciliation.
enum WorkSessionStartSource {
  manual,
  automatic;

  static WorkSessionStartSource from(String? value) =>
      WorkSessionStartSource.values.firstWhere(
        (source) => source.name == value,
        orElse: () => WorkSessionStartSource.manual,
      );
}

/// One locally-recorded attendance work session (Start Day → End Day).
///
/// The local row is the source of truth for the UI; [syncStatus] mirrors how
/// far the matching attendance outbox entry has progressed. [serverId] is
/// attached when the backend acknowledges the session.
class LocalWorkSession {
  const LocalWorkSession({
    this.localId,
    required this.offlineUuid,
    this.serverId,
    required this.date,
    required this.startTime,
    this.endTime,
    required this.startLatitude,
    required this.startLongitude,
    this.startAccuracy,
    this.endLatitude,
    this.endLongitude,
    this.endAccuracy,
    this.status = WorkSessionStatus.active,
    this.syncStatus = SyncStatus.pending,
    this.startSource = WorkSessionStartSource.manual,
    this.privacyAckAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? localId;
  final String offlineUuid;
  final int? serverId;

  /// Local calendar day (`yyyy-MM-dd`) the session started on.
  final String date;

  final DateTime startTime;
  final DateTime? endTime;
  final double startLatitude;
  final double startLongitude;
  final double? startAccuracy;
  final double? endLatitude;
  final double? endLongitude;
  final double? endAccuracy;
  final WorkSessionStatus status;
  final SyncStatus syncStatus;

  /// Whether the salesman pressed Start Day or the company automatic policy
  /// created the session.
  final WorkSessionStartSource startSource;

  /// When the salesman acknowledged the GPS tracking disclosure for this
  /// session (kept for later server-side audit synchronization).
  final String? privacyAckAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isActive => status == WorkSessionStatus.active;

  Duration? get duration {
    final end = endTime;
    if (end == null) {
      return null;
    }
    final diff = end.difference(startTime);
    return diff.isNegative ? Duration.zero : diff;
  }

  Map<String, Object?> toRow() => {
    if (localId != null) 'id': localId,
    'offline_uuid': offlineUuid,
    'server_id': serverId,
    'date': date,
    'start_time': utcIso(startTime),
    'end_time': endTime == null ? null : utcIso(endTime!),
    'start_latitude': startLatitude,
    'start_longitude': startLongitude,
    'start_accuracy': startAccuracy,
    'end_latitude': endLatitude,
    'end_longitude': endLongitude,
    'end_accuracy': endAccuracy,
    'status': status.name,
    'sync_status': syncStatus.name,
    'start_source': startSource.name,
    'privacy_ack_at': privacyAckAt,
    'created_at': utcIso(createdAt),
    'updated_at': utcIso(updatedAt),
  };

  factory LocalWorkSession.fromRow(Map<String, Object?> row) =>
      LocalWorkSession(
        localId: row['id'] as int?,
        offlineUuid: row['offline_uuid'] as String,
        serverId: row['server_id'] as int?,
        date: row['date'] as String,
        startTime: DateTime.parse(row['start_time'] as String),
        endTime: parseStoredTime(row['end_time'] as String?),
        startLatitude: (row['start_latitude'] as num).toDouble(),
        startLongitude: (row['start_longitude'] as num).toDouble(),
        startAccuracy: (row['start_accuracy'] as num?)?.toDouble(),
        endLatitude: (row['end_latitude'] as num?)?.toDouble(),
        endLongitude: (row['end_longitude'] as num?)?.toDouble(),
        endAccuracy: (row['end_accuracy'] as num?)?.toDouble(),
        status: WorkSessionStatus.from(row['status'] as String?),
        syncStatus: SyncStatus.from(row['sync_status'] as String?),
        startSource: WorkSessionStartSource.from(
          row['start_source'] as String?,
        ),
        privacyAckAt: row['privacy_ack_at'] as String?,
        createdAt: DateTime.parse(row['created_at'] as String),
        updatedAt: DateTime.parse(row['updated_at'] as String),
      );

  LocalWorkSession copyWith({
    int? localId,
    int? serverId,
    DateTime? endTime,
    double? endLatitude,
    double? endLongitude,
    double? endAccuracy,
    WorkSessionStatus? status,
    SyncStatus? syncStatus,
    WorkSessionStartSource? startSource,
    DateTime? updatedAt,
  }) => LocalWorkSession(
    localId: localId ?? this.localId,
    offlineUuid: offlineUuid,
    serverId: serverId ?? this.serverId,
    date: date,
    startTime: startTime,
    endTime: endTime ?? this.endTime,
    startLatitude: startLatitude,
    startLongitude: startLongitude,
    startAccuracy: startAccuracy,
    endLatitude: endLatitude ?? this.endLatitude,
    endLongitude: endLongitude ?? this.endLongitude,
    endAccuracy: endAccuracy ?? this.endAccuracy,
    status: status ?? this.status,
    syncStatus: syncStatus ?? this.syncStatus,
    startSource: startSource ?? this.startSource,
    privacyAckAt: privacyAckAt,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// Server-side attendance session as defined by `docs/API_CONTRACT.md` §8.5.
class AttendanceSession {
  const AttendanceSession({
    required this.id,
    this.userId,
    required this.status,
    required this.startedAt,
    this.endedAt,
    this.durationHours,
    this.startLocation,
    this.endLocation,
    this.offlineUuid,
  });

  factory AttendanceSession.fromJson(Map<String, dynamic> json) =>
      AttendanceSession(
        id: (json['id'] as num?)?.toInt() ?? 0,
        userId: (json['user_id'] as num?)?.toInt(),
        status: json['status']?.toString() ?? 'active',
        startedAt: _parse(json['started_at']),
        endedAt: _parse(json['ended_at']),
        durationHours: (json['duration_hours'] as num?)?.toDouble(),
        startLocation: AttendanceLocation.fromJson(json['start_location']),
        endLocation: AttendanceLocation.fromJson(json['end_location']),
        offlineUuid: json['offline_uuid']?.toString(),
      );

  final int id;
  final int? userId;
  final String status;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final double? durationHours;
  final AttendanceLocation? startLocation;
  final AttendanceLocation? endLocation;
  final String? offlineUuid;

  static DateTime? _parse(Object? value) {
    if (value is! String || value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(value);
  }
}

class AttendanceLocation {
  const AttendanceLocation({required this.latitude, required this.longitude});

  static AttendanceLocation? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      return null;
    }
    final latitude = (value['latitude'] as num?)?.toDouble();
    final longitude = (value['longitude'] as num?)?.toDouble();
    if (latitude == null || longitude == null) {
      return null;
    }
    return AttendanceLocation(latitude: latitude, longitude: longitude);
  }

  final double latitude;
  final double longitude;
}
