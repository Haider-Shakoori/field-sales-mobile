import 'dart:convert';
import 'dart:io';

import 'package:field_sales_mobile/core/api/api_client.dart';
import 'package:field_sales_mobile/core/db/app_database.dart';
import 'package:field_sales_mobile/core/storage/secret_store.dart';
import 'package:field_sales_mobile/features/visits/visit_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<String> _databasePath() async =>
    p.join(await getDatabasesPath(), 'field_sales.db');

class _VisitFormApi extends ApiClient {
  _VisitFormApi() : super(SecretStore());

  final calls = <String>[];

  @override
  Future<dynamic> post(
    String path, {
    Object? data,
    Map<String, String>? headers,
  }) async {
    calls.add(path);
    final body = data is Map ? Map<String, dynamic>.from(data) : const {};

    if (path == 'visits/check-in') {
      return {
        'id': body['offline_uuid'],
        'route_id': null,
        'is_planned': true,
        'checkin': {'distance_meters': 3.0, 'within_geofence': true},
      };
    }

    if (path.endsWith('/form-submissions')) {
      return {'id': body['offline_uuid']};
    }

    if (path.endsWith('/check-out')) {
      return {
        'id': 'visit-1',
        'route_id': null,
        'is_planned': true,
        'duration_seconds': 600,
        'checkout': {'distance_meters': 4.0, 'within_geofence': true},
      };
    }

    return const {};
  }

  @override
  Future<dynamic> postMultipart(
    String path, {
    required String filePath,
    String field = 'photo',
    Map<String, dynamic> fields = const {},
  }) async {
    calls.add(path);
    return {'id': fields['client_uuid']};
  }
}

Future<void> _seedCustomer(AppDatabase db, String tenantId) async {
  await db.db.insert('customers', {
    'tenant_id': tenantId,
    'uuid': 'customer-1',
    'payload': jsonEncode({
      'id': 'customer-1',
      'name': 'Customer One',
      'branch_id': 'branch-1',
      'territory_id': 'territory-1',
      'route_ids': ['route-1'],
    }),
    'source': 'server',
    'sync_status': 'synced',
    'cached_at': DateTime.now().toUtc().toIso8601String(),
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

  test('database v12 creates visit form tables and indexes', () async {
    final db = AppDatabase();
    await db.open();

    final tables = (await db.db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    )).map((row) => row['name']).toSet();
    final indexes = (await db.db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='index'",
    )).map((row) => row['name']).toSet();

    expect(
      tables,
      containsAll([
        'local_visit_form_templates',
        'local_visit_form_submissions',
      ]),
    );
    expect(
      indexes,
      containsAll([
        'idx_visit_forms_tenant_uuid',
        'idx_visit_form_sub_uuid',
        'idx_visit_form_sub_template',
        'idx_visit_form_sub_sync',
      ]),
    );

    await db.db.close();
  });

  test('required cached form blocks local checkout until saved', () async {
    final db = AppDatabase();
    await db.open();
    const tenantId = 'visit-form-tenant';
    await _seedCustomer(db, tenantId);

    await db.db.insert('local_visit_form_templates', {
      'tenant_id': tenantId,
      'uuid': 'form-1',
      'code': 'AUDIT',
      'name': 'Required Audit',
      'version': 1,
      'required_on_checkout': 1,
      'scope_type': 'all',
      'payload': jsonEncode({
        'id': 'form-1',
        'code': 'AUDIT',
        'name': 'Required Audit',
        'version': 1,
        'required_on_checkout': true,
        'scope': {'type': 'all', 'id': null, 'name': null},
        'questions': [
          {
            'id': 'question-1',
            'label': 'Available?',
            'type': 'yes_no',
            'required': true,
          },
        ],
      }),
      'cached_at': DateTime.now().toUtc().toIso8601String(),
    });

    final now = DateTime.utc(2026, 9, 23, 5);
    await db.db.insert('local_visits', {
      'tenant_id': tenantId,
      'offline_uuid': 'visit-1',
      'customer_uuid': 'customer-1',
      'customer_name': 'Customer One',
      'status': 'active',
      'checked_in_at': now.toIso8601String(),
      'checkin_latitude': 34.5,
      'checkin_longitude': 69.2,
      'checkin_accuracy': 8,
      'sync_status': 'pending_checkin',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });

    final repository = VisitRepository(api: _VisitFormApi(), db: db);
    final visit = (await repository.list(tenantId)).single;

    await expectLater(
      repository.checkOutLocal(
        tenantId: tenantId,
        visit: visit,
        at: now.add(const Duration(minutes: 10)),
        latitude: 34.5001,
        longitude: 69.2001,
        accuracy: 8,
        outcome: 'order_placed',
      ),
      throwsA(isA<StateError>()),
    );

    await repository.saveFormSubmissionLocal(
      tenantId: tenantId,
      visit: visit,
      template: (await repository.applicableForms(
        tenantId,
        customerUuid: 'customer-1',
        visitOfflineUuid: 'visit-1',
      )).single,
      answers: [
        {'question_id': 'question-1', 'value': true},
      ],
    );

    await repository.checkOutLocal(
      tenantId: tenantId,
      visit: visit,
      at: now.add(const Duration(minutes: 10)),
      latitude: 34.5001,
      longitude: 69.2001,
      accuracy: 8,
      outcome: 'order_placed',
    );

    final updated = (await repository.list(tenantId)).single;
    expect(updated['status'], 'completed');

    await db.db.close();
  });

  test('sync uploads photo and form before checkout', () async {
    final db = AppDatabase();
    await db.open();
    const tenantId = 'visit-form-sync';
    await _seedCustomer(db, tenantId);

    final folder = await Directory.systemTemp.createTemp('visit-form-sync');
    final photo = File(p.join(folder.path, 'photo.jpg'));
    await photo.writeAsBytes([1, 2, 3]);

    final now = DateTime.utc(2026, 9, 23, 5);

    await db.db.insert('local_visit_form_templates', {
      'tenant_id': tenantId,
      'uuid': 'form-1',
      'code': 'PHOTO-AUDIT',
      'name': 'Photo Audit',
      'version': 1,
      'required_on_checkout': 1,
      'scope_type': 'route',
      'scope_uuid': 'route-1',
      'payload': jsonEncode({
        'id': 'form-1',
        'code': 'PHOTO-AUDIT',
        'name': 'Photo Audit',
        'version': 1,
        'required_on_checkout': true,
        'scope': {'type': 'route', 'id': 'route-1', 'name': 'Route One'},
        'questions': [
          {
            'id': 'question-photo',
            'label': 'Shelf photo',
            'type': 'photo',
            'required': true,
          },
        ],
      }),
      'cached_at': now.toIso8601String(),
    });

    await db.db.insert('local_visits', {
      'tenant_id': tenantId,
      'offline_uuid': 'visit-1',
      'customer_uuid': 'customer-1',
      'customer_name': 'Customer One',
      'status': 'completed',
      'outcome': 'order_placed',
      'checked_in_at': now.toIso8601String(),
      'checked_out_at': now.add(const Duration(minutes: 10)).toIso8601String(),
      'checkin_latitude': 34.5,
      'checkin_longitude': 69.2,
      'checkin_accuracy': 8,
      'checkout_latitude': 34.5001,
      'checkout_longitude': 69.2001,
      'checkout_accuracy': 8,
      'sync_status': 'pending_checkin',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });

    await db.db.insert('local_visit_photos', {
      'tenant_id': tenantId,
      'client_uuid': 'photo-1',
      'visit_offline_uuid': 'visit-1',
      'local_path': photo.path,
      'captured_at': now.add(const Duration(minutes: 3)).toIso8601String(),
      'sync_status': 'pending',
      'created_at': now.toIso8601String(),
    });

    await db.db.insert('local_visit_form_submissions', {
      'tenant_id': tenantId,
      'offline_uuid': 'submission-1',
      'visit_offline_uuid': 'visit-1',
      'template_uuid': 'form-1',
      'template_version': 1,
      'template_name': 'Photo Audit',
      'answers_json': jsonEncode([
        {'question_id': 'question-photo', 'value': 'photo-1'},
      ]),
      'submitted_at': now.add(const Duration(minutes: 5)).toIso8601String(),
      'sync_status': 'pending',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });

    final api = _VisitFormApi();
    final repository = VisitRepository(api: api, db: db);

    final result = await repository.syncPending(tenantId);

    expect(result.failed, 0);
    expect(api.calls, [
      'visits/check-in',
      'visits/visit-1/photos',
      'visits/visit-1/form-submissions',
      'visits/visit-1/check-out',
    ]);

    final visit = (await db.db.query(
      'local_visits',
      where: 'tenant_id=? AND offline_uuid=?',
      whereArgs: [tenantId, 'visit-1'],
    )).single;
    final submission = (await db.db.query(
      'local_visit_form_submissions',
      where: 'tenant_id=? AND offline_uuid=?',
      whereArgs: [tenantId, 'submission-1'],
    )).single;

    expect(visit['sync_status'], 'synced');
    expect(submission['sync_status'], 'synced');

    await folder.delete(recursive: true);
    await db.db.close();
  });
}
