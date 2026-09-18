import 'package:sqflite/sqflite.dart';

import '../models/gps_point.dart';
import '../models/time_utils.dart';
import 'app_database.dart';

/// Local append-only GPS buffer.
///
/// Every accepted fix is written here IMMEDIATELY (see the tracking service),
/// so points survive network loss, backgrounding and app restarts until the
/// dedicated GPS uploader drains them through `POST /api/v1/gps/locations`.
class GpsPointRepository {
  GpsPointRepository._();

  static final GpsPointRepository instance = GpsPointRepository._();

  /// Upload chunk size mandated by the GPS batch contract (max 100 points).
  static const maxBatchSize = kGpsUploadMaxBatchSize;

  Future<Database> get _db => AppDatabase.instance;

  /// Inserts [point], assigning the next monotonic [LocalGpsPoint.sequenceNumber]
  /// when the caller did not supply one (0). The unique `client_uuid` makes
  /// re-inserting the same fix a no-op conflict.
  Future<LocalGpsPoint> insertPoint(LocalGpsPoint point) async {
    final db = await _db;
    return db.transaction<LocalGpsPoint>((txn) async {
      var sequence = point.sequenceNumber;
      if (sequence <= 0) {
        sequence = await _nextSequenceNumber(txn);
      }
      final row = point.toRow()..['sequence_number'] = sequence;
      final localId = await txn.insert('local_gps_points', row);
      return point.copyWith(localId: localId, sequenceNumber: sequence);
    });
  }

  Future<int> _nextSequenceNumber(DatabaseExecutor txn) async {
    final rows = await txn.rawQuery(
      'SELECT COALESCE(MAX(sequence_number), 0) AS max_seq '
      'FROM local_gps_points',
    );
    return ((rows.first['max_seq'] as int?) ?? 0) + 1;
  }

  /// Pending points in chronological (sequence) order, up to [limit].
  Future<List<LocalGpsPoint>> pending({int limit = maxBatchSize}) async {
    final db = await _db;
    final rows = await db.query(
      'local_gps_points',
      where: 'sync_status = ?',
      whereArgs: [GpsPointSyncStatus.pending.name],
      orderBy: 'sequence_number ASC, id ASC',
      limit: limit,
    );
    return rows.map(LocalGpsPoint.fromRow).toList();
  }

  Future<int> pendingCount() async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM local_gps_points WHERE sync_status = ?',
      [GpsPointSyncStatus.pending.name],
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  /// Most recently RECORDED point, used for the tracking status panel and the
  /// End Day fallback when a fresh fix cannot be obtained.
  Future<LocalGpsPoint?> lastPoint() async {
    final db = await _db;
    final rows = await db.query(
      'local_gps_points',
      orderBy: 'recorded_at DESC, id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : LocalGpsPoint.fromRow(rows.first);
  }

  /// Tags a chunk with the [batchUuid] sent in the upload request.
  Future<void> assignBatch(List<String> clientUuids, String batchUuid) async {
    if (clientUuids.isEmpty) {
      return;
    }
    final db = await _db;
    await db.transaction((txn) async {
      for (final uuid in clientUuids) {
        await txn.update(
          'local_gps_points',
          {'batch_uuid': batchUuid},
          where: 'client_uuid = ?',
          whereArgs: [uuid],
        );
      }
    });
  }

  /// Marks points as uploaded (accepted OR deduplicated by the server).
  Future<void> markUploaded(
    List<String> clientUuids, {
    required String batchUuid,
    DateTime? uploadedAt,
  }) async {
    if (clientUuids.isEmpty) {
      return;
    }
    final at = utcIso((uploadedAt ?? DateTime.now()).toUtc());
    final db = await _db;
    await db.transaction((txn) async {
      for (final uuid in clientUuids) {
        await txn.update(
          'local_gps_points',
          {
            'sync_status': GpsPointSyncStatus.uploaded.name,
            'batch_uuid': batchUuid,
            'last_error': null,
            'uploaded_at': at,
          },
          where: 'client_uuid = ?',
          whereArgs: [uuid],
        );
      }
    });
  }

  /// Preserves rejected points with their diagnostic error instead of deleting
  /// them. They are excluded from the pending query until an operator or a
  /// future batch decides how to handle them.
  Future<void> markRejected(
    List<String> clientUuids, {
    required String batchUuid,
    required String error,
  }) async {
    if (clientUuids.isEmpty) {
      return;
    }
    final db = await _db;
    await db.transaction((txn) async {
      for (final uuid in clientUuids) {
        await txn.update(
          'local_gps_points',
          {
            'sync_status': GpsPointSyncStatus.rejected.name,
            'batch_uuid': batchUuid,
            'last_error': error,
          },
          where: 'client_uuid = ?',
          whereArgs: [uuid],
        );
      }
    });
  }

  /// Housekeeping: uploaded points older than [cutoff] can be dropped locally
  /// (server already has them). Default retention lives in the tracking
  /// config (7 days, per the sync design).
  Future<int> purgeUploadedBefore(DateTime cutoff) async {
    final db = await _db;
    return db.delete(
      'local_gps_points',
      where: 'sync_status = ? AND uploaded_at IS NOT NULL AND uploaded_at < ?',
      whereArgs: [GpsPointSyncStatus.uploaded.name, utcIso(cutoff.toUtc())],
    );
  }

  Future<int> countByStatus(GpsPointSyncStatus status) async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM local_gps_points WHERE sync_status = ?',
      [status.name],
    );
    return (rows.first['c'] as int?) ?? 0;
  }
}
