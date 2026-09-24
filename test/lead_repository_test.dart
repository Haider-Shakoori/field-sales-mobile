import 'package:field_sales_mobile/core/api/api_client.dart';
import 'package:field_sales_mobile/core/db/app_database.dart';
import 'package:field_sales_mobile/core/storage/secret_store.dart';
import 'package:field_sales_mobile/features/leads/lead_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late AppDatabase db;
  late LeadRepository repo;
  setUp(() async {
    db = AppDatabase();
    await db.open();
    repo = LeadRepository(api: ApiClient(SecretStore()), db: db);
  });
  test('lead can be captured and updated offline', () async {
    final id = await repo.createLocal(
      tenantId: 'tenant-a',
      name: 'Prospect',
      phone: '0700',
      estimatedValue: 100,
    );
    await repo.updateLocal(
      tenantId: 'tenant-a',
      offlineUuid: id,
      stage: 'qualified',
      priority: 'high',
    );
    await repo.addActivityLocal(
      tenantId: 'tenant-a',
      leadOfflineUuid: id,
      type: 'call',
      notes: 'Qualified',
    );
    await repo.requestConversion('tenant-a', id);
    final rows = await repo.list('tenant-a');
    expect(rows, hasLength(1));
    expect(rows.first['stage'], 'won');
    expect(rows.first['pending_conversion'], 1);
    expect(await repo.pendingCount('tenant-a'), 2);
  });
}