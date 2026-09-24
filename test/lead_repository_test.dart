import 'package:field_sales_mobile/core/api/api_client.dart';
import 'package:field_sales_mobile/core/db/app_database.dart';
import 'package:field_sales_mobile/core/storage/secret_store.dart';
import 'package:field_sales_mobile/features/leads/lead_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<String> _databasePath() async => p.join(await getDatabasesPath(), 'field_sales.db');

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    await deleteDatabase(await _databasePath());
  });

  test('offline lead stage activity and conversion remain queued safely', () async {
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
    await repository.updateStageLocal(tenantId: 'tenant-a', offlineUuid: uuid, stage: 'qualified');
    await repository.addActivityLocal(tenantId: 'tenant-a', leadOfflineUuid: uuid, type: 'meeting', notes: 'Qualified during field visit.');
    await repository.convertLocal(tenantId: 'tenant-a', offlineUuid: uuid);

    final lead = (await db.db.query('local_leads', where: 'tenant_id=? AND offline_uuid=?', whereArgs: ['tenant-a', uuid])).single;
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
  });
}
