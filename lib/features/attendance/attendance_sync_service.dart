import '../../core/api/api_exception.dart';
import '../../core/api/attendance_api.dart';
import '../../core/storage/work_session_repository.dart';
import '../../core/sync/sync_repository.dart';
import '../../core/sync/sync_status.dart';

/// Result of one attendance outbox drain.
class AttendanceSyncOutcome {
  const AttendanceSyncOutcome({
    this.synced = 0,
    this.failed = 0,
    this.authorizationLost = false,
    this.skipped = false,
    this.error,
  });

  final int synced;
  final int failed;
  final bool authorizationLost;
  final bool skipped;
  final String? error;
}

/// Dedicated attendance outbox drain (Start Day / End Day entries only).
///
/// This is deliberately NOT the Batch 12 general sync engine: it reads just
/// `entity_type = 'attendance'` rows from the existing outbox, attempts the two
/// documented endpoints once per trigger (Start/End Day, connectivity
/// restoration, app start), and never deletes local data on failure.
class AttendanceSyncService {
  AttendanceSyncService({
    required AttendanceApi api,
    WorkSessionRepository? workSessions,
    SyncQueueRepository? queue,
  }) : _api = api,
       _workSessions = workSessions ?? WorkSessionRepository.instance,
       _queue = queue ?? SyncQueueRepository.instance;

  final AttendanceApi _api;
  final WorkSessionRepository _workSessions;
  final SyncQueueRepository _queue;

  bool _syncing = false;
  bool get syncing => _syncing;

  String? _lastError;
  String? get lastError => _lastError;

  /// Invoked when the token/device is revoked; the attendance controller stops
  /// tracking and keeps every unsynced row.
  void Function(ApiException error)? onAuthorizationLost;

  Future<AttendanceSyncOutcome> flushPending({int limit = 20}) async {
    if (_syncing) {
      return const AttendanceSyncOutcome(skipped: true);
    }
    _syncing = true;
    var synced = 0;
    var failed = 0;
    try {
      final entries = await _queue.next(
        limit: limit,
        entityType: WorkSessionRepository.attendanceEntityType,
      );
      for (final entry in entries) {
        await _queue.markSyncing(entry);
        try {
          if (entry.action == WorkSessionRepository.startAction) {
            final session = await _api.start(
              offlineUuid: entry.entityUuid,
              latitude: _double(entry.payload['latitude']),
              longitude: _double(entry.payload['longitude']),
              accuracy: _nullableDouble(entry.payload['accuracy']),
            );
            if (session.id > 0) {
              await _workSessions.attachServerSession(
                entry.entityUuid,
                session.id,
              );
            } else {
              await _workSessions.updateSyncStatus(
                entry.entityUuid,
                SyncStatus.synced,
              );
            }
            await _queue.markSynced(
              entry,
              serverId: session.id > 0 ? session.id.toString() : null,
            );
          } else if (entry.action == WorkSessionRepository.endAction) {
            final session = await _api.end(
              latitude: _double(entry.payload['latitude']),
              longitude: _double(entry.payload['longitude']),
              accuracy: _nullableDouble(entry.payload['accuracy']),
              sessionOfflineUuid: entry.entityUuid,
            );
            if (session.id > 0) {
              await _workSessions.attachServerSession(
                entry.entityUuid,
                session.id,
              );
            } else {
              await _workSessions.updateSyncStatus(
                entry.entityUuid,
                SyncStatus.synced,
              );
            }
            await _queue.markSynced(
              entry,
              serverId: session.id > 0 ? session.id.toString() : null,
            );
          } else {
            await _queue.markFailed(
              entry,
              error: 'Unknown attendance action "${entry.action}"',
            );
            failed++;
            continue;
          }
          synced++;
        } on ApiException catch (error) {
          _lastError = error.message;
          if (error.isUnauthenticated || error.isDeviceRevoked) {
            // Keep the payload for after re-authentication; never delete it.
            await _queue.markFailed(entry, error: error.code ?? 'UNAUTHORIZED');
            onAuthorizationLost?.call(error);
            return AttendanceSyncOutcome(
              synced: synced,
              failed: failed + 1,
              authorizationLost: true,
              error: error.message,
            );
          }
          if (error.retryable) {
            // Transient (network/5xx/429): return to pending for the next
            // controlled trigger instead of scheduling backoff (Batch 12).
            await _queue.reset(entry.entityUuid);
            return AttendanceSyncOutcome(
              synced: synced,
              failed: failed,
              error: error.message,
            );
          }
          await _queue.markFailed(entry, error: error.message);
          failed++;
        }
      }
      _lastError = null;
      return AttendanceSyncOutcome(synced: synced, failed: failed);
    } finally {
      _syncing = false;
    }
  }

  /// Re-queues attendance entries that failed while the token was revoked, so
  /// a fresh login can retry them. Local sessions are flipped back to pending.
  Future<void> resetFailedEntries() async {
    final entries = await _queue.failedForEntity(
      WorkSessionRepository.attendanceEntityType,
    );
    for (final entry in entries) {
      await _queue.reset(entry.entityUuid);
      await _workSessions.updateSyncStatus(
        entry.entityUuid,
        SyncStatus.pending,
      );
    }
  }

  double _double(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  double? _nullableDouble(Object? value) {
    if (value == null) {
      return null;
    }
    return _double(value);
  }
}
