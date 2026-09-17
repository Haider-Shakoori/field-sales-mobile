import 'package:field_sales_mobile/core/storage/app_database.dart';
import 'package:field_sales_mobile/core/storage/local_first_transaction.dart';
import 'package:field_sales_mobile/core/sync/sync_queue.dart';
import 'package:field_sales_mobile/core/sync/sync_repository.dart';
import 'package:field_sales_mobile/core/sync/sync_status.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_harness.dart';

void main() {
  setUp(initTestDatabase);

  tearDown(tearDownDatabase);

  final repo = SyncQueueRepository.instance;

  QueueEntry entry({
    String uuid = 'e-1',
    String action = 'create',
    int priority = 5,
  }) => QueueEntry(
    entityType: 'order',
    entityUuid: uuid,
    action: action,
    payload: {'total': 12.5, 'customer': 'c-9'},
    priority: priority,
  );

  group('OUTBOX — enqueue + read', () {
    test('enqueues and reads pending entries in priority order', () async {
      await repo.enqueue(entry(uuid: 'low', priority: 5));
      await repo.enqueue(entry(uuid: 'urgent', priority: 1));

      final next = await repo.next();
      expect(next, hasLength(2));
      expect(next.first.entityUuid, 'urgent');
      expect(next.first.payload['total'], 12.5);

      final counts = await repo.counts();
      expect(counts.pending, 2);
      expect(counts.synced, 0);
      expect(counts.failed, 0);
    });

    test(
      'failed entries are excluded from the drain (retry is Batch 12)',
      () async {
        await repo.enqueue(entry(uuid: 'ok'));
        await repo.enqueue(entry(uuid: 'bad'));

        final before = await repo.next();
        // both queued with the same priority; first enqueued wins FIFO
        expect(before.map((e) => e.entityUuid), ['ok', 'bad']);

        await repo.markFailed(before.first, error: 'rejected');

        final after = await repo.next();
        expect(after.map((e) => e.entityUuid), ['bad']);

        final ok = await _byUuid('ok');
        expect(ok.status, SyncStatus.failed);
        expect(ok.attempts, 1);
      },
    );

    test('pending → syncing → synced flows through the outbox', () async {
      await repo.enqueue(entry());

      var pending = await repo.next();
      expect(pending, hasLength(1));
      await repo.markSyncing(pending.single);

      // syncing entries are intentionally not re-returned for drain.
      expect(await repo.next(), isEmpty);

      final syncing = await _byUuid('e-1');
      expect(syncing.status, SyncStatus.syncing);

      await repo.markSynced(syncing, serverId: '42');
      final synced = await _byUuid('e-1');
      expect(synced.status, SyncStatus.synced);
      expect(synced.serverId, '42');

      final counts = await repo.counts();
      expect(counts.pending, 0);
      expect(counts.synced, 1);
    });

    test(
      'markFailed records the error and does not schedule backoff',
      () async {
        await repo.enqueue(entry(uuid: 'fail-me'));

        final pending = await repo.next();
        expect(pending.single.entityUuid, 'fail-me');
        await repo.markFailed(pending.single, error: 'server said no');

        final failed = await _byUuid('fail-me');
        expect(failed.status, SyncStatus.failed);
        expect(failed.errorMessage, 'server said no');
        // No backoff is scheduled (Batch 12 scope) — nextRetryAt stays null.
        expect(failed.nextRetryAt, isNull);
      },
    );

    test('reset returns a failed entry to pending', () async {
      await repo.enqueue(entry(uuid: 'reset-me'));
      final pendingEntry = (await repo.next()).single;
      await repo.markFailed(pendingEntry, error: 'transient');

      await repo.reset('reset-me');

      final restored = await _byUuid('reset-me');
      expect(restored.status, SyncStatus.pending);
      expect(restored.errorMessage, isNull);
      expect((await repo.next()).single.entityUuid, 'reset-me');
    });
  });

  group('OUTBOX — atomic local-first write', () {
    test('local write + enqueue commit together', () async {
      final result = await LocalFirstTransaction.instance.run<String>(
        localWrite: (txn) async {
          await txn.insert('customers', {
            'id': 5,
            'uuid': 'c-5',
            'name': 'Local Shop',
            'business_name': 'Local Shop',
            'is_active': 1,
          });
          return 'inserted c-5';
        },
        entry: entry(uuid: 'c-5', action: 'create'),
      );

      expect(result, 'inserted c-5');

      final row = await DbAsserts.query(
        'SELECT * FROM customers WHERE id = ?',
        [5],
      );
      expect(row, hasLength(1));
      expect((await repo.next()).single.entityUuid, 'c-5');
    });

    test('a failing local write rolls back the enqueue (no orphan)', () async {
      await expectLater(
        LocalFirstTransaction.instance.run<String>(
          localWrite: (txn) async {
            await txn.insert('customers', {
              'id': 6,
              'uuid': 'c-6',
              'name': 'Orphan',
              'business_name': 'Orphan',
              'is_active': 1,
            });
            throw StateError('local write aborted');
          },
          entry: entry(uuid: 'c-6', action: 'create'),
        ),
        throwsStateError,
      );

      expect(await repo.next(), isEmpty);
      expect(
        await DbAsserts.query('SELECT * FROM customers WHERE id = ?', [6]),
        isEmpty,
      );
    });
  });
}

Future<QueueEntry> _byUuid(String uuid) async {
  final db = await AppDatabase.instance;
  final rows = await db.query(
    'sync_queue',
    where: 'entity_uuid = ?',
    whereArgs: [uuid],
  );
  return QueueEntry.fromRow(rows.single);
}
