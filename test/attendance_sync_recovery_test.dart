import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:field_sales_mobile/core/api/api_client.dart';
import 'package:field_sales_mobile/core/db/app_database.dart';
import 'package:field_sales_mobile/core/storage/secret_store.dart';
import 'package:field_sales_mobile/features/attendance/attendance_repository.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.requests);

  final List<RequestOptions> requests;

  ResponseBody _json(Object body, int status) => ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);

    if (options.path.endsWith('/attendance/start')) {
      return _json({
        'success': false,
        'data': null,
        'meta': <String, dynamic>{},
        'error': {
          'message': 'A work session already exists for this local date.',
          'code': 'SESSION_ALREADY_EXISTS',
          'details': {
            'session': {'id': 'server-session-uuid', 'status': 'completed'},
          },
        },
      }, 409);
    }

    if (options.path.endsWith('/attendance/end')) {
      return _json({
        'success': true,
        'data': {
          'id': 'server-session-uuid',
          'uuid': 'server-session-uuid',
          'status': 'completed',
        },
        'meta': <String, dynamic>{},
      }, 200);
    }

    return _json({
      'success': false,
      'data': null,
      'meta': <String, dynamic>{},
      'error': {'message': 'Not found.', 'code': 'NOT_FOUND'},
    }, 404);
  }

  @override
  void close({bool force = false}) {}
}

Future<String> _databasePath() async =>
    p.join(await getDatabasesPath(), 'field_sales.db');

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await deleteDatabase(await _databasePath());
  });

  test(
    'duplicate server session reconciles instead of blocking sync',
    () async {
      const tenantId = 'recovery-tenant';

      final db = AppDatabase();
      await db.open();

      final api = ApiClient(SecretStore());
      final requests = <RequestOptions>[];
      api.dio.httpClientAdapter = _StubAdapter(requests);

      final attendance = AttendanceRepository(api: api, db: db);

      final uuid = await attendance.start(
        tenantId: tenantId,
        date: '2026-09-20',
        at: DateTime.utc(2026, 9, 20, 7, 33),
        lat: 34.5553,
        lng: 69.2075,
        accuracy: 5,
        source: 'manual',
      );

      final session = await attendance.active(tenantId);
      await attendance.end(
        session: session!,
        at: DateTime.utc(2026, 9, 20, 7, 58),
        lat: 34.5588,
        lng: 69.2120,
        accuracy: 5,
      );

      await attendance.drain(tenantId);

      final queue = await db.db.query(
        'sync_queue',
        where: 'tenant_id=?',
        whereArgs: [tenantId],
        orderBy: 'priority ASC',
      );

      expect(queue.map((row) => row['action']).toList(), ['start', 'end']);
      expect(queue.every((row) => row['status'] == 'synced'), isTrue);
      expect(queue.every((row) => row['error_message'] == null), isTrue);
      expect(queue.first['server_id'], 'server-session-uuid');

      final sessions = await db.db.query(
        'local_work_sessions',
        where: 'tenant_id=? AND offline_uuid=?',
        whereArgs: [tenantId, uuid],
      );

      expect(sessions.single['sync_status'], 'synced');
      expect(sessions.single['server_id'], 'server-session-uuid');

      expect(requests.map((request) => request.uri.path).toList(), [
        '/api/v1/attendance/start',
        '/api/v1/attendance/end',
      ]);

      await db.db.close();
    },
  );
}
