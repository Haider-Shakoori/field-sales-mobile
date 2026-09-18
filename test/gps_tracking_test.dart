import 'package:field_sales_mobile/core/location/location_fix.dart';
import 'package:field_sales_mobile/core/models/gps_point.dart';
import 'package:field_sales_mobile/core/storage/gps_point_repository.dart';
import 'package:field_sales_mobile/core/storage/work_session_repository.dart';
import 'package:field_sales_mobile/features/tracking/gps_quality_filter.dart';
import 'package:field_sales_mobile/features/tracking/gps_tracking_config.dart';
import 'package:field_sales_mobile/features/tracking/gps_tracking_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_harness.dart';

void main() {
  setUp(initTestDatabase);
  tearDown(tearDownDatabase);

  final gpsPoints = GpsPointRepository.instance;
  final sessions = WorkSessionRepository.instance;
  final filter = GpsQualityFilter(const GpsTrackingConfig());
  final baseTime = DateTime.utc(2026, 1, 15, 8);

  LocalGpsPoint previousPoint({
    double latitude = 34.5553,
    double longitude = 69.2075,
    DateTime? at,
  }) => LocalGpsPoint(
    clientUuid: 'prev',
    latitude: latitude,
    longitude: longitude,
    recordedAt: at ?? baseTime,
    createdAt: baseTime,
  );

  group('GPS QUALITY FILTER', () {
    test('accepts a valid fix', () {
      final fix = LocationFix(
        latitude: 34.5553,
        longitude: 69.2075,
        accuracy: 8,
        recordedAt: baseTime,
      );
      expect(filter.rejectionFor(fix), isNull);
    });

    test('rejects coordinates outside valid bounds', () {
      expect(
        filter.rejectionFor(
          LocationFix(latitude: 91, longitude: 69.2, recordedAt: baseTime),
        ),
        GpsRejectionReason.invalidCoordinates,
      );
      expect(
        filter.rejectionFor(
          LocationFix(latitude: 34.5, longitude: -181, recordedAt: baseTime),
        ),
        GpsRejectionReason.invalidCoordinates,
      );
      expect(
        filter.rejectionFor(
          LocationFix(
            latitude: double.nan,
            longitude: 69.2,
            recordedAt: baseTime,
          ),
        ),
        GpsRejectionReason.invalidCoordinates,
      );
    });

    test('rejects empty (0,0) coordinates', () {
      expect(
        filter.rejectionFor(
          LocationFix(latitude: 0, longitude: 0, recordedAt: baseTime),
        ),
        GpsRejectionReason.emptyCoordinates,
      );
    });

    test('rejects unusable accuracy beyond the configured threshold', () {
      expect(
        filter.rejectionFor(
          LocationFix(
            latitude: 34.5,
            longitude: 69.2,
            accuracy: 250,
            recordedAt: baseTime,
          ),
        ),
        GpsRejectionReason.poorAccuracy,
      );
    });

    test('rejects timestamps too far in the future', () {
      final now = DateTime.utc(2026, 1, 15, 8);
      expect(
        filter.rejectionFor(
          LocationFix(
            latitude: 34.5,
            longitude: 69.2,
            recordedAt: now.add(const Duration(minutes: 30)),
          ),
          now: now,
        ),
        GpsRejectionReason.futureTimestamp,
      );
    });

    test('debounces a nearby duplicate within the window', () {
      final fix = LocationFix(
        latitude: 34.55533,
        longitude: 69.20752,
        accuracy: 6,
        recordedAt: baseTime.add(const Duration(seconds: 2)),
      );
      expect(
        filter.rejectionFor(fix, previous: previousPoint()),
        GpsRejectionReason.debounce,
      );
    });

    test('accepts a point at the same place after the debounce window', () {
      final fix = LocationFix(
        latitude: 34.5553,
        longitude: 69.2075,
        accuracy: 6,
        recordedAt: baseTime.add(const Duration(seconds: 30)),
      );
      expect(filter.rejectionFor(fix, previous: previousPoint()), isNull);
    });

    test('accepts a point that moved well beyond the debounce distance', () {
      final fix = LocationFix(
        latitude: 34.5563,
        longitude: 69.2075,
        accuracy: 6,
        recordedAt: baseTime.add(const Duration(seconds: 2)),
      );
      expect(filter.rejectionFor(fix, previous: previousPoint()), isNull);
    });

    test('classifies movement and picks the canonical intervals', () {
      final moving = LocationFix(
        latitude: 34.5,
        longitude: 69.2,
        speed: 2,
        recordedAt: baseTime,
      );
      final stationary = LocationFix(
        latitude: 34.5,
        longitude: 69.2,
        speed: 0,
        recordedAt: baseTime,
      );
      expect(filter.isMoving(moving), isTrue);
      expect(filter.isMoving(stationary), isFalse);
      expect(filter.intervalFor(moving: true), const Duration(seconds: 15));
      expect(filter.intervalFor(moving: false), const Duration(seconds: 60));
    });
  });

  group('GPS PERSISTENCE', () {
    test(
      'valid point persists with a UUID and monotonic sequence number',
      () async {
        final first = await gpsPoints.insertPoint(
          LocalGpsPoint(
            clientUuid: 'uuid-1',
            latitude: 34.5,
            longitude: 69.2,
            accuracy: 5,
            recordedAt: baseTime,
            createdAt: baseTime,
          ),
        );
        final second = await gpsPoints.insertPoint(
          LocalGpsPoint(
            clientUuid: 'uuid-2',
            latitude: 34.6,
            longitude: 69.3,
            recordedAt: baseTime.add(const Duration(seconds: 15)),
            createdAt: baseTime,
          ),
        );

        expect(first.clientUuid, 'uuid-1');
        expect(first.sequenceNumber, 1);
        expect(second.sequenceNumber, 2);

        final pending = await gpsPoints.pending();
        expect(pending.map((p) => p.clientUuid), ['uuid-1', 'uuid-2']);
        expect(await gpsPoints.pendingCount(), 2);
        expect((await gpsPoints.lastPoint())!.clientUuid, 'uuid-2');
      },
    );

    test(
      'inserting the same client_uuid twice conflicts (no duplicate)',
      () async {
        await gpsPoints.insertPoint(
          LocalGpsPoint(
            clientUuid: 'stable-uuid',
            latitude: 34.5,
            longitude: 69.2,
            recordedAt: baseTime,
            createdAt: baseTime,
          ),
        );
        await expectLater(
          gpsPoints.insertPoint(
            LocalGpsPoint(
              clientUuid: 'stable-uuid',
              latitude: 34.5,
              longitude: 69.2,
              recordedAt: baseTime,
              createdAt: baseTime,
            ),
          ),
          throwsA(anything),
        );
        expect(await gpsPoints.pendingCount(), 1);
      },
    );

    test('uploaded and rejected states are preserved distinctly', () async {
      await gpsPoints.insertPoint(_point('a', baseTime));
      await gpsPoints.insertPoint(_point('b', baseTime));
      await gpsPoints.insertPoint(_point('c', baseTime));

      await gpsPoints.markUploaded(
        ['a'],
        batchUuid: 'batch-1',
        uploadedAt: DateTime.utc(2026, 1, 15, 9),
      );
      await gpsPoints.markRejected(
        ['b'],
        batchUuid: 'batch-1',
        error: 'outside bounds',
      );

      expect(await gpsPoints.pendingCount(), 1);
      expect(await gpsPoints.countByStatus(GpsPointSyncStatus.uploaded), 1);
      expect(await gpsPoints.countByStatus(GpsPointSyncStatus.rejected), 1);

      final rejected = (await gpsPoints.pending())
          .map((p) => p.clientUuid)
          .toList();
      expect(rejected, ['c']);

      final rows = await DbAsserts.query(
        "SELECT * FROM local_gps_points WHERE client_uuid = 'b'",
      );
      expect(rows.single['last_error'], 'outside bounds');
      expect(rows.single['sync_status'], 'rejected');
    });

    test('purge removes only old uploaded points', () async {
      await gpsPoints.insertPoint(_point('old', baseTime));
      await gpsPoints.markUploaded(
        ['old'],
        batchUuid: 'batch-old',
        uploadedAt: DateTime.utc(2026, 1, 1),
      );
      await gpsPoints.insertPoint(_point('new', baseTime));

      final removed = await gpsPoints.purgeUploadedBefore(
        DateTime.utc(2026, 1, 10),
      );
      expect(removed, 1);
      expect(await gpsPoints.countByStatus(GpsPointSyncStatus.uploaded), 0);
      expect(await gpsPoints.pendingCount(), 1);
    });
  });

  group('GPS TRACKING SERVICE', () {
    test('refuses to start without an active session', () async {
      final tracking = GpsTrackingService(
        locationSource: FakeLocationSource(),
        workSessions: sessions,
        gpsPoints: gpsPoints,
        telemetry: FakeDeviceTelemetryProvider(),
      );
      await expectLater(tracking.start(), throwsStateError);
      tracking.dispose();
    });

    test(
      'start accepts the initial fix and stores accepted stream fixes',
      () async {
        await sessions.startSession(latitude: 34.5, longitude: 69.2);
        final source = FakeLocationSource();
        final tracking = GpsTrackingService(
          locationSource: source,
          workSessions: sessions,
          gpsPoints: gpsPoints,
          telemetry: FakeDeviceTelemetryProvider(),
        );

        await tracking.start(
          initialFix: LocationFix(
            latitude: 34.5553,
            longitude: 69.2075,
            accuracy: 8,
            recordedAt: baseTime,
          ),
        );
        expect(tracking.isTracking, isTrue);
        expect(await gpsPoints.pendingCount(), 1);

        source.emit(
          LocationFix(
            latitude: 34.60,
            longitude: 69.30,
            accuracy: 9,
            recordedAt: baseTime.add(const Duration(seconds: 20)),
          ),
        );
        await waitForCondition(() => tracking.pendingCount == 2);

        expect(await gpsPoints.pendingCount(), 2);
        expect(tracking.lastAcceptedPoint, isNotNull);
        expect(tracking.lastCapturedAt, isNotNull);
        expect(tracking.lastAcceptedPoint!.isMockLocation, isFalse);
        expect(tracking.lastAcceptedPoint!.batteryLevel, 80);
        expect(tracking.lastAcceptedPoint!.networkStatus, 'wifi');

        await tracking.stop();
        expect(tracking.isTracking, isFalse);
        tracking.dispose();
      },
    );

    test(
      'persists the mock-location signal as telemetry (never blocks)',
      () async {
        await sessions.startSession(latitude: 34.5, longitude: 69.2);
        final source = FakeLocationSource();
        final tracking = GpsTrackingService(
          locationSource: source,
          workSessions: sessions,
          gpsPoints: gpsPoints,
          telemetry: FakeDeviceTelemetryProvider(),
        );
        await tracking.start();

        source.emit(
          LocationFix(
            latitude: 34.5553,
            longitude: 69.2075,
            accuracy: 8,
            recordedAt: baseTime,
            isMocked: true,
          ),
        );
        await waitForCondition(
          () => tracking.lastAcceptedPoint?.isMockLocation == true,
        );

        final point = tracking.lastAcceptedPoint!;
        expect(point.isMockLocation, isTrue);
        expect(point.clientUuid, isNotEmpty);
        expect(await gpsPoints.pendingCount(), 1);

        tracking.dispose();
      },
    );

    test('switches to the moving interval when speed rises', () async {
      await sessions.startSession(latitude: 34.5, longitude: 69.2);
      final source = FakeLocationSource();
      final tracking = GpsTrackingService(
        locationSource: source,
        workSessions: sessions,
        gpsPoints: gpsPoints,
        telemetry: FakeDeviceTelemetryProvider(),
      );
      await tracking.start();
      expect(source.subscriptions.last.interval, const Duration(seconds: 60));

      source.emit(
        LocationFix(
          latitude: 34.60,
          longitude: 69.30,
          accuracy: 8,
          speed: 3,
          recordedAt: baseTime.add(const Duration(seconds: 60)),
        ),
      );
      await waitForCondition(() => source.subscriptions.length >= 2);

      expect(source.subscriptions.last.interval, const Duration(seconds: 15));
      tracking.dispose();
    });

    test(
      'restoreLastPoint hydrates the last persisted point after a restart',
      () async {
        await gpsPoints.insertPoint(_point('persisted', baseTime));
        final tracking = GpsTrackingService(
          locationSource: FakeLocationSource(),
          workSessions: sessions,
          gpsPoints: gpsPoints,
          telemetry: FakeDeviceTelemetryProvider(),
        );
        expect(tracking.lastAcceptedPoint, isNull);

        await tracking.restoreLastPoint();

        expect(tracking.lastAcceptedPoint!.clientUuid, 'persisted');
        await tracking.refreshPendingCount();
        expect(tracking.pendingCount, 1);
        tracking.dispose();
      },
    );

    test('stop prevents any further collection', () async {
      await sessions.startSession(latitude: 34.5, longitude: 69.2);
      final source = FakeLocationSource();
      final tracking = GpsTrackingService(
        locationSource: source,
        workSessions: sessions,
        gpsPoints: gpsPoints,
        telemetry: FakeDeviceTelemetryProvider(),
      );
      await tracking.start();
      await tracking.stop();

      source.emit(
        LocationFix(
          latitude: 34.5553,
          longitude: 69.2075,
          accuracy: 8,
          recordedAt: baseTime,
        ),
      );
      await pumpEventQueue();

      expect(await gpsPoints.pendingCount(), 0);
      tracking.dispose();
    });
  });
}

LocalGpsPoint _point(String uuid, DateTime at) => LocalGpsPoint(
  clientUuid: uuid,
  latitude: 34.5,
  longitude: 69.2,
  recordedAt: at,
  createdAt: at,
);
