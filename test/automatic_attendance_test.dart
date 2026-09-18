import 'package:field_sales_mobile/core/api/api_exception.dart';
import 'package:field_sales_mobile/core/api/attendance_api.dart';
import 'package:field_sales_mobile/core/api/gps_api.dart';
import 'package:field_sales_mobile/core/location/location_fix.dart';
import 'package:field_sales_mobile/core/location/location_permission_service.dart';
import 'package:field_sales_mobile/core/models/attendance.dart';
import 'package:field_sales_mobile/core/models/attendance_tracking_settings.dart';
import 'package:field_sales_mobile/core/models/gps_point.dart';
import 'package:field_sales_mobile/core/storage/attendance_tracking_settings_repository.dart';
import 'package:field_sales_mobile/core/storage/gps_point_repository.dart';
import 'package:field_sales_mobile/core/storage/privacy_ack_store.dart';
import 'package:field_sales_mobile/core/storage/work_session_repository.dart';
import 'package:field_sales_mobile/core/sync/sync_repository.dart';
import 'package:field_sales_mobile/core/time/tenant_time.dart';
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

  group('MANUAL — safe fallback', () {
    test('no trusted settings means MANUAL and no auto session', () async {
      final h = _AutoHarness(
        settings: null,
        now: DateTime.utc(2026, 9, 18, 10),
      );
      final controller = await h.build(saveSettings: false);

      expect(controller.settings.startMode, WorkSessionStartMode.manual);
      expect(controller.settingsTrusted, isFalse);
      expect(controller.automaticMode, isFalse);
      expect(controller.automaticState, AutomaticPolicyState.manual);
      expect(controller.activeSession, isNull);
      expect(h.scheduler.isScheduled, isFalse);
      expect(h.attendanceRequests, isEmpty);
    });

    test('manual Start Day still creates the session and starts GPS', () async {
      final h = _AutoHarness(
        settings: null,
        now: DateTime.utc(2026, 9, 18, 10),
      );
      final controller = await h.build(saveSettings: false);

      final result = await controller.startDay();

      expect(result.outcome, StartDayOutcome.started);
      expect(result.trackingStarted, isTrue);
      expect(controller.activeSession, isNotNull);
      expect(
        controller.activeSession!.startSource,
        WorkSessionStartSource.manual,
      );
      expect(controller.isTracking, isTrue);
      expect(await gpsPoints.pendingCount(), 1);
    });

    test('manual End Day still stops tracking and completes locally', () async {
      final h = _AutoHarness(
        settings: null,
        now: DateTime.utc(2026, 9, 18, 10),
      );
      final controller = await h.build(saveSettings: false);
      await controller.startDay();

      final result = await controller.endDay();

      expect(result.outcome, EndDayOutcome.ended);
      expect(controller.activeSession, isNull);
      expect(controller.isTracking, isFalse);
    });
  });

  group('AUTOMATIC — start', () {
    test(
      'inside the schedule starts automatically with the same flow',
      () async {
        final h = _AutoHarness(
          settings: const AttendanceTrackingSettings(
            startMode: WorkSessionStartMode.automatic,
            workdayStartTime: '08:00',
            workdayEndTime: '17:00',
            timezone: 'UTC',
          ),
          now: DateTime.utc(2026, 9, 18, 10),
        );
        final controller = await h.build();

        expect(controller.activeSession, isNotNull);
        expect(
          controller.activeSession!.startSource,
          WorkSessionStartSource.automatic,
        );
        expect(controller.isTracking, isTrue);
        expect(controller.automaticState, AutomaticPolicyState.active);

        // Same Start Day flow: the start fix is persisted and the outbox entry
        // uses the standard attendance payload.
        expect(await gpsPoints.pendingCount(), 1);
        final entry = (await queue.next(entityType: 'attendance')).single;
        expect(entry.action, WorkSessionRepository.startAction);
        expect(entry.entityUuid, controller.activeSession!.offlineUuid);
        expect(entry.payload['offline_uuid'], entry.entityUuid);
        expect(entry.payload['latitude'], isNotNull);
      },
    );

    test('before the schedule does not start', () async {
      final h = _AutoHarness(
        settings: _automatic(),
        now: DateTime.utc(2026, 9, 18, 7, 30),
      );
      final controller = await h.build();

      expect(controller.activeSession, isNull);
      expect(
        controller.automaticState,
        AutomaticPolicyState.waitingForSchedule,
      );
      expect(controller.workdayStartLabel, '08:00');
      expect(
        h.scheduler.scheduledDelays.last,
        const Duration(minutes: 30, seconds: 1),
      );
    });

    test('after the schedule does not start', () async {
      final h = _AutoHarness(
        settings: _automatic(),
        now: DateTime.utc(2026, 9, 18, 19),
      );
      final controller = await h.build();

      expect(controller.activeSession, isNull);
      expect(controller.automaticState, AutomaticPolicyState.outsideSchedule);
      expect(h.attendanceRequests, isEmpty);
    });

    test('an existing active session prevents a duplicate start', () async {
      final h = _AutoHarness(
        settings: _automatic(),
        now: DateTime.utc(2026, 9, 18, 7, 30),
      );
      final controller = await h.build();
      final manual = await controller.startDay();
      final firstSession = controller.activeSession!;

      h.clock.value = DateTime.utc(2026, 9, 18, 10);
      await controller.evaluateAutomaticPolicy();

      expect(manual.outcome, StartDayOutcome.started);
      expect(
        await DbAsserts.query('SELECT * FROM local_work_sessions'),
        hasLength(1),
      );
      expect(controller.activeSession!.offlineUuid, firstSession.offlineUuid);
      expect(
        controller.activeSession!.startSource,
        WorkSessionStartSource.manual,
      );
      expect(
        (await controller.startDay()).outcome,
        StartDayOutcome.alreadyActive,
      );
    });

    test(
      'offline auto start creates the local session and outbox entry',
      () async {
        final h = _AutoHarness(settings: _automatic());
        final controller = await h.build();

        expect(h.connectivity.isOnline, isFalse);
        expect(h.attendanceRequests, isEmpty);
        expect(controller.activeSession, isNotNull);
        expect(await queue.next(entityType: 'attendance'), hasLength(1));
        expect(controller.pendingGpsCount, 1);
      },
    );

    test('privacy acknowledgement is required and never bypassed', () async {
      final h = _AutoHarness(settings: _automatic());
      final controller = await h.build(acknowledge: false);

      expect(controller.activeSession, isNull);
      expect(controller.automaticState, AutomaticPolicyState.waitingForPrivacy);
      expect(h.attendanceRequests, isEmpty);

      await controller.acknowledgePrivacy();
      await controller.retryAutomaticStart();

      expect(controller.activeSession, isNotNull);
      expect(controller.automaticState, AutomaticPolicyState.active);
    });

    test(
      'location services disabled prevents auto start without prompting',
      () async {
        final h = _AutoHarness(settings: _automatic());
        h.permissions.serviceEnabled = false;
        final controller = await h.build();

        expect(controller.activeSession, isNull);
        expect(
          controller.automaticState,
          AutomaticPolicyState.waitingForServices,
        );
        expect(h.permissions.requestForegroundCalls, 0);
      },
    );

    test('denied permission prevents auto start without prompting', () async {
      final h = _AutoHarness(settings: _automatic());
      h.permissions.foreground = LocationPermissionStatus.denied;
      final controller = await h.build();

      expect(controller.activeSession, isNull);
      expect(
        controller.automaticState,
        AutomaticPolicyState.waitingForPermission,
      );
      expect(h.permissions.requestForegroundCalls, 0);
    });

    test('unavailable GPS fix does not create a broken session', () async {
      final h = _AutoHarness(settings: _automatic());
      h.locationSource.current = null;
      final controller = await h.build();

      expect(controller.activeSession, isNull);
      expect(
        controller.automaticState,
        AutomaticPolicyState.waitingForLocation,
      );
      expect(
        await DbAsserts.query('SELECT * FROM local_work_sessions'),
        isEmpty,
      );
    });

    test('gpsTrackingEnabled=false blocks automatic start', () async {
      final h = _AutoHarness(settings: _automatic(gpsTrackingEnabled: false));
      final controller = await h.build();

      expect(controller.activeSession, isNull);
      expect(controller.automaticState, AutomaticPolicyState.gpsDisabled);
    });

    test('app resume during the window starts automatically', () async {
      final h = _AutoHarness(
        settings: _automatic(),
        now: DateTime.utc(2026, 9, 18, 7, 30),
      );
      final controller = await h.build();
      expect(controller.activeSession, isNull);

      h.clock.value = DateTime.utc(2026, 9, 18, 8, 5);
      await controller.onAppResumed();

      expect(controller.activeSession, isNotNull);
    });

    test('the boundary timer firing starts automatically', () async {
      final h = _AutoHarness(
        settings: _automatic(),
        now: DateTime.utc(2026, 9, 18, 7, 59),
      );
      final controller = await h.build();
      expect(controller.activeSession, isNull);

      h.clock.value = DateTime.utc(2026, 9, 18, 8, 0);
      h.scheduler.fire();
      await waitForCondition(() => controller.activeSession != null);

      expect(controller.activeSession, isNotNull);
    });

    test('switching MANUAL → AUTOMATIC inside the window starts', () async {
      final h = _AutoHarness(
        settings: null,
        now: DateTime.utc(2026, 9, 18, 10),
      );
      final controller = await h.build(saveSettings: false);
      expect(controller.activeSession, isNull);

      await h.repo.saveTrusted(_automatic(), tenantId: '3');
      await controller.reloadSettings();
      await controller.evaluateAutomaticPolicy();

      expect(controller.activeSession, isNotNull);
      expect(controller.automaticMode, isTrue);
    });

    test('tenant timezone wins over device/UTC time', () async {
      // 12:30 UTC is 13:30 in London on 2026-07-01 (BST), i.e. OUTSIDE the
      // 12:00–13:00 tenant window even though it is inside the same window in
      // UTC/device time.
      final h = _AutoHarness(
        settings: _automatic(
          start: '12:00',
          end: '13:00',
          timezone: 'Europe/London',
        ),
        now: DateTime.utc(2026, 7, 1, 12, 30),
      );
      final controller = await h.build();

      expect(controller.activeSession, isNull);
      expect(controller.automaticState, AutomaticPolicyState.outsideSchedule);
    });

    test('DST-adjusted tenant window starts correctly (BST)', () async {
      // 11:30 UTC is 12:30 in London on 2026-07-01 (BST) — inside the window.
      // A fixed-offset implementation without DST would see 11:30 and skip.
      final h = _AutoHarness(
        settings: _automatic(
          start: '12:00',
          end: '13:00',
          timezone: 'Europe/London',
        ),
        now: DateTime.utc(2026, 7, 1, 11, 30),
      );
      final controller = await h.build();

      expect(controller.activeSession, isNotNull);
      expect(controller.automaticMode, isTrue);
    });

    test('missing/invalid tenant timezone blocks auto start safely', () async {
      final h = _AutoHarness(
        settings: _automatic(timezone: 'Not/AZone'),
        now: DateTime.utc(2026, 9, 18, 10),
      );
      final controller = await h.build();

      expect(controller.activeSession, isNull);
      expect(controller.automaticState, AutomaticPolicyState.missingTimezone);
      expect(h.attendanceRequests, isEmpty);

      // Manual mode keeps working without a tenant zone.
      final manualStart = await controller.startDay();
      expect(manualStart.outcome, StartDayOutcome.started);
    });

    test('automatic does not start again after today is completed', () async {
      final h = _AutoHarness(
        settings: _automatic(),
        now: DateTime.utc(2026, 9, 18, 10),
      );
      final controller = await h.build();
      expect(controller.activeSession, isNotNull);

      // Still inside the tenant window after End Day.
      await controller.endDay();
      await controller.evaluateAutomaticPolicy();

      expect(controller.automaticState, AutomaticPolicyState.completedToday);
      expect(controller.activeSession, isNull);
      expect(
        await DbAsserts.query('SELECT * FROM local_work_sessions'),
        hasLength(1),
      );
    });

    test('manual second Start Day on the same work date is rejected', () async {
      final h = _AutoHarness(
        settings: _manual(),
        now: DateTime.utc(2026, 9, 18, 10),
      );
      final controller = await h.build();

      expect((await controller.startDay()).outcome, StartDayOutcome.started);
      expect((await controller.endDay()).outcome, EndDayOutcome.ended);

      final second = await controller.startDay();
      expect(second.outcome, StartDayOutcome.alreadyCompletedToday);
      expect(
        await DbAsserts.query('SELECT * FROM local_work_sessions'),
        hasLength(1),
      );
      expect(await queue.next(entityType: 'attendance'), hasLength(2));
    });

    test(
      'overnight tenant window starts and auto-ends in tenant time',
      () async {
        final h = _AutoHarness(
          settings: _automatic(
            start: '20:00',
            end: '04:00',
            autoEndSession: true,
            timezone: 'Asia/Kabul',
          ),
          // 16:30 UTC = 21:00 Kabul — inside the overnight window.
          now: DateTime.utc(2026, 9, 18, 16, 30),
        );
        final controller = await h.build();
        expect(controller.activeSession, isNotNull);

        // 00:30 UTC next day = 05:00 Kabul — after the window.
        h.clock.value = DateTime.utc(2026, 9, 19, 0, 30);
        await controller.evaluateAutomaticPolicy();

        expect(controller.activeSession, isNull);
        expect(controller.completedToday, isNotNull);
      },
    );
  });

  group('MANUAL + gpsTrackingEnabled=false', () {
    test('session stays available but continuous GPS stays off', () async {
      final h = _AutoHarness(
        settings: _automatic(gpsTrackingEnabled: false),
        now: DateTime.utc(2026, 9, 18, 10),
      );
      // Automatic cannot start; fall back to the manual flow.
      final controller = await h.build();
      expect(controller.activeSession, isNull);

      final result = await controller.startDay();

      expect(result.outcome, StartDayOutcome.started);
      expect(result.gpsTrackingEnabled, isFalse);
      expect(result.trackingStarted, isFalse);
      expect(controller.activeSession, isNotNull);
      expect(controller.isTracking, isFalse);
      expect(controller.pauseReason, TrackingPauseReason.gpsDisabled);
      expect(await gpsPoints.pendingCount(), 0);
      expect(await queue.next(entityType: 'attendance'), hasLength(1));
    });
  });

  group('AUTOMATIC — end', () {
    test('autoEnd=false leaves the session active after the window', () async {
      final h = _AutoHarness(
        settings: _automatic(autoEndSession: false),
        now: DateTime.utc(2026, 9, 18, 10),
      );
      final controller = await h.build();
      expect(controller.activeSession, isNotNull);

      h.clock.value = DateTime.utc(2026, 9, 18, 18);
      await controller.evaluateAutomaticPolicy();

      expect(controller.activeSession, isNotNull);
      expect(controller.isTracking, isTrue);
    });

    test('autoEnd=true completes the session after the window', () async {
      final h = _AutoHarness(
        settings: _automatic(autoEndSession: true),
        now: DateTime.utc(2026, 9, 18, 10),
      );
      final controller = await h.build();
      expect(controller.activeSession, isNotNull);

      h.clock.value = DateTime.utc(2026, 9, 18, 18);
      await controller.evaluateAutomaticPolicy();

      expect(controller.activeSession, isNull);
      expect(controller.completedToday, isNotNull);
      expect(controller.isTracking, isFalse);
      final pending = await queue.next(entityType: 'attendance');
      expect(pending.map((e) => e.action), containsAll(['start', 'end']));
      expect(
        (await DbAsserts.query('SELECT * FROM local_work_sessions'))
            .single['status'],
        'completed',
      );
    });

    test('offline automatic end persists locally without network', () async {
      final h = _AutoHarness(
        settings: _automatic(autoEndSession: true),
        now: DateTime.utc(2026, 9, 18, 10),
      );
      final controller = await h.build();

      h.clock.value = DateTime.utc(2026, 9, 18, 18);
      await controller.evaluateAutomaticPolicy();

      expect(h.attendanceRequests, isEmpty);
      expect(controller.completedToday!.status, WorkSessionStatus.completed);
      final pending = await queue.next(entityType: 'attendance');
      expect(pending.map((e) => e.action), containsAll(['start', 'end']));
    });

    test('automatic end is idempotent (no duplicate end)', () async {
      final h = _AutoHarness(
        settings: _automatic(autoEndSession: true),
        now: DateTime.utc(2026, 9, 18, 10),
      );
      final controller = await h.build();

      h.clock.value = DateTime.utc(2026, 9, 18, 18);
      await controller.evaluateAutomaticPolicy();
      await controller.evaluateAutomaticPolicy();
      await controller.evaluateAutomaticPolicy();

      final sessionsRows = await DbAsserts.query(
        'SELECT * FROM local_work_sessions',
      );
      expect(sessionsRows, hasLength(1));
      final endEntries = await DbAsserts.query(
        "SELECT * FROM sync_queue WHERE entity_type = 'attendance' AND action = 'end'",
      );
      expect(endEntries, hasLength(1));
      expect((await controller.endDay()).outcome, EndDayOutcome.notActive);
    });

    test('a session started outside the window is not auto-ended', () async {
      final h = _AutoHarness(
        settings: _automatic(autoEndSession: true),
        now: DateTime.utc(2026, 9, 18, 18, 30),
      );
      final controller = await h.build();
      expect(controller.activeSession, isNull);

      final result = await controller.startDay();
      expect(result.outcome, StartDayOutcome.started);

      await controller.evaluateAutomaticPolicy();

      expect(controller.activeSession, isNotNull);
    });

    test('overnight window auto-ends after the morning boundary', () async {
      final h = _AutoHarness(
        settings: _automatic(
          start: '20:00',
          end: '04:00',
          autoEndSession: true,
        ),
        now: DateTime.utc(2026, 9, 18, 21),
      );
      final controller = await h.build();
      expect(controller.activeSession, isNotNull);

      h.clock.value = DateTime.utc(2026, 9, 19, 5);
      await controller.evaluateAutomaticPolicy();

      expect(controller.activeSession, isNull);
      expect(controller.completedToday, isNotNull);
    });
  });

  group('SETTINGS CHANGES', () {
    test('company intervals reach the tracker and adapt on movement', () async {
      final h = _AutoHarness(
        settings: _automatic(moving: 30, stationary: 120),
        now: DateTime.utc(2026, 9, 18, 10),
      );
      final controller = await h.build();
      expect(controller.isTracking, isTrue);
      expect(h.tracking.config.movingInterval, const Duration(seconds: 30));
      expect(
        h.tracking.config.stationaryInterval,
        const Duration(seconds: 120),
      );
      expect(
        h.locationSource.subscriptions.last.interval,
        const Duration(seconds: 120),
      );

      h.locationSource.emit(
        LocationFix(
          latitude: 34.60,
          longitude: 69.30,
          accuracy: 6,
          speed: 3,
          recordedAt: h.clock.now().toUtc(),
        ),
      );
      await waitForCondition(() => h.locationSource.subscriptions.length >= 2);

      expect(
        h.locationSource.subscriptions.last.interval,
        const Duration(seconds: 30),
      );
    });

    test(
      'gpsTrackingEnabled true → false stops GPS but keeps points',
      () async {
        final h = _AutoHarness(
          settings: _automatic(),
          now: DateTime.utc(2026, 9, 18, 10),
        );
        final controller = await h.build();
        expect(controller.isTracking, isTrue);
        final pointsBefore = await gpsPoints.pendingCount();

        await h.repo.saveTrusted(
          _automatic(gpsTrackingEnabled: false),
          tenantId: '3',
        );
        await controller.reloadSettings();
        await pumpEventQueue();

        expect(controller.isTracking, isFalse);
        expect(controller.pauseReason, TrackingPauseReason.gpsDisabled);
        expect(controller.activeSession, isNotNull);
        expect(await gpsPoints.pendingCount(), pointsBefore);
      },
    );

    test(
      'gpsTrackingEnabled false → true resumes for an active session',
      () async {
        final h = _AutoHarness(
          settings: _automatic(gpsTrackingEnabled: false),
          now: DateTime.utc(2026, 9, 18, 10),
        );
        final controller = await h.build();
        await controller.startDay();
        expect(controller.isTracking, isFalse);

        await h.repo.saveTrusted(_automatic(), tenantId: '3');
        await controller.reloadSettings();
        await controller.resumeTracking();

        expect(controller.isTracking, isTrue);
        expect(controller.pauseReason, TrackingPauseReason.none);
      },
    );

    test('AUTOMATIC → MANUAL does not end an active session', () async {
      final h = _AutoHarness(settings: _automatic());
      final controller = await h.build();
      final offlineUuid = controller.activeSession!.offlineUuid;
      expect(controller.isTracking, isTrue);

      await h.repo.saveTrusted(_manual(), tenantId: '3');
      await controller.reloadSettings();
      await controller.evaluateAutomaticPolicy();

      expect(controller.activeSession, isNotNull);
      expect(controller.activeSession!.offlineUuid, offlineUuid);
      expect(
        controller.activeSession!.startSource,
        WorkSessionStartSource.automatic,
      );
      expect(controller.isTracking, isTrue);
      expect(controller.automaticMode, isFalse);
    });
  });

  group('RESTORE', () {
    test(
      'active session restores in MANUAL mode and tracking resumes',
      () async {
        await sessions.startSession(latitude: 34.5, longitude: 69.2);
        final h = _AutoHarness(settings: _manual());
        final controller = await h.build();

        expect(controller.activeSession, isNotNull);
        expect(controller.isTracking, isTrue);
        expect(controller.automaticState, AutomaticPolicyState.active);
      },
    );

    test(
      'active session restores in AUTOMATIC mode without duplicates',
      () async {
        await sessions.startSession(latitude: 34.5, longitude: 69.2);
        final h = _AutoHarness(settings: _automatic());
        final controller = await h.build();

        expect(
          await DbAsserts.query('SELECT * FROM local_work_sessions'),
          hasLength(1),
        );
        expect(
          controller.activeSession!.startSource,
          WorkSessionStartSource.manual,
        );
        expect(controller.isTracking, isTrue);
      },
    );

    test('tracking resumes only when permitted', () async {
      await sessions.startSession(latitude: 34.5, longitude: 69.2);
      final h = _AutoHarness(settings: _manual());
      h.permissions.foreground = LocationPermissionStatus.denied;
      final controller = await h.build();

      expect(controller.activeSession, isNotNull);
      expect(controller.isTracking, isFalse);
      expect(controller.pauseReason, TrackingPauseReason.permissionMissing);
    });

    test(
      'restored active session does not track when gps policy is disabled',
      () async {
        await sessions.startSession(latitude: 34.5, longitude: 69.2);
        final h = _AutoHarness(settings: _manual(gpsTrackingEnabled: false));
        final controller = await h.build();

        expect(controller.activeSession, isNotNull);
        expect(controller.isTracking, isFalse);
        expect(controller.pauseReason, TrackingPauseReason.gpsDisabled);
      },
    );

    test(
      'auth restore racing controller restore still obeys gps policy',
      () async {
        await sessions.startSession(latitude: 34.5, longitude: 69.2);
        final h = _AutoHarness(settings: _manual(gpsTrackingEnabled: false));
        final controller = await h.create();
        await controller.acknowledgePrivacy();

        await Future.wait([controller.restore(), controller.setSignedIn(true)]);

        expect(controller.activeSession, isNotNull);
        expect(controller.isTracking, isFalse);
        expect(controller.pauseReason, TrackingPauseReason.gpsDisabled);
      },
    );

    test(
      'deferred sign-in still refreshes trusted settings from Laravel',
      () async {
        await sessions.startSession(latitude: 34.5, longitude: 69.2);
        await AttendanceTrackingSettingsRepository().saveTrusted(
          _manual(gpsTrackingEnabled: false),
          tenantId: '3',
        );
        final h = _AutoHarness(
          settings: _manual(gpsTrackingEnabled: false),
          repository: AttendanceTrackingSettingsRepository(
            remoteSource: _FixedSettingsSource(
              _manual(gpsTrackingEnabled: true),
            ),
          ),
        );
        final controller = await h.create(saveSettings: false);
        await controller.acknowledgePrivacy();

        await Future.wait([controller.restore(), controller.setSignedIn(true)]);

        expect(controller.gpsTrackingEnabled, isTrue);
        expect(controller.isTracking, isTrue);
      },
    );
  });

  group('GPS FRESHNESS', () {
    test('reports noLocationYet, fresh and stale', () async {
      final h = _AutoHarness(settings: _manual());
      final controller = await h.build();

      expect(controller.trackingFreshness, TrackingFreshness.noLocationYet);

      await gpsPoints.insertPoint(
        LocalGpsPoint(
          clientUuid: 'fresh-point',
          latitude: 34.5,
          longitude: 69.2,
          recordedAt: h.clock.now().toUtc().subtract(
            const Duration(minutes: 5),
          ),
          createdAt: h.clock.now().toUtc(),
        ),
      );
      await h.tracking.restoreLastPoint();
      expect(controller.trackingFreshness, TrackingFreshness.fresh);

      h.clock.advance(const Duration(minutes: 20));
      expect(controller.trackingFreshness, TrackingFreshness.stale);
    });
  });
}

AttendanceTrackingSettings _automatic({
  String start = '08:00',
  String end = '17:00',
  bool autoEndSession = false,
  bool gpsTrackingEnabled = true,
  int moving = 15,
  int stationary = 60,
  String? timezone = 'UTC',
}) => AttendanceTrackingSettings(
  startMode: WorkSessionStartMode.automatic,
  workdayStartTime: start,
  workdayEndTime: end,
  autoEndSession: autoEndSession,
  gpsTrackingEnabled: gpsTrackingEnabled,
  gpsMovingIntervalSeconds: moving,
  gpsStationaryIntervalSeconds: stationary,
  timezone: timezone,
);

AttendanceTrackingSettings _manual({
  bool gpsTrackingEnabled = true,
  String? timezone = 'UTC',
}) => AttendanceTrackingSettings(
  startMode: WorkSessionStartMode.manual,
  gpsTrackingEnabled: gpsTrackingEnabled,
  timezone: timezone,
);

class _AutoHarness {
  _AutoHarness({
    AttendanceTrackingSettings? settings,
    DateTime? now,
    bool online = false,
    AttendanceTrackingSettingsRepository? repository,
  }) : settings = settings ?? _automatic(),
       clock = TestClock(now ?? DateTime.utc(2026, 9, 18, 10)),
       connectivity = FakeConnectivityService(online: online),
       repo =
           repository ??
           AttendanceTrackingSettingsRepository(
             clock: TestClock(now ?? DateTime.utc(2026, 9, 18, 10)),
           ) {
    locationSource.current = LocationFix(
      latitude: 34.5553,
      longitude: 69.2075,
      accuracy: 5,
      speed: 0,
      recordedAt: clock.now().toUtc(),
    );
  }

  final AttendanceTrackingSettings settings;
  final TestClock clock;
  final FakeConnectivityService connectivity;
  final AttendanceTrackingSettingsRepository repo;
  final FakeLocationSource locationSource = FakeLocationSource();
  final FakeLocationPermissionService permissions =
      FakeLocationPermissionService(
        background: BackgroundLocationAccess.granted,
      );
  final FakeNotificationPermissionService notificationPermissions =
      FakeNotificationPermissionService();
  final FakeBoundaryScheduler scheduler = FakeBoundaryScheduler();
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

  late GpsTrackingService tracking;

  /// Constructs the controller without restoring/signing in (for concurrency
  /// and lifecycle tests).
  Future<AttendanceController> create({bool saveSettings = true}) async {
    if (saveSettings) {
      await repo.saveTrusted(settings, tenantId: '3');
    }
    tracking = GpsTrackingService(
      locationSource: locationSource,
      workSessions: WorkSessionRepository.instance,
      gpsPoints: GpsPointRepository.instance,
      telemetry: FakeDeviceTelemetryProvider(),
      config: const GpsTrackingConfig(),
      clock: clock,
    );
    return AttendanceController(
      workSessions: WorkSessionRepository.instance,
      privacyAcks: PrivacyAckStore.instance,
      permissions: permissions,
      locationSource: locationSource,
      tracking: tracking,
      gpsUpload: GpsUploadService(
        gpsPoints: GpsPointRepository.instance,
        gpsApi: GpsApi(apiClient: gpsClient),
        connectivity: connectivity,
      ),
      attendanceSync: AttendanceSyncService(
        api: AttendanceApi(apiClient: attendanceClient),
      ),
      connectivity: connectivity,
      secureStorage: FakeSecretStore(installationUuid: 'auto-device'),
      notificationPermissions: notificationPermissions,
      settingsRepository: repo,
      clock: clock,
      tenantTime: TenantTimeResolver(clock: clock),
      boundaryScheduler: scheduler,
    );
  }

  Future<AttendanceController> build({
    bool saveSettings = true,
    bool acknowledge = true,
    bool signedIn = true,
  }) async {
    final controller = await create(saveSettings: saveSettings);
    await controller.restore();
    if (acknowledge) {
      await controller.acknowledgePrivacy();
    }
    if (signedIn) {
      await controller.setSignedIn(true);
    }
    return controller;
  }
}

class _FixedSettingsSource implements AttendanceTrackingSettingsSource {
  _FixedSettingsSource(this.settings);

  final AttendanceTrackingSettings settings;

  @override
  Future<AttendanceTrackingSettings?> fetch() async => settings;
}
