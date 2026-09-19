import 'package:field_sales_mobile/core/api/api_exception.dart';
import 'package:field_sales_mobile/core/db/app_database.dart';
import 'package:field_sales_mobile/core/sync/sync_retry_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<String> _databasePath() async =>
    p.join(await getDatabasesPath(), 'field_sales.db');

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    await deleteDatabase(await _databasePath());
  });

  test('retry store backs off transient failures and blocks permanent ones',
      () async {
    final db = AppDatabase();
    await db.open();
    final retry = SyncRetryStore(db);

    final transient = await retry.recordFailure(
      tenantId: 'tenant-sync',
      entityType: 'order',
      entityUuid: 'order-1',
      error: ApiException(
        status: 503,
        message: 'Service unavailable.',
        retryable: true,
      ),
    );

    expect(transient.blocked, isFalse);
    expect(transient.retryable, isTrue);
    expect(transient.nextRetryAt, isNotNull);
    expect(
      await retry.shouldAttempt(
        tenantId: 'tenant-sync',
        entityType: 'order',
        entityUuid: 'order-1',
      ),
      isFalse,
    );
    expect(
      await retry.shouldAttempt(
        tenantId: 'tenant-sync',
        entityType: 'order',
        entityUuid: 'order-1',
        now: transient.nextRetryAt!.add(const Duration(seconds: 1)),
      ),
      isTrue,
    );

    final permanent = await retry.recordFailure(
      tenantId: 'tenant-sync',
      entityType: 'expense',
      entityUuid: 'expense-1',
      error: ApiException(
        status: 422,
        message: 'Invalid expense.',
        code: 'VALIDATION_ERROR',
        retryable: false,
      ),
    );

    expect(permanent.blocked, isTrue);
    expect(permanent.nextRetryAt, isNull);
    expect(await retry.issueCount('tenant-sync'), 2);
    expect(await retry.blockedCount('tenant-sync'), 1);
    expect(await retry.waitingCount('tenant-sync'), 1);

    await retry.retryAll('tenant-sync');

    expect(
      await retry.shouldAttempt(
        tenantId: 'tenant-sync',
        entityType: 'expense',
        entityUuid: 'expense-1',
      ),
      isTrue,
    );

    await db.db.close();
  });
}
