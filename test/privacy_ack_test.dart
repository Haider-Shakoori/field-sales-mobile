import 'package:field_sales_mobile/core/api/api_client.dart';
import 'package:field_sales_mobile/core/api/api_exception.dart';
import 'package:field_sales_mobile/core/api/attendance_api.dart';
import 'package:field_sales_mobile/core/api/gps_api.dart';
import 'package:field_sales_mobile/core/api/privacy_ack_api.dart';
import 'package:field_sales_mobile/core/location/location_fix.dart';
import 'package:field_sales_mobile/core/location/location_permission_service.dart';
import 'package:field_sales_mobile/core/models/attendance_tracking_settings.dart';
import 'package:field_sales_mobile/core/storage/attendance_tracking_settings_repository.dart';
import 'package:field_sales_mobile/core/storage/gps_point_repository.dart';
import 'package:field_sales_mobile/core/storage/privacy_ack_store.dart';
import 'package:field_sales_mobile/core/storage/work_session_repository.dart';
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

  group('PRIVACY ACK — real API', () {
    test('posts only the contract body and stores the server id', () async {
      final h = _AckHarness();
      final controller = await h.build(acknowledge: false);

      final ack = await controller.acknowledgePrivacy();

      final request = h.privacyClient.requests.single;
      expect(request.method, 'POST');
      expect(request.path, '/gps/privacy-acknowledgement');
      final body = request.body! as Map;
      expect(body.keys.toSet(), {
        'policy_version',
        'acknowledged_at',
        'app_version',
      });
      expect(body['policy_version'], '1');
      expect(body['app_version'], '1.0.0');
      expect(body['acknowledged_at'], isA<String>());

      expect(ack.isSynced, isTrue);
      expect(ack.serverId, 55);
      expect(ack.serverUuid, 'ack-uuid-1');
      final stored = await PrivacyAckStore.instance.load();
      expect(stored!.isSynced, isTrue);
      expect(stored.serverId, 55);
    });

    test(
      'offline acknowledgement stays pending and syncs with same metadata',
      () async {
        final h = _AckHarness(online: false);
        final controller = await h.build(acknowledge: false);

        final pending = await controller.acknowledgePrivacy();

        expect(pending.isSynced, isFalse);
        expect(pending.syncStatus, 'pending');
        expect(h.privacyClient.requests, isEmpty);
        final originalInstant = pending.acknowledgedAt;

        h.connectivity.online = true;
        await controller.syncPrivacyAcknowledgement();

        final request = h.privacyClient.requests.single;
        final body = request.body! as Map;
        expect(body['policy_version'], pending.policyVersion);
        expect(body['acknowledged_at'], utcIsoForTest(originalInstant));
        final stored = await PrivacyAckStore.instance.load();
        expect(stored!.isSynced, isTrue);
        expect(stored.serverId, 55);
      },
    );

    test(
      'failed sync keeps the ack pending and retries the same payload',
      () async {
        final h = _AckHarness()..failSync = true;
        final controller = await h.build(acknowledge: false);

        final first = await controller.acknowledgePrivacy();
        expect(first.isSynced, isFalse);
        expect(h.privacyClient.requests, hasLength(1));

        h.failSync = false;
        await controller.syncPrivacyAcknowledgement();

        expect(h.privacyClient.requests, hasLength(2));
        expect(
          h.privacyClient.requests.first.body,
          h.privacyClient.requests.last.body,
        );
        final stored = await PrivacyAckStore.instance.load();
        expect(stored!.serverId, 55);
      },
    );

    test('policy version change requires a fresh acknowledgement', () async {
      final h = _AckHarness(settings: _autoSettings(privacyPolicyVersion: '1'));
      final controller = await h.build();
      expect(controller.privacyAcknowledged, isTrue);

      await h.repo.saveTrusted(
        _autoSettings(privacyPolicyVersion: '2'),
        tenantId: '3',
      );
      await controller.reloadSettings();
      await controller.evaluateAutomaticPolicy();

      expect(controller.effectivePolicyVersion, '2');
      expect(controller.privacyAcknowledged, isFalse);
      expect(controller.automaticState, AutomaticPolicyState.waitingForPrivacy);

      await controller.acknowledgePrivacy();

      expect(
        h.privacyClient.requests.last.body! as Map,
        containsPair('policy_version', '2'),
      );
      final stored = await PrivacyAckStore.instance.load();
      expect(stored!.policyVersion, '2');
      expect(stored.isSynced, isTrue);
    });

    test('automatic mode never silently acknowledges', () async {
      final h = _AckHarness(settings: _autoSettings());
      final controller = await h.build(acknowledge: false);

      expect(controller.automaticState, AutomaticPolicyState.waitingForPrivacy);
      expect(controller.activeSession, isNull);
      expect(h.privacyClient.requests, isEmpty);
      expect(await PrivacyAckStore.instance.load(), isNull);
    });
  });
}

String utcIsoForTest(DateTime time) => time.toUtc().toIso8601String();

AttendanceTrackingSettings _autoSettings({String privacyPolicyVersion = '1'}) =>
    AttendanceTrackingSettings(
      startMode: WorkSessionStartMode.automatic,
      workdayStartTime: '00:00',
      workdayEndTime: '23:59',
      timezone: 'UTC',
      privacyPolicyVersion: privacyPolicyVersion,
    );

class _AckHarness {
  _AckHarness({AttendanceTrackingSettings? settings, bool online = true})
    : settings = settings ?? _autoSettings(),
      clock = TestClock(DateTime.utc(2026, 9, 18, 10)),
      connectivity = FakeConnectivityService(online: online);

  final AttendanceTrackingSettings settings;
  final TestClock clock;
  final FakeConnectivityService connectivity;
  final FakeLocationSource locationSource = FakeLocationSource();
  final FakeLocationPermissionService permissions =
      FakeLocationPermissionService(
        background: BackgroundLocationAccess.granted,
      );
  final FakeNotificationPermissionService notificationPermissions =
      FakeNotificationPermissionService();
  final FakeBoundaryScheduler scheduler = FakeBoundaryScheduler();
  final AttendanceTrackingSettingsRepository repo =
      AttendanceTrackingSettingsRepository();

  bool failSync = false;

  late final RecordingApiClient privacyClient = RecordingApiClient(
    handler: (request) async {
      if (failSync) {
        throw ApiException(status: 0, message: 'offline', code: 'NETWORK');
      }
      return ApiEnvelope(
        data: {
          'id': 55,
          'uuid': 'ack-uuid-1',
          'policy_version': '1',
          'acknowledged_at': '2026-09-18T10:00:00Z',
          'recorded_at': '2026-09-18T10:00:00Z',
        },
      );
    },
  );

  Future<AttendanceController> build({bool acknowledge = true}) async {
    locationSource.current = LocationFix(
      latitude: 34.5553,
      longitude: 69.2075,
      accuracy: 5,
      speed: 0,
      recordedAt: clock.now().toUtc(),
    );
    await repo.saveTrusted(settings, tenantId: '3');

    final offlineClient = RecordingApiClient(
      handler: (request) async {
        throw ApiException(status: 0, message: 'offline', code: 'NETWORK');
      },
    );
    final tracking = GpsTrackingService(
      locationSource: locationSource,
      workSessions: WorkSessionRepository.instance,
      gpsPoints: GpsPointRepository.instance,
      telemetry: FakeDeviceTelemetryProvider(),
      config: const GpsTrackingConfig(),
      clock: clock,
    );
    final controller = AttendanceController(
      workSessions: WorkSessionRepository.instance,
      privacyAcks: PrivacyAckStore.instance,
      permissions: permissions,
      locationSource: locationSource,
      tracking: tracking,
      gpsUpload: GpsUploadService(
        gpsPoints: GpsPointRepository.instance,
        gpsApi: GpsApi(apiClient: offlineClient),
        connectivity: connectivity,
      ),
      attendanceSync: AttendanceSyncService(
        api: AttendanceApi(apiClient: offlineClient),
      ),
      connectivity: connectivity,
      secureStorage: FakeSecretStore(installationUuid: 'ack-device'),
      notificationPermissions: notificationPermissions,
      settingsRepository: repo,
      privacyAckApi: PrivacyAcknowledgementApi(apiClient: privacyClient),
      clock: clock,
      tenantTime: TenantTimeResolver(clock: clock),
      boundaryScheduler: scheduler,
    );
    await controller.restore();
    await controller.setSignedIn(true);
    if (acknowledge) {
      await controller.acknowledgePrivacy();
    }
    return controller;
  }
}
