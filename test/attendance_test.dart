import 'package:field_sales_mobile/core/api/api_exception.dart';
import 'package:field_sales_mobile/core/api/attendance_api.dart';
import 'package:field_sales_mobile/core/api/gps_api.dart';
import 'package:field_sales_mobile/core/location/location_permission_service.dart';
import 'package:field_sales_mobile/core/models/attendance.dart';
import 'package:field_sales_mobile/core/models/privacy_ack.dart';
import 'package:field_sales_mobile/core/storage/app_database.dart';
import 'package:field_sales_mobile/core/storage/gps_point_repository.dart';
import 'package:field_sales_mobile/core/storage/privacy_ack_store.dart';
import 'package:field_sales_mobile/core/storage/work_session_repository.dart';
import 'package:field_sales_mobile/core/sync/connectivity_service.dart';
import 'package:field_sales_mobile/core/sync/sync_repository.dart';
import 'package:field_sales_mobile/core/sync/sync_status.dart';
import 'package:field_sales_mobile/features/attendance/attendance_controller.dart';
import 'package:field_sales_mobile/features/attendance/attendance_sync_service.dart';
import 'package:field_sales_mobile/features/tracking/gps_tracking_config.dart';
import 'package:field_sales_mobile/features/tracking/gps_tracking_service.dart';
import 'package:field_sales_mobile/features/tracking/gps_upload_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_harness.dart';

void main() {
  setUp(initTestDatabase);
  tearDown(tearDownDatabase);

  final sessions = WorkSessionRepository.instance;
  final gpsPoints = GpsPointRepository.instance;
  final queue = SyncQueueRepository.instance;

  group('ATTENDANCE — local work session repository', () {
    test(
      'start stores the session and enqueues attendance-start atomically',
      () async {
        final session = await sessions.startSession(
          latitude: 34.5553,
          longitude: 69.2075,
          accuracy: 8,
          privacyAckAt: '2026-01-15T07:59:00Z',
        );

        expect(session.offlineUuid, isNotEmpty);
        expect(session.status, WorkSessionStatus.active);
        expect(await sessions.activeSession(), isNotNull);

        final entries = await queue.next(entityType: 'attendance');
        expect(entries, hasLength(1));
        expect(entries.single.entityUuid, session.offlineUuid);
        expect(entries.single.action, WorkSessionRepository.startAction);
        expect(entries.single.payload['offline_uuid'], session.offlineUuid);
        expect(entries.single.payload['latitude'], 34.5553);
        expect(entries.single.payload['accuracy'], 8);
        expect(
          entries.single.priority,
          WorkSessionRepository.attendancePriority,
        );
      },
    );

    test('duplicate local start is prevented', () async {
      await sessions.startSession(latitude: 34.5, longitude: 69.2);

      await expectLater(
        sessions.startSession(latitude: 34.6, longitude: 69.3),
        throwsA(isA<ActiveSessionExistsException>()),
      );

      final rows = await DbAsserts.query('SELECT * FROM local_work_sessions');
      expect(rows, hasLength(1));
      expect(await queue.next(entityType: 'attendance'), hasLength(1));
    });

    test(
      'start rolls back the session when the outbox enqueue fails',
      () async {
        await _blockQueueInserts();

        await expectLater(
          sessions.startSession(latitude: 34.5, longitude: 69.2),
          throwsA(isA<Exception>()),
        );

        expect(await sessions.activeSession(), isNull);
        expect(
          await DbAsserts.query('SELECT * FROM local_work_sessions'),
          isEmpty,
        );

        await _unblockQueueInserts();
        expect(await queue.next(entityType: 'attendance'), isEmpty);
      },
    );

    test('end closes the SAME session and enqueues attendance-end', () async {
      final started = await sessions.startSession(
        latitude: 34.5553,
        longitude: 69.2075,
      );

      final ended = await sessions.endSession(
        session: started,
        latitude: 34.56,
        longitude: 69.21,
        accuracy: 6,
      );

      expect(ended.offlineUuid, started.offlineUuid);
      expect(ended.status, WorkSessionStatus.completed);
      expect(ended.endLatitude, 34.56);
      expect(ended.duration, isNotNull);

      final rows = await DbAsserts.query('SELECT * FROM local_work_sessions');
      expect(rows, hasLength(1));

      final entries = await queue.next(entityType: 'attendance');
      expect(entries, hasLength(2));
      expect(entries.first.action, WorkSessionRepository.startAction);
      expect(entries.last.action, WorkSessionRepository.endAction);
      expect(entries.last.entityUuid, started.offlineUuid);
    });

    test('end rolls back when the outbox enqueue fails', () async {
      final started = await sessions.startSession(
        latitude: 34.5553,
        longitude: 69.2075,
      );
      await _blockQueueInserts();

      await expectLater(
        sessions.endSession(
          session: started,
          latitude: 34.56,
          longitude: 69.21,
        ),
        throwsA(isA<Exception>()),
      );

      final active = await sessions.activeSession();
      expect(active, isNotNull);
      expect(active!.endTime, isNull);
      await _unblockQueueInserts();
    });

    test('active session survives a fresh repository read (reload)', () async {
      final started = await sessions.startSession(
        latitude: 34.5553,
        longitude: 69.2075,
      );

      final reloaded = await sessions.activeSession();
      expect(reloaded!.offlineUuid, started.offlineUuid);
      expect(reloaded.syncStatus, SyncStatus.pending);

      final byUuid = await sessions.byOfflineUuid(started.offlineUuid);
      expect(byUuid, isNotNull);
    });

    test('attachServerSession records the server id and sync state', () async {
      final started = await sessions.startSession(
        latitude: 34.5,
        longitude: 69.2,
      );
      await sessions.attachServerSession(started.offlineUuid, 100);

      final reloaded = await sessions.byOfflineUuid(started.offlineUuid);
      expect(reloaded!.serverId, 100);
      expect(reloaded.syncStatus, SyncStatus.synced);
    });

    test('recent history is newest first', () async {
      final first = await sessions.startSession(
        latitude: 34.5,
        longitude: 69.2,
        startedAt: DateTime.utc(2026, 1, 14, 8),
      );
      await sessions.endSession(
        session: first,
        latitude: 34.5,
        longitude: 69.2,
        endedAt: DateTime.utc(2026, 1, 14, 17),
      );
      await sessions.startSession(
        latitude: 34.5,
        longitude: 69.2,
        startedAt: DateTime.utc(2026, 1, 15, 8),
      );

      final history = await sessions.recent();
      expect(history, hasLength(2));
      expect(history.first.startTime.day, 15);
      expect(history.last.startTime.day, 14);
    });
  });

  group('ATTENDANCE — privacy acknowledgement', () {
    test(
      'persists acknowledgement with policy version and user context',
      () async {
        final store = PrivacyAckStore.instance;
        expect(await store.load(), isNull);

        await store.save(
          GpsPrivacyAcknowledgement(
            acknowledgedAt: DateTime.utc(2026, 1, 15, 8),
            userId: '7',
            tenantId: '3',
            deviceUuid: 'device-1',
            appVersion: '1.0.0',
          ),
        );

        final loaded = await store.load();
        expect(loaded!.policyVersion, kGpsTrackingPolicyVersion);
        expect(loaded.userId, '7');
        expect(loaded.tenantId, '3');
        expect(loaded.syncStatus, 'pending');
        expect(loaded.isSynced, isFalse);
      },
    );
  });

  group('ATTENDANCE — controller offline flows', () {
    test('Start Day requires the privacy acknowledgement first', () async {
      final h = _Harness();
      final controller = h.controller();

      final first = await controller.startDay();
      expect(first.outcome, StartDayOutcome.needsPrivacyAck);
      expect(await sessions.activeSession(), isNull);

      await controller.acknowledgePrivacy();
      final second = await controller.startDay(
        privacyAlreadyAcknowledged: true,
      );
      expect(second.outcome, StartDayOutcome.started);
      expect(second.trackingStarted, isTrue);
      expect(controller.privacyAcknowledged, isTrue);
      expect(controller.activeSession, isNotNull);
    });

    test(
      'offline Start Day commits locally without any network call',
      () async {
        final h = _Harness();
        final controller = h.controller();
        await controller.acknowledgePrivacy();

        final result = await controller.startDay(
          privacyAlreadyAcknowledged: true,
        );
        await pumpEventQueue();

        expect(result.outcome, StartDayOutcome.started);
        expect(controller.hasActiveSession, isTrue);
        expect(controller.isTracking, isTrue);
        expect(h.attendanceRequests, isEmpty);
        expect(h.gpsRequests, isEmpty);

        // The start fix is persisted through the normal quality gate.
        expect(await gpsPoints.pendingCount(), 1);
      },
    );

    test('duplicate Start Day while active reports alreadyActive', () async {
      final h = _Harness();
      final controller = h.controller();
      await controller.acknowledgePrivacy();
      await controller.startDay(privacyAlreadyAcknowledged: true);

      final again = await controller.startDay(privacyAlreadyAcknowledged: true);
      expect(again.outcome, StartDayOutcome.alreadyActive);
      expect(
        await DbAsserts.query('SELECT * FROM local_work_sessions'),
        hasLength(1),
      );
    });

    test(
      'offline End Day closes locally, stops tracking, keeps one session',
      () async {
        final h = _Harness();
        final controller = h.controller();
        await controller.acknowledgePrivacy();
        await controller.startDay(privacyAlreadyAcknowledged: true);
        await pumpEventQueue();
        expect(controller.isTracking, isTrue);

        final result = await controller.endDay();
        await pumpEventQueue();

        expect(result.outcome, EndDayOutcome.ended);
        expect(controller.isTracking, isFalse);
        expect(controller.activeSession, isNull);
        expect(controller.completedToday, isNotNull);
        expect(
          await DbAsserts.query('SELECT * FROM local_work_sessions'),
          hasLength(1),
        );
        expect(h.attendanceRequests, isEmpty);
        // Both attendance entries (start + end) are queued for later.
        expect(await queue.next(entityType: 'attendance'), hasLength(2));
      },
    );

    test(
      'End Day falls back to the session start when no fix is available',
      () async {
        final h = _Harness();
        final controller = h.controller();
        await controller.acknowledgePrivacy();
        await controller.startDay(privacyAlreadyAcknowledged: true);

        h.locationSource.current = null;
        final result = await controller.endDay();

        expect(result.outcome, EndDayOutcome.ended);
        expect(result.usedFallback, isTrue);

        final session = await sessions.sessionForToday();
        expect(session!.endLatitude, session.startLatitude);
        expect(session.endLongitude, session.startLongitude);
      },
    );

    test(
      'session restore reloads the active session and resumes tracking',
      () async {
        final h = _Harness();
        final first = h.controller();
        await first.acknowledgePrivacy();
        await first.startDay(privacyAlreadyAcknowledged: true);
        await pumpEventQueue();
        expect(first.isTracking, isTrue);

        // New controller instance simulates an app restart.
        final restarted = h.controller();
        await restarted.restore();
        expect(restarted.restoring, isFalse);
        expect(restarted.activeSession, isNotNull);
        expect(restarted.privacyAcknowledged, isTrue);
        // The last captured point is hydrated from SQLite, not left blank.
        expect(restarted.lastGpsPoint, isNotNull);

        await restarted.setSignedIn(true);
        expect(restarted.isTracking, isTrue);
      },
    );

    test(
      'logout stops tracking but keeps the active session and GPS data',
      () async {
        final h = _Harness();
        final controller = h.controller();
        await controller.acknowledgePrivacy();
        await controller.startDay(privacyAlreadyAcknowledged: true);
        await pumpEventQueue();
        final pendingBefore = await gpsPoints.pendingCount();

        await controller.stopTrackingForLogout();
        await pumpEventQueue();

        expect(controller.isTracking, isFalse);
        expect(controller.activeSession, isNotNull);
        expect(await gpsPoints.pendingCount(), pendingBefore);
      },
    );

    test('revocation stops tracking and preserves unsynced points', () async {
      final h = _Harness();
      final controller = h.controller();
      await controller.acknowledgePrivacy();
      await controller.startDay(privacyAlreadyAcknowledged: true);
      await pumpEventQueue();
      expect(controller.isTracking, isTrue);
      final pendingBefore = await gpsPoints.pendingCount();

      controller.gpsUploader.onAuthorizationLost?.call(
        ApiException(
          status: 401,
          message: 'Session expired',
          code: 'DEVICE_REVOKED',
        ),
      );
      await pumpEventQueue();

      expect(controller.authorizationLost, isTrue);
      expect(controller.isTracking, isFalse);
      expect(controller.pauseReason, TrackingPauseReason.authorizationLost);
      expect(await gpsPoints.pendingCount(), pendingBefore);
    });
  });

  group('ATTENDANCE — permission / services outcomes', () {
    test('location services disabled is reported', () async {
      final h = _Harness()..permissions.serviceEnabled = false;
      final controller = h.controller();
      await controller.acknowledgePrivacy();

      final result = await controller.startDay(
        privacyAlreadyAcknowledged: true,
      );
      expect(result.outcome, StartDayOutcome.servicesDisabled);
      expect(await sessions.activeSession(), isNull);
    });

    test('foreground permission denied is reported', () async {
      final h = _Harness()
        ..permissions.foreground = LocationPermissionStatus.denied
        ..permissions.requestForegroundResult = LocationPermissionStatus.denied;
      final controller = h.controller();
      await controller.acknowledgePrivacy();

      final result = await controller.startDay(
        privacyAlreadyAcknowledged: true,
      );
      expect(result.outcome, StartDayOutcome.permissionDenied);
      expect(await sessions.activeSession(), isNull);
    });

    test(
      'permanently denied permission is reported for a settings action',
      () async {
        final h = _Harness()
          ..permissions.foreground = LocationPermissionStatus.deniedForever;
        final controller = h.controller();
        await controller.acknowledgePrivacy();

        final result = await controller.startDay(
          privacyAlreadyAcknowledged: true,
        );
        expect(result.outcome, StartDayOutcome.permissionPermanentlyDenied);
      },
    );

    test('missing GPS fix blocks Start Day', () async {
      final h = _Harness()..locationSource.current = null;
      final controller = h.controller();
      await controller.acknowledgePrivacy();

      final result = await controller.startDay(
        privacyAlreadyAcknowledged: true,
      );
      expect(result.outcome, StartDayOutcome.locationUnavailable);
      expect(await sessions.activeSession(), isNull);
    });

    test(
      'denied notification permission is surfaced but never blocks',
      () async {
        final h = _Harness()..notificationPermissions.granted = false;
        final controller = h.controller();
        await controller.acknowledgePrivacy();

        final result = await controller.startDay(
          privacyAlreadyAcknowledged: true,
        );

        expect(result.outcome, StartDayOutcome.started);
        expect(result.notificationPermissionGranted, isFalse);
        expect(h.notificationPermissions.requestCalls, 1);
        expect(await sessions.activeSession(), isNotNull);
      },
    );

    test('no tracking can start without an active work session', () async {
      final tracking = GpsTrackingService(
        locationSource: FakeLocationSource(),
        workSessions: sessions,
        gpsPoints: gpsPoints,
        telemetry: FakeDeviceTelemetryProvider(),
      );

      await expectLater(tracking.start(), throwsStateError);
      expect(tracking.isTracking, isFalse);
      tracking.dispose();
    });
  });
}

/// Harness wiring the real repositories/DB with fake providers.
class _Harness {
  _Harness();

  final FakeLocationSource locationSource = FakeLocationSource();
  final FakeLocationPermissionService permissions =
      FakeLocationPermissionService();
  final FakeNotificationPermissionService notificationPermissions =
      FakeNotificationPermissionService();

  final List<RecordedRequest> attendanceRequests = [];
  final List<RecordedRequest> gpsRequests = [];

  late final RecordingApiClient attendanceClient = RecordingApiClient(
    handler: (request) async {
      attendanceRequests.add(request);
      throw ApiException(status: 0, message: 'offline', code: 'NETWORK');
    },
  );

  late final RecordingApiClient gpsClient = RecordingApiClient(
    handler: (request) async {
      gpsRequests.add(request);
      throw ApiException(status: 0, message: 'offline', code: 'NETWORK');
    },
  );

  late final ConnectivityService connectivity = ConnectivityService();

  AttendanceController controller() {
    final tracking = GpsTrackingService(
      locationSource: locationSource,
      workSessions: WorkSessionRepository.instance,
      gpsPoints: GpsPointRepository.instance,
      telemetry: FakeDeviceTelemetryProvider(),
      config: const GpsTrackingConfig(),
    );
    final uploader = GpsUploadService(
      gpsPoints: GpsPointRepository.instance,
      gpsApi: GpsApi(apiClient: gpsClient),
      connectivity: connectivity,
    );
    final sync = AttendanceSyncService(
      api: AttendanceApi(apiClient: attendanceClient),
    );
    return AttendanceController(
      workSessions: WorkSessionRepository.instance,
      privacyAcks: PrivacyAckStore.instance,
      permissions: permissions,
      locationSource: locationSource,
      tracking: tracking,
      gpsUpload: uploader,
      attendanceSync: sync,
      connectivity: connectivity,
      secureStorage: FakeSecretStore(installationUuid: 'device-test'),
      notificationPermissions: notificationPermissions,
    );
  }
}

Future<void> _blockQueueInserts() async {
  final db = await AppDatabase.instance;
  await db.execute('''
    CREATE TRIGGER block_queue_insert BEFORE INSERT ON sync_queue
    BEGIN SELECT RAISE(ABORT, 'enqueue blocked'); END
  ''');
}

Future<void> _unblockQueueInserts() async {
  final db = await AppDatabase.instance;
  await db.execute('DROP TRIGGER IF EXISTS block_queue_insert');
}
