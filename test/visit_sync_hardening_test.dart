import 'dart:io';

import 'package:field_sales_mobile/core/api/api_client.dart';
import 'package:field_sales_mobile/core/api/api_exception.dart';
import 'package:field_sales_mobile/core/db/app_database.dart';
import 'package:field_sales_mobile/core/storage/secret_store.dart';
import 'package:field_sales_mobile/core/sync/sync_retry_store.dart';
import 'package:field_sales_mobile/features/visits/visit_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<String> _databasePath() async =>
    p.join(await getDatabasesPath(), 'field_sales.db');

class _FakeApiClient extends ApiClient {
  _FakeApiClient() : super(SecretStore());

  Map<String, dynamic>? lastMultipartFields;
  Object? postError;

  @override
  Future<dynamic> post(
    String p, {
    Object? data,
    Map<String, String>? headers,
  }) async {
    if (postError != null) throw postError!;
    final values = Map<String, dynamic>.from(data! as Map);
    return {'id': values['client_uuid']};
  }

  @override
  Future<dynamic> postMultipart(
    String p, {
    required String filePath,
    String field = 'photo',
    Map<String, dynamic> fields = const {},
  }) async {
    lastMultipartFields = Map<String, dynamic>.from(fields);
    return {'id': fields['client_uuid']};
  }
}

Future<void> _seedSyncedVisit(
  AppDatabase db, {
  required String tenantId,
  required String visitUuid,
}) async {
  final now = DateTime.utc(2026, 9, 19, 8).toIso8601String();

  await db.db.insert('local_visits', {
    'tenant_id': tenantId,
    'offline_uuid': visitUuid,
    'server_uuid': visitUuid,
    'customer_uuid': 'customer-1',
    'customer_name': 'Customer One',
    'status': 'active',
    'checked_in_at': now,
    'checkin_latitude': 34.5,
    'checkin_longitude': 69.2,
    'checkin_accuracy': 8,
    'sync_status': 'synced',
    'created_at': now,
    'updated_at': now,
  });
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    await deleteDatabase(await _databasePath());
  });

  test('visit photo upload sends stable client UUID', () async {
    final db = AppDatabase();
    await db.open();
    const tenantId = 'tenant-photo';
    const visitUuid = '11111111-1111-4111-8111-111111111111';
    const photoUuid = '22222222-2222-4222-8222-222222222222';

    await _seedSyncedVisit(db, tenantId: tenantId, visitUuid: visitUuid);

    final folder = await Directory.systemTemp.createTemp('field-photo-test');
    final file = File(p.join(folder.path, 'photo.jpg'));
    await file.writeAsBytes([1, 2, 3, 4]);

    await db.db.insert('local_visit_photos', {
      'tenant_id': tenantId,
      'client_uuid': photoUuid,
      'visit_offline_uuid': visitUuid,
      'local_path': file.path,
      'captured_at': DateTime.utc(2026, 9, 19, 8).toIso8601String(),
      'sync_status': 'pending',
      'created_at': DateTime.utc(2026, 9, 19, 8).toIso8601String(),
    });

    final api = _FakeApiClient();
    final repository = VisitRepository(api: api, db: db);

    await repository.syncPending(tenantId);

    expect(api.lastMultipartFields?['client_uuid'], photoUuid);

    final photo = (await db.db.query(
      'local_visit_photos',
      where: 'tenant_id=? AND client_uuid=?',
      whereArgs: [tenantId, photoUuid],
    )).single;

    expect(photo['sync_status'], 'synced');
    expect(photo['server_uuid'], photoUuid);

    await folder.delete(recursive: true);
    await db.db.close();
  });

  test(
    'missing photo blocks only after server confirms it is absent',
    () async {
      final db = AppDatabase();
      await db.open();
      const tenantId = 'tenant-photo';
      const visitUuid = '33333333-3333-4333-8333-333333333333';
      const photoUuid = '44444444-4444-4444-8444-444444444444';

      await _seedSyncedVisit(db, tenantId: tenantId, visitUuid: visitUuid);

      await db.db.insert('local_visit_photos', {
        'tenant_id': tenantId,
        'client_uuid': photoUuid,
        'visit_offline_uuid': visitUuid,
        'local_path': p.join(Directory.systemTemp.path, 'missing-photo.jpg'),
        'captured_at': DateTime.utc(2026, 9, 19, 8).toIso8601String(),
        'sync_status': 'pending',
        'created_at': DateTime.utc(2026, 9, 19, 8).toIso8601String(),
      });

      final api = _FakeApiClient()
        ..postError = ApiException(
          status: 422,
          message: 'The photo field is required.',
          code: 'VALIDATION_ERROR',
          retryable: false,
        );
      final repository = VisitRepository(api: api, db: db);

      await repository.syncPending(tenantId);

      final photo = (await db.db.query(
        'local_visit_photos',
        where: 'tenant_id=? AND client_uuid=?',
        whereArgs: [tenantId, photoUuid],
      )).single;

      expect(photo['sync_status'], 'blocked');

      final issues = await SyncRetryStore(db).issues(tenantId);
      expect(issues, hasLength(1));
      expect(issues.single['entity_type'], 'visit_photo');
      expect(issues.single['status'], 'blocked');

      await db.db.close();
    },
  );
}
