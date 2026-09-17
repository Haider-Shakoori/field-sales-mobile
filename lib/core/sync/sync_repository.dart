import 'package:sqflite/sqflite.dart';

import '../storage/app_database.dart';
import 'sync_queue.dart';
import 'sync_status.dart';

/// Persistence for the local-first sync queue.
///
/// Local records are enqueued immediately (offline-first write); [next]
/// reads the pending entries in priority order for the outbox drain. Status
/// flows through `pending` → `syncing` → `synced` / `failed`.
///
/// Batch 6 ships the basic outbox only: enqueue, read pending, mark syncing,
/// mark synced, mark failed. Retry scheduling (exponential backoff, periodic
/// push to `POST /api/v1/sync/push`) is Batch 12 scope and intentionally not
/// implemented here — the queue is kept so the Batch 12 engine can pick it up.
class SyncQueueRepository {
  SyncQueueRepository._();

  static final SyncQueueRepository instance = SyncQueueRepository._();

  Future<Database> get _db => AppDatabase.instance;

  /// Inserts an entry into the outbox. Pass [txn] to enqueue inside the same
  /// transaction as the local write (see LocalFirstTransaction).
  Future<void> enqueue(QueueEntry entry, {DatabaseExecutor? txn}) async {
    if (txn != null) {
      await txn.insert('sync_queue', entry.toRow());
      return;
    }
    final db = await _db;
    await db.insert('sync_queue', entry.toRow());
  }

  /// Returns the next batch of pending entries, ordered by priority then
  /// creation time. Failed and syncing entries are not returned (retry and
  /// resumable drains are Batch 12 behavior).
  Future<List<QueueEntry>> next({int limit = 50}) async {
    final db = await _db;
    final rows = await db.query(
      'sync_queue',
      where: 'status = ?',
      whereArgs: [nameOf(SyncStatus.pending)],
      orderBy: 'priority ASC, created_at ASC',
      limit: limit,
    );
    return rows.map(QueueEntry.fromRow).toList();
  }

  Future<void> markSyncing(QueueEntry entry) async {
    final db = await _db;
    await db.update(
      'sync_queue',
      {'status': nameOf(SyncStatus.syncing), 'updated_at': now},
      where: 'entity_uuid = ?',
      whereArgs: [entry.entityUuid],
    );
  }

  Future<void> markSynced(QueueEntry entry, {String? serverId}) async {
    final db = await _db;
    await db.update(
      'sync_queue',
      {
        'status': nameOf(SyncStatus.synced),
        'server_id': serverId,
        'error_message': null,
        'updated_at': now,
      },
      where: 'entity_uuid = ?',
      whereArgs: [entry.entityUuid],
    );
  }

  /// Marks an entry as failed. Backoff/retry scheduling is Batch 12 scope,
  /// so no `next_retry_at` is computed here — the entry stays failed until a
  /// future batch decides how to requeue it.
  Future<void> markFailed(
    QueueEntry entry, {
    required String error,
    bool retryable = false,
    String? serverUuid,
  }) async {
    final db = await _db;
    await db.update(
      'sync_queue',
      {
        'attempts': entry.attempts + 1,
        'status': nameOf(SyncStatus.failed),
        'error_message': error,
        'server_uuid': serverUuid,
        'updated_at': now,
      },
      where: 'entity_uuid = ?',
      whereArgs: [entry.entityUuid],
    );
  }

  Future<void> reset(String entityUuid) async {
    final db = await _db;
    await db.update(
      'sync_queue',
      {
        'status': nameOf(SyncStatus.pending),
        'error_message': null,
        'updated_at': now,
      },
      where: 'entity_uuid = ?',
      whereArgs: [entityUuid],
    );
  }

  Future<SyncQueueCounts> counts() async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT status, COUNT(*) AS c FROM sync_queue GROUP BY status',
    );
    final byStatus = {
      for (final r in rows) r['status'] as String: r['c'] as int? ?? 0,
    };
    return SyncQueueCounts(
      byStatus[nameOf(SyncStatus.pending)] ?? 0,
      byStatus[nameOf(SyncStatus.synced)] ?? 0,
      byStatus[nameOf(SyncStatus.failed)] ?? 0,
    );
  }
}

String get now => DateTime.now().toIso8601String();
