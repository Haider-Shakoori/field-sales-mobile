import 'package:field_sales_mobile/core/api/api_client.dart';
import 'package:field_sales_mobile/core/api/attendance_api.dart';
import 'package:field_sales_mobile/core/api/gps_api.dart';
import 'package:field_sales_mobile/core/models/gps_point.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_harness.dart';

void main() {
  group('API MAPPING — attendance', () {
    test('start posts the contract body and parses the session', () async {
      final client = RecordingApiClient(
        handler: (request) async => ApiEnvelope(
          data: {
            'id': 100,
            'user_id': 5,
            'status': 'active',
            'started_at': '2026-01-15T08:00:00Z',
            'start_location': {'latitude': 34.5553, 'longitude': 69.2075},
            'offline_uuid': 'client-uuid-att-001',
          },
        ),
      );
      final api = AttendanceApi(apiClient: client);

      final session = await api.start(
        offlineUuid: 'client-uuid-att-001',
        latitude: 34.5553,
        longitude: 69.2075,
        accuracy: 10.5,
      );

      expect(client.requests.single.method, 'POST');
      expect(client.requests.single.path, '/attendance/start');
      expect(client.requests.single.idempotencyKey, 'client-uuid-att-001');
      final body = client.requests.single.body! as Map;
      expect(body['offline_uuid'], 'client-uuid-att-001');
      expect(body['accuracy'], 10.5);
      expect(session.id, 100);
      expect(session.status, 'active');
      expect(session.startedAt, DateTime.utc(2026, 1, 15, 8));
      expect(session.startLocation!.latitude, closeTo(34.5553, 0.00001));
    });

    test('end posts coordinates and parses duration', () async {
      final client = RecordingApiClient(
        handler: (request) async => ApiEnvelope(
          data: {
            'id': 100,
            'status': 'completed',
            'started_at': '2026-01-15T08:00:00Z',
            'ended_at': '2026-01-15T17:00:00Z',
            'duration_hours': 9.0,
            'end_location': {'latitude': 34.56, 'longitude': 69.21},
          },
        ),
      );
      final api = AttendanceApi(apiClient: client);

      final session = await api.end(
        latitude: 34.56,
        longitude: 69.21,
        accuracy: 8.2,
        sessionOfflineUuid: 'client-uuid-att-001',
      );

      expect(client.requests.single.path, '/attendance/end');
      expect(client.requests.single.idempotencyKey, 'client-uuid-att-001:end');
      expect(session.status, 'completed');
      expect(session.durationHours, 9.0);
      expect(session.endLocation!.longitude, closeTo(69.21, 0.00001));
    });

    test('today returns null when the server has no session', () async {
      final client = RecordingApiClient(
        handler: (request) async => const ApiEnvelope(data: null),
      );
      final api = AttendanceApi(apiClient: client);

      expect(await api.today(), isNull);
    });

    test('history parses the paginated list', () async {
      final client = RecordingApiClient(
        handler: (request) async => ApiEnvelope(
          data: [
            {
              'id': 100,
              'status': 'completed',
              'started_at': '2026-01-15T08:00:00Z',
              'ended_at': '2026-01-15T17:00:00Z',
              'duration_hours': 9.0,
            },
            {
              'id': 99,
              'status': 'completed',
              'started_at': '2026-01-14T08:15:00Z',
              'ended_at': '2026-01-14T16:45:00Z',
              'duration_hours': 8.5,
            },
          ],
          meta: {'page': 1, 'per_page': 25, 'total': 30, 'last_page': 2},
        ),
      );
      final api = AttendanceApi(apiClient: client);

      final history = await api.history();

      expect(client.requests.single.path, '/attendance/history');
      expect(history, hasLength(2));
      expect(history.first.id, 100);
      expect(history.last.durationHours, 8.5);
    });
  });

  group('API MAPPING — GPS batch', () {
    LocalGpsPoint point(String uuid) => LocalGpsPoint(
      clientUuid: uuid,
      latitude: 34.5,
      longitude: 69.2,
      accuracy: 8,
      recordedAt: DateTime.utc(2026, 1, 15, 8),
      sequenceNumber: 1,
      createdAt: DateTime.utc(2026, 1, 15, 8),
    );

    test(
      'posts batch_uuid plus locations and parses aggregate counts',
      () async {
        final client = RecordingApiClient(
          handler: (request) async => ApiEnvelope(
            data: {
              'accepted': 1,
              'rejected': 0,
              'duplicates': 1,
              'batch_id': 12345,
            },
          ),
        );
        final api = GpsApi(apiClient: client);

        final result = await api.uploadBatch(
          batchUuid: 'batch-1',
          points: [point('gps-1'), point('gps-2')],
        );

        expect(client.requests.single.method, 'POST');
        expect(client.requests.single.path, '/gps/locations');
        expect(client.requests.single.idempotencyKey, 'batch-1');
        final body = client.requests.single.body! as Map;
        expect(body['batch_uuid'], 'batch-1');
        expect((body['locations'] as List), hasLength(2));
        expect(result.accepted, 1);
        expect(result.duplicates, 1);
        expect(result.batchId, 12345);
        expect(result.uploadedCount, 2);
        expect(result.fullyUploaded, isTrue);
      },
    );

    test('parses optional per-point verdict lists', () async {
      final client = RecordingApiClient(
        handler: (request) async => ApiEnvelope(
          data: {
            'accepted': 1,
            'rejected': 1,
            'duplicates': 0,
            'accepted_uuids': ['gps-1'],
            'rejected_uuids': ['gps-2'],
          },
        ),
      );
      final api = GpsApi(apiClient: client);

      final result = await api.uploadBatch(
        batchUuid: 'batch-2',
        points: [point('gps-1'), point('gps-2')],
      );

      expect(result.hasPerPointVerdicts, isTrue);
      expect(result.acceptedUuids, ['gps-1']);
      expect(result.rejectedUuids, ['gps-2']);
    });

    test('rejects batches over the 100 point contract limit', () async {
      final api = GpsApi(
        apiClient: RecordingApiClient(
          handler: (request) async => throw StateError('must not be called'),
        ),
      );

      await expectLater(
        api.uploadBatch(
          batchUuid: 'too-big',
          points: List.generate(101, (i) => point('p-$i')),
        ),
        throwsArgumentError,
      );
    });
  });
}
