import 'package:sqflite/sqflite.dart';

import '../storage/app_database.dart';
import '../sync/sync_status.dart';
import 'sync_queue.dart';
import 'sync_repository.dart';

/// Flushes the local syncing queue via the sync gateway and logs the outcome.
///
/// Batch 6 keeps the outbox ([SyncQueueRepository]) fully functional but does
/// NOT transmit anything: the Batch 12 sync endpoint (`POST /api/v1/sync/push`)
/// is not implemented in the backend, so `SyncEngine.deferred` is what the app
/// is wired to. The drain pipeline (read → [markSyncing] → resolve → synced /
/// failed) is exercised directly by the OUTBOX tests; a future batch wires a
/// real transport into the injectable [push] and re-enables periodic draining.
class SyncEngine {
  SyncEngine({required this.push});

  /// Non-transmitting engine: the server endpoint for outbox push does not
  /// exist yet (Batch 12), so any drain attempt fails fast with a clear error
  /// instead of hitting a nonexistent route.
  SyncEngine.deferred() : push = _deferredPush;

  static Future<List<SyncResult>> _deferredPush(List<QueueEntry> pending) =>
      throw SyncPushException(
        'Outbox push is deferred to Batch 12 — POST /api/v1/sync/push is '
        'not implemented on the server yet.',
      );

  /// Sends a batch of pending entities to the server; resolves each entry to
  /// a [SyncResult] carrying the server id on success or the error/retry
  /// decision on failure.
  final Future<List<SyncResult>> Function(List<QueueEntry> pending) push;

  Future<SyncOutcome> drain() async {
    final db = await AppDatabase.instance;
    final entries = await SyncQueueRepository.instance.next(limit: 50);
    if (entries.isEmpty) {
      return const SyncOutcome(0, 0);
    }

    final started = DateTime.now();
    try {
      for (final entry in entries) {
        await SyncQueueRepository.instance.markSyncing(entry);
      }
      final results = await push(entries);
      var failed = 0;
      for (final item in results) {
        if (item.error != null) {
          failed++;
          await SyncQueueRepository.instance.markFailed(
            item.entry,
            error: item.error!,
            serverUuid: item.serverUuid,
          );
        } else {
          await SyncQueueRepository.instance.markSynced(
            item.entry,
            serverId: item.serverId,
          );
        }
      }
      await _log(db, 'push', entries.length - failed, failed, started);
      return SyncOutcome(entries.length - failed, failed);
    } catch (e) {
      await _log(db, 'push', 0, entries.length, started, error: e.toString());
      throw SyncPushException(e.toString());
    }
  }

  Future<void> _log(
    Database db,
    String dir,
    int ok,
    int failed,
    DateTime started, {
    String? error,
  }) async {
    await db.insert('local_sync_log', {
      'sync_type': 'queue',
      'direction': dir,
      'status': error == null
          ? (failed == 0 ? 'completed' : 'partial')
          : 'failed',
      'records': ok + failed,
      'duration_ms': DateTime.now().difference(started).inMilliseconds,
      'created_at': DateTime.now().toIso8601String(),
    });
    if (error != null) {
      await db.update(
        'local_sync_log',
        {'error_message': error},
        where: 'sync_type = ? AND direction = ?',
        whereArgs: ['queue', dir],
      );
    }
  }
}

class SyncResult {
  SyncResult({required this.entry, this.serverId, this.error, this.serverUuid});

  final QueueEntry entry;
  final String? serverId;
  final String? error;
  final String? serverUuid;
}

class SyncOutcome {
  const SyncOutcome(this.pushed, this.failed);

  final int pushed;
  final int failed;
}

class SyncPushException implements Exception {
  SyncPushException(this.message);

  final String message;

  @override
  String toString() => 'SyncPushException: $message';
}

String nameOf(SyncStatus status) => status.name;
