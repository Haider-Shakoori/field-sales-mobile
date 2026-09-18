import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/attendance.dart';
import '../models/time_utils.dart';
import '../sync/sync_queue.dart';
import '../sync/sync_repository.dart';
import '../sync/sync_status.dart';
import 'app_database.dart';

/// Thrown when a Start Day is attempted while another session is active.
class ActiveSessionExistsException implements Exception {
  const ActiveSessionExistsException(this.offlineUuid);

  final String? offlineUuid;

  @override
  String toString() =>
      'ActiveSessionExistsException: ${offlineUuid ?? 'unknown session'}';
}

/// Thrown when End Day finds no active local session.
class NoActiveSessionException implements Exception {
  const NoActiveSessionException();

  @override
  String toString() => 'NoActiveSessionException';
}

/// Offline-first persistence for attendance work sessions.
///
/// Start and End are transactional: the local session write and its attendance
/// outbox entry commit together (or not at all). The UI reads this local table
/// exclusively — network success never gates the work session state.
class WorkSessionRepository {
  WorkSessionRepository._();

  static final WorkSessionRepository instance = WorkSessionRepository._();

  static const attendanceEntityType = 'attendance';
  static const startAction = 'start';
  static const endAction = 'end';

  /// Outbox entries for attendance are drained before generic priorities.
  static const attendancePriority = 2;

  Future<Database> get _db => AppDatabase.instance;

  /// The single locally ACTIVE session, or null when the day is not started.
  Future<LocalWorkSession?> activeSession() async {
    final db = await _db;
    final rows = await db.query(
      'local_work_sessions',
      where: 'status = ?',
      whereArgs: [WorkSessionStatus.active.name],
      orderBy: 'start_time DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : LocalWorkSession.fromRow(rows.first);
  }

  /// Most recent session started on the local calendar day of [day].
  Future<LocalWorkSession?> sessionForDay(DateTime day) =>
      sessionForDayKey(localDateKey(day));

  /// Most recent session for a pre-computed local date key (`yyyy-MM-dd`).
  ///
  /// Used with tenant-timezone dates so local "today" matches the server's
  /// tenant-local work date.
  Future<LocalWorkSession?> sessionForDayKey(String dateKey) async {
    final db = await _db;
    final rows = await db.query(
      'local_work_sessions',
      where: 'date = ?',
      whereArgs: [dateKey],
      orderBy: 'start_time DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : LocalWorkSession.fromRow(rows.first);
  }

  Future<LocalWorkSession?> sessionForToday() => sessionForDay(DateTime.now());

  Future<LocalWorkSession?> byOfflineUuid(String offlineUuid) async {
    final db = await _db;
    final rows = await db.query(
      'local_work_sessions',
      where: 'offline_uuid = ?',
      whereArgs: [offlineUuid],
      limit: 1,
    );
    return rows.isEmpty ? null : LocalWorkSession.fromRow(rows.first);
  }

  /// Recent sessions (newest first) for the local attendance history view.
  Future<List<LocalWorkSession>> recent({int limit = 30}) async {
    final db = await _db;
    final rows = await db.query(
      'local_work_sessions',
      orderBy: 'start_time DESC',
      limit: limit,
    );
    return rows.map(LocalWorkSession.fromRow).toList();
  }

  /// Inserts the local session and enqueues its attendance-start outbox entry
  /// in ONE transaction. If the enqueue fails the session insert rolls back.
  Future<LocalWorkSession> startSession({
    required double latitude,
    required double longitude,
    double? accuracy,
    String? privacyAckAt,
    DateTime? startedAt,
    String? localDateKeyOverride,
    WorkSessionStartSource source = WorkSessionStartSource.manual,
  }) async {
    final db = await _db;
    final at = (startedAt ?? DateTime.now()).toUtc();
    final now = DateTime.now().toUtc();
    final offlineUuid = const Uuid().v4();

    final session = LocalWorkSession(
      offlineUuid: offlineUuid,
      date: localDateKeyOverride ?? localDateKey(at),
      startTime: at,
      startLatitude: latitude,
      startLongitude: longitude,
      startAccuracy: accuracy,
      status: WorkSessionStatus.active,
      syncStatus: SyncStatus.pending,
      startSource: source,
      privacyAckAt: privacyAckAt,
      createdAt: now,
      updatedAt: now,
    );

    final entry = QueueEntry(
      entityType: attendanceEntityType,
      entityUuid: offlineUuid,
      action: startAction,
      priority: attendancePriority,
      payload: {
        'offline_uuid': offlineUuid,
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': ?accuracy,
        'started_at': utcIso(at),
      },
    );

    return db.transaction<LocalWorkSession>((txn) async {
      final active = await txn.query(
        'local_work_sessions',
        columns: ['offline_uuid'],
        where: 'status = ?',
        whereArgs: [WorkSessionStatus.active.name],
        limit: 1,
      );
      if (active.isNotEmpty) {
        throw ActiveSessionExistsException(
          active.first['offline_uuid'] as String?,
        );
      }

      final localId = await txn.insert('local_work_sessions', session.toRow());
      await SyncQueueRepository.instance.enqueue(entry, txn: txn);
      return session.copyWith(localId: localId);
    });
  }

  /// Closes the SAME local session identified by [session.offlineUuid] and
  /// enqueues attendance-end atomically. Never creates a new session.
  Future<LocalWorkSession> endSession({
    required LocalWorkSession session,
    required double latitude,
    required double longitude,
    double? accuracy,
    DateTime? endedAt,
  }) async {
    final db = await _db;
    final at = (endedAt ?? DateTime.now()).toUtc();

    final entry = QueueEntry(
      entityType: attendanceEntityType,
      entityUuid: session.offlineUuid,
      action: endAction,
      priority: attendancePriority,
      payload: {
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': ?accuracy,
        'ended_at': utcIso(at),
      },
    );

    return db.transaction<LocalWorkSession>((txn) async {
      final changed = await txn.update(
        'local_work_sessions',
        {
          'end_time': utcIso(at),
          'end_latitude': latitude,
          'end_longitude': longitude,
          'end_accuracy': accuracy,
          'status': WorkSessionStatus.completed.name,
          'sync_status': SyncStatus.pending.name,
          'updated_at': utcIso(DateTime.now().toUtc()),
        },
        where: 'offline_uuid = ? AND status = ?',
        whereArgs: [session.offlineUuid, WorkSessionStatus.active.name],
      );
      if (changed == 0) {
        throw const NoActiveSessionException();
      }

      await SyncQueueRepository.instance.enqueue(entry, txn: txn);

      final rows = await txn.query(
        'local_work_sessions',
        where: 'offline_uuid = ?',
        whereArgs: [session.offlineUuid],
        limit: 1,
      );
      return LocalWorkSession.fromRow(rows.single);
    });
  }

  /// Attaches the server id after the attendance API acknowledges the session.
  Future<void> attachServerSession(
    String offlineUuid,
    int serverId, {
    SyncStatus syncStatus = SyncStatus.synced,
  }) async {
    final db = await _db;
    await db.update(
      'local_work_sessions',
      {
        'server_id': serverId,
        'sync_status': syncStatus.name,
        'updated_at': utcIso(DateTime.now().toUtc()),
      },
      where: 'offline_uuid = ?',
      whereArgs: [offlineUuid],
    );
  }

  Future<void> updateSyncStatus(
    String offlineUuid,
    SyncStatus syncStatus,
  ) async {
    final db = await _db;
    await db.update(
      'local_work_sessions',
      {
        'sync_status': syncStatus.name,
        'updated_at': utcIso(DateTime.now().toUtc()),
      },
      where: 'offline_uuid = ?',
      whereArgs: [offlineUuid],
    );
  }
}
