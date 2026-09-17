import 'package:sqflite/sqflite.dart';

import '../sync/sync_queue.dart';
import '../sync/sync_repository.dart';
import 'app_database.dart';

/// Atomic local-first write helper.
///
/// Runs [localWrite] and enqueues the matching outbox entry in a SINGLE
/// SQLite transaction: either both the cache write and the queue entry
/// commit, or neither does. This is the core offline-first guarantee — a
/// locally created/edited record is never orphaned from its sync intent.
class LocalFirstTransaction {
  LocalFirstTransaction._();

  static final LocalFirstTransaction instance = LocalFirstTransaction._();

  /// Executes [localWrite] and [entry]'s enqueue atomically, returning the
  /// local write result. Propagates any error without persisting either side.
  Future<T> run<T>({
    required Future<T> Function(DatabaseExecutor txn) localWrite,
    required QueueEntry entry,
  }) async {
    final db = await AppDatabase.instance;
    return db.transaction<T>((txn) async {
      final result = await localWrite(txn);
      await SyncQueueRepository.instance.enqueue(entry, txn: txn);
      return result;
    });
  }
}
