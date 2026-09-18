import 'package:field_sales_mobile/core/api/api_client.dart';
import 'package:field_sales_mobile/core/api/api_exception.dart';
import 'package:field_sales_mobile/core/api/gps_api.dart';
import 'package:field_sales_mobile/core/models/gps_point.dart';
import 'package:field_sales_mobile/core/storage/gps_point_repository.dart';
import 'package:field_sales_mobile/features/tracking/gps_upload_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_harness.dart';

void main() {
  setUp(initTestDatabase);
  tearDown(tearDownDatabase);

  final gpsPoints = GpsPointRepository.instance;
  final at = DateTime.utc(2026, 1, 15, 8);

  Future<void> seed(int count) async {
    for (var i = 1; i <= count; i++) {
      await gpsPoints.insertPoint(
        LocalGpsPoint(
          clientUuid: 'point-$i',
          latitude: 34.5 + i / 1000,
          longitude: 69.2,
          accuracy: 8,
          batteryLevel: 80,
          networkStatus: 'wifi',
          recordedAt: at.add(Duration(seconds: i)),
          createdAt: at,
        ),
      );
    }
  }

  GpsUploadService buildUploader(
    RecordingApiClient client, {
    bool online = true,
    GpsUploadService Function(GpsUploadService service)? onCreated,
  }) {
    final service = GpsUploadService(
      gpsPoints: gpsPoints,
      gpsApi: GpsApi(apiClient: client),
      connectivity: FakeConnectivityService(online: online),
    );
    onCreated?.call(service);
    return service;
  }

  Map<String, dynamic> aggregate({
    int accepted = 0,
    int rejected = 0,
    int duplicates = 0,
  }) => {
    'accepted': accepted,
    'rejected': rejected,
    'duplicates': duplicates,
    'batch_id': 42,
  };

  group('GPS UPLOADER', () {
    test('uploads in chunks of at most 100 points', () async {
      await seed(150);
      final client = RecordingApiClient(
        handler: (request) async => ApiEnvelope(
          data: aggregate(accepted: (request.body! as Map)['locations'].length),
        ),
      );
      final uploader = buildUploader(client);

      final outcome = await uploader.flush();

      expect(client.requests, hasLength(2));
      expect((client.requests.first.body! as Map)['locations'], hasLength(100));
      expect((client.requests.last.body! as Map)['locations'], hasLength(50));
      expect(outcome.uploaded, 150);
      expect(outcome.batches, 2);
      expect(await gpsPoints.pendingCount(), 0);
      expect(await gpsPoints.countByStatus(GpsPointSyncStatus.uploaded), 150);
    });

    test('marks accepted and duplicate points as uploaded', () async {
      await seed(3);
      final client = RecordingApiClient(
        handler: (request) async =>
            ApiEnvelope(data: aggregate(accepted: 2, duplicates: 1)),
      );
      final uploader = buildUploader(client);

      final outcome = await uploader.flush();

      expect(outcome.uploaded, 2);
      expect(outcome.duplicates, 1);
      expect(await gpsPoints.pendingCount(), 0);
      expect(await gpsPoints.countByStatus(GpsPointSyncStatus.uploaded), 3);
    });

    test(
      'preserves retry identity: same client_uuid, fresh batch_uuid',
      () async {
        await seed(2);
        var attempt = 0;
        final client = RecordingApiClient(
          handler: (request) async {
            attempt++;
            if (attempt == 1) {
              throw ApiException(
                status: 0,
                message: 'network down',
                code: 'NETWORK',
                retryable: true,
              );
            }
            return ApiEnvelope(data: aggregate(accepted: 2));
          },
        );
        final uploader = buildUploader(client);

        final first = await uploader.flush();
        expect(first.error, isNotNull);
        expect(await gpsPoints.pendingCount(), 2);

        final second = await uploader.flush();
        expect(second.error, isNull);
        expect(await gpsPoints.pendingCount(), 0);

        final firstBody = client.requests.first.body! as Map;
        final secondBody = client.requests.last.body! as Map;
        final firstUuids = (firstBody['locations'] as List)
            .map((l) => (l as Map)['client_uuid'])
            .toList();
        final secondUuids = (secondBody['locations'] as List)
            .map((l) => (l as Map)['client_uuid'])
            .toList();
        expect(secondUuids, firstUuids);
        expect(secondBody['batch_uuid'], isNot(firstBody['batch_uuid']));
        expect((client.requests.last.body! as Map)['locations'], hasLength(2));
      },
    );

    test(
      'rejected aggregate keeps points with diagnostics (no silent drop)',
      () async {
        await seed(3);
        final client = RecordingApiClient(
          handler: (request) async =>
              ApiEnvelope(data: aggregate(accepted: 1, rejected: 2)),
        );
        final uploader = buildUploader(client);

        final outcome = await uploader.flush();

        expect(outcome.rejected, 2);
        expect(await gpsPoints.pendingCount(), 0);
        expect(await gpsPoints.countByStatus(GpsPointSyncStatus.rejected), 3);
        final rows = await DbAsserts.query(
          'SELECT * FROM local_gps_points WHERE last_error IS NOT NULL',
        );
        expect(rows, hasLength(3));
        expect(rows.first['last_error'].toString(), contains('partially'));
      },
    );

    test(
      'per-point verdicts map accepted/duplicate/rejected precisely',
      () async {
        await seed(3);
        final client = RecordingApiClient(
          handler: (request) async => ApiEnvelope(
            data: {
              ...aggregate(accepted: 1, rejected: 1, duplicates: 1),
              'accepted_uuids': ['point-1'],
              'duplicate_uuids': ['point-2'],
              'rejected_uuids': ['point-3'],
            },
          ),
        );
        final uploader = buildUploader(client);

        await uploader.flush();

        expect(await gpsPoints.countByStatus(GpsPointSyncStatus.uploaded), 2);
        expect(await gpsPoints.countByStatus(GpsPointSyncStatus.rejected), 1);
        final rejected = (await DbAsserts.query(
          "SELECT * FROM local_gps_points WHERE sync_status = 'rejected'",
        )).single;
        expect(rejected['client_uuid'], 'point-3');
        expect(rejected['last_error'], contains('per-point'));
      },
    );

    test('skips entirely while offline and keeps points pending', () async {
      await seed(2);
      final client = RecordingApiClient(
        handler: (request) async => throw StateError('must not be called'),
      );
      final uploader = buildUploader(client, online: false);

      final outcome = await uploader.flush();

      expect(outcome.skipped, isTrue);
      expect(client.requests, isEmpty);
      expect(await gpsPoints.pendingCount(), 2);
    });

    test(
      'authorization loss reports, stops the drain, keeps points pending',
      () async {
        await seed(2);
        var authLost = 0;
        final client = RecordingApiClient(
          handler: (request) async => throw ApiException(
            status: 401,
            message: 'Session expired',
            code: 'DEVICE_REVOKED',
          ),
        );
        final uploader = buildUploader(client);
        uploader.onAuthorizationLost = (_) => authLost++;

        final outcome = await uploader.flush();

        expect(outcome.authorizationLost, isTrue);
        expect(authLost, 1);
        expect(await gpsPoints.pendingCount(), 2);
      },
    );

    test('request body matches the GPS contract shape', () async {
      await seed(1);
      final client = RecordingApiClient(
        handler: (request) async => ApiEnvelope(data: aggregate(accepted: 1)),
      );
      final uploader = buildUploader(client);

      await uploader.flush();

      final request = client.requests.single;
      expect(request.method, 'POST');
      expect(request.path, '/gps/locations');
      expect(request.idempotencyKey, isNotNull);
      final body = request.body! as Map;
      expect(body['batch_uuid'], request.idempotencyKey);
      final location = (body['locations'] as List).single as Map;
      expect(location['client_uuid'], 'point-1');
      expect(location['latitude'], closeTo(34.501, 0.0001));
      expect(location['recorded_at'], isA<String>());
      expect(location['sequence_number'], 1);
      expect(location['is_mock_location'], isFalse);
      expect(location['network_status'], 'wifi');
    });
  });
}
