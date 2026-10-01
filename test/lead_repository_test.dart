import 'package:field_sales_mobile/core/api/api_client.dart';
import 'package:field_sales_mobile/core/db/app_database.dart';
import 'package:field_sales_mobile/core/storage/secret_store.dart';
import 'package:field_sales_mobile/features/leads/lead_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<String> _databasePath() async =>
    p.join(await getDatabasesPath(), 'field_sales.db');

class _LeadApi extends ApiClient {
  _LeadApi() : super(SecretStore());

  final patches = <Map<String, dynamic>>[];

  @override
  Future<dynamic> patch(
    String path, {
    Object? data,
    Map<String, String>? headers,
  }) async {
    final payload = Map<String, dynamic>.from(data as Map);
    patches.add({'path': path, ...payload});
    return {'id': 'lead-server', ...payload};
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    await deleteDatabase(await _databasePath());
  });

  test(
    'offline lead stage activity and conversion remain queued safely',
    () async {
      final db = AppDatabase();
      await db.open();
      final repository = LeadRepository(api: ApiClient(SecretStore()), db: db);

      final uuid = await repository.createLocal(
        tenantId: 'tenant-a',
        name: 'Kabul Prospect',
        contactPerson: 'Ahmad',
        phone: '+93700123456',
        priority: 'high',
        estimatedValue: 5000,
        currency: 'AFN',
      );
      await repository.updateStageLocal(
        tenantId: 'tenant-a',
        offlineUuid: uuid,
        stage: 'qualified',
      );
      await repository.addActivityLocal(
        tenantId: 'tenant-a',
        leadOfflineUuid: uuid,
        type: 'meeting',
        notes: 'Qualified during field visit.',
      );
      await repository.convertLocal(tenantId: 'tenant-a', offlineUuid: uuid);

      final lead = (await db.db.query(
        'local_leads',
        where: 'tenant_id=? AND offline_uuid=?',
        whereArgs: ['tenant-a', uuid],
      )).single;
      final activities = await repository.activities('tenant-a', uuid);

      expect(lead['stage'], 'won');
      expect(lead['probability'], 100);
      expect(lead['sync_status'], 'pending_create');
      expect(lead['pending_conversion'], 1);
      expect(activities, hasLength(1));
      expect(activities.single['sync_status'], 'pending_create');
      expect(await repository.pendingCount('tenant-a'), 2);
      expect(await repository.list('tenant-b'), isEmpty);

      await db.db.close();
    },
  );

  test('offline opportunity edit syncs the full web-parity payload', () async {
    final db = AppDatabase();
    await db.open();
    final api = _LeadApi();
    final repository = LeadRepository(api: api, db: db);

    final uuid = await repository.createLocal(
      tenantId: 'tenant-a',
      name: 'Original Prospect',
      contactPerson: 'Original Contact',
      phone: '+93700000000',
      email: 'old@example.com',
      address: 'Old address',
      source: 'field',
      priority: 'normal',
      estimatedValue: 100,
      currency: 'USD',
      expectedCloseDate: DateTime(2026, 10, 10),
      notes: 'Old notes',
    );

    await db.db.update(
      'local_leads',
      {'server_uuid': 'lead-server', 'sync_status': 'synced'},
      where: 'tenant_id=? AND offline_uuid=?',
      whereArgs: ['tenant-a', uuid],
    );

    await repository.updateOpportunityLocal(
      tenantId: 'tenant-a',
      offlineUuid: uuid,
      name: 'Updated Prospect',
      contactPerson: 'Updated Contact',
      phone: '+93700111111',
      email: null,
      address: 'New address',
      source: 'referral',
      stage: 'lost',
      priority: 'high',
      estimatedValue: null,
      currency: 'AFN',
      expectedCloseDate: null,
      lostReason: 'Decision postponed.',
      notes: null,
    );

    final result = await repository.syncPending('tenant-a');
    expect(result.synced, 1);
    expect(result.failed, 0);
    expect(api.patches, hasLength(1));

    final patch = api.patches.single;
    expect(patch['path'], 'leads/lead-server');
    expect(patch['name'], 'Updated Prospect');
    expect(patch['contact_person'], 'Updated Contact');
    expect(patch['phone'], '+93700111111');
    expect(patch['email'], isNull);
    expect(patch['address'], 'New address');
    expect(patch['source'], 'referral');
    expect(patch['stage'], 'lost');
    expect(patch['priority'], 'high');
    expect(patch['estimated_value'], isNull);
    expect(patch['currency'], 'AFN');
    expect(patch['expected_close_date'], isNull);
    expect(patch['lost_reason'], 'Decision postponed.');
    expect(patch['notes'], isNull);

    await db.db.close();
  });
}
