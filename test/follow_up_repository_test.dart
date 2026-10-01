import 'package:field_sales_mobile/core/api/api_client.dart';
import 'package:field_sales_mobile/core/db/app_database.dart';
import 'package:field_sales_mobile/core/storage/secret_store.dart';
import 'package:field_sales_mobile/core/sync/connectivity_gate.dart';
import 'package:field_sales_mobile/features/followups/follow_up_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _OnlineGate extends ConnectivityGate {
  @override
  Future<bool> isOnline() async => true;

  @override
  Stream<bool> get statusChanges => const Stream.empty();
}

class _FakeFollowUpApi extends ApiClient {
  _FakeFollowUpApi() : super(SecretStore());

  final List<Map<String, dynamic>> rows = [];
  final List<String> calls = [];

  @override
  Future<dynamic> post(
    String path, {
    Object? data,
    Map<String, String>? headers,
  }) async {
    calls.add('POST $path');
    final payload = Map<String, dynamic>.from(data! as Map);
    final row = <String, dynamic>{
      'id': payload['offline_uuid'],
      'customer_id': path.split('/')[1],
      'customer_name': 'Test Customer',
      'type': payload['type'],
      'priority': payload['priority'],
      'status': 'pending',
      'due_at': payload['due_at'],
      'notes': payload['notes'],
      'completed_at': null,
      'completion_note': null,
      'created_at': '2026-10-01T10:00:00Z',
      'updated_at': '2026-10-01T10:00:00Z',
    };
    rows.removeWhere((item) => item['id'] == row['id']);
    rows.add(row);
    return row;
  }

  @override
  Future<dynamic> patch(
    String path, {
    Object? data,
    Map<String, String>? headers,
  }) async {
    calls.add('PATCH $path');
    final payload = Map<String, dynamic>.from(data! as Map);
    final id = path.split('/')[1];
    final index = rows.indexWhere((item) => item['id'] == id);
    final current = Map<String, dynamic>.from(rows[index]);
    current['status'] = payload['status'];
    current['completion_note'] = payload['completion_note'];
    current['completed_at'] = payload['status'] == 'completed'
        ? '2026-10-01T11:00:00Z'
        : null;
    current['updated_at'] = '2026-10-01T11:00:00Z';
    rows[index] = current;
    return current;
  }

  @override
  Future<ApiEnvelope> getEnvelope(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    calls.add('GET $path');
    return ApiEnvelope(
      data: rows.map(Map<String, dynamic>.from).toList(),
      meta: const {'current_page': 1, 'last_page': 1},
    );
  }
}

Future<String> _databasePath() async =>
    p.join(await getDatabasesPath(), 'field_sales.db');

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    await deleteDatabase(await _databasePath());
    ConnectivityGate.instance = _OnlineGate();
  });

  tearDown(() {
    ConnectivityGate.instance = ConnectivityGate();
  });

  test('database v21 contains tenant-scoped follow-up storage', () async {
    final db = AppDatabase();
    await db.open();

    final tables = await db.db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' "
      "AND name='local_customer_follow_ups'",
    );
    expect(AppDatabase.version, 21);
    expect(tables, hasLength(1));

    await db.db.close();
  });

  test('offline create and completion synchronize idempotently', () async {
    final db = AppDatabase();
    await db.open();
    final api = _FakeFollowUpApi();
    final repository = FollowUpRepository(api: api, db: db);
    const tenantId = 'tenant-followup-test';

    final uuid = await repository.createLocal(
      tenantId: tenantId,
      customer: const {'id': 'customer-1', 'name': 'Test Customer'},
      type: 'payment',
      priority: 'high',
      dueAt: DateTime.utc(2026, 10, 2, 8),
      notes: 'Collect overdue balance.',
    );

    await repository.updateStatusLocal(
      tenantId: tenantId,
      offlineUuid: uuid,
      status: 'completed',
      completionNote: 'Paid in full.',
    );

    final before = (await db.db.query(
      'local_customer_follow_ups',
      where: 'tenant_id=? AND offline_uuid=?',
      whereArgs: [tenantId, uuid],
    )).single;
    expect(before['status'], 'completed');
    expect(before['sync_status'], 'pending_create');

    final result = await repository.syncPending(tenantId);
    expect(result.synced, 1);
    expect(result.failed, 0);
    expect(api.calls, contains('POST customers/customer-1/follow-ups'));
    expect(api.calls, contains('PATCH follow-ups/$uuid/status'));

    final after = (await db.db.query(
      'local_customer_follow_ups',
      where: 'tenant_id=? AND offline_uuid=?',
      whereArgs: [tenantId, uuid],
    )).single;
    expect(after['server_uuid'], uuid);
    expect(after['status'], 'completed');
    expect(after['completion_note'], 'Paid in full.');
    expect(after['sync_status'], 'synced');
    expect(await repository.pendingCount(tenantId), 0);

    await db.db.close();
  });

  test('server-assigned follow-ups refresh into local cache', () async {
    final db = AppDatabase();
    await db.open();
    final api = _FakeFollowUpApi()
      ..rows.add({
        'id': 'server-followup-1',
        'customer_id': 'customer-2',
        'customer_name': 'Assigned Customer',
        'type': 'visit',
        'priority': 'normal',
        'status': 'pending',
        'due_at': '2026-10-03T08:00:00Z',
        'notes': 'Check display stock.',
        'completed_at': null,
        'completion_note': null,
        'created_at': '2026-10-01T09:00:00Z',
        'updated_at': '2026-10-01T09:00:00Z',
      });
    final repository = FollowUpRepository(api: api, db: db);

    await repository.refresh('tenant-followup-test');
    final rows = await repository.list('tenant-followup-test');

    expect(rows, hasLength(1));
    expect(rows.single['offline_uuid'], 'server-followup-1');
    expect(rows.single['customer_name'], 'Assigned Customer');
    expect(rows.single['status'], 'pending');
    expect(rows.single['sync_status'], 'synced');

    await db.db.close();
  });
}
