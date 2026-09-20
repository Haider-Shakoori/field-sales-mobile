import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:field_sales_mobile/core/api/api_client.dart';
import 'package:field_sales_mobile/core/db/app_database.dart';
import 'package:field_sales_mobile/core/storage/secret_store.dart';
import 'package:field_sales_mobile/core/sync/connectivity_gate.dart';
import 'package:field_sales_mobile/features/attendance/attendance_repository.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _OfflineGate extends ConnectivityGate {
  @override
  Future<bool> isOnline() async => false;

  @override
  Stream<bool> get statusChanges => const Stream.empty();
}

class _RecordingAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);

    return ResponseBody.fromString(
      jsonEncode({
        'success': true,
        'data': {'id': 'server-session-uuid', 'uuid': 'server-session-uuid'},
        'meta': <String, dynamic>{},
      }),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
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

  tearDown(() {
    ConnectivityGate.instance = ConnectivityGate();
  });

  test(
    'default gate assumes online when the connectivity plugin is absent',
    () async {
      expect(await ConnectivityGate.instance.isOnline(), isTrue);
    },
  );

  test('offline gate keeps attendance queued without network calls', () async {
    ConnectivityGate.instance = _OfflineGate();

    final db = AppDatabase();
    await db.open();

    final api = ApiClient(SecretStore());
    final adapter = _RecordingAdapter();
    api.dio.httpClientAdapter = adapter;

    final attendance = AttendanceRepository(api: api, db: db);

    await attendance.start(
      tenantId: 'offline-tenant',
      date: '2026-09-20',
      at: DateTime.utc(2026, 9, 20, 7, 33),
      lat: 34.5553,
      lng: 69.2075,
      accuracy: 5,
      source: 'manual',
    );

    await attendance.drain('offline-tenant');

    expect(adapter.requests, isEmpty);

    final queue = await db.db.query('sync_queue');
    expect(queue.single['status'], 'pending');

    final sessions = await db.db.query('local_work_sessions');
    expect(sessions.single['sync_status'], 'pending');

    await db.db.close();
  });
}
