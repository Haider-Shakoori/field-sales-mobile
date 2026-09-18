import 'package:field_sales_mobile/core/api/api_exception.dart';
import 'package:field_sales_mobile/core/api/attendance_api.dart';
import 'package:field_sales_mobile/core/api/gps_api.dart';
import 'package:field_sales_mobile/core/location/location_fix.dart';
import 'package:field_sales_mobile/core/location/location_permission_service.dart';
import 'package:field_sales_mobile/core/models/attendance_tracking_settings.dart';
import 'package:field_sales_mobile/core/storage/attendance_tracking_settings_repository.dart';
import 'package:field_sales_mobile/core/storage/gps_point_repository.dart';
import 'package:field_sales_mobile/core/storage/privacy_ack_store.dart';
import 'package:field_sales_mobile/core/storage/work_session_repository.dart';
import 'package:field_sales_mobile/core/time/tenant_time.dart';
import 'package:field_sales_mobile/features/attendance/attendance_card.dart';
import 'package:field_sales_mobile/features/attendance/attendance_controller.dart';
import 'package:field_sales_mobile/features/attendance/attendance_sync_service.dart';
import 'package:field_sales_mobile/features/tracking/gps_tracking_config.dart';
import 'package:field_sales_mobile/features/tracking/gps_tracking_service.dart';
import 'package:field_sales_mobile/features/tracking/gps_upload_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'helpers/test_harness.dart';

void main() {
  setUp(() => initTestDatabase(noIsolate: true));
  tearDown(tearDownDatabase);

  Future<_UiEnv> pumpCard(
    WidgetTester tester, {
    AttendanceTrackingSettings? settings,
    DateTime? now,
    bool acknowledge = true,
    LocationPermissionStatus foreground = LocationPermissionStatus.whileInUse,
    bool servicesEnabled = true,
  }) async {
    final env = _UiEnv(
      settings: settings,
      now: now ?? DateTime.utc(2026, 9, 18, 10),
      foreground: foreground,
      servicesEnabled: servicesEnabled,
    );
    final configured = env.settings;
    if (configured != null) {
      await env.repo.saveTrusted(configured, tenantId: '3');
    }
    await env.controller.restore();
    if (acknowledge) {
      await env.controller.acknowledgePrivacy();
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<AttendanceController>.value(
            value: env.controller,
            child: const SingleChildScrollView(child: AttendanceCard()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await env.controller.setSignedIn(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return env;
  }

  Future<void> disposeEnv(WidgetTester tester, _UiEnv env) async {
    await tester.pumpWidget(const SizedBox.shrink());
    env.controller.dispose();
  }

  testWidgets('manual fallback still shows the Start Day button', (
    tester,
  ) async {
    await pumpCard(tester, settings: null);

    expect(find.byKey(const Key('startDayButton')), findsOneWidget);
    expect(find.text('Automatic Work Day'), findsNothing);
  });

  testWidgets('automatic before schedule shows the scheduled start', (
    tester,
  ) async {
    await pumpCard(
      tester,
      settings: _settings(),
      now: DateTime.utc(2026, 9, 18, 7, 30),
    );

    expect(find.text('Automatic Work Day'), findsOneWidget);
    expect(find.text('Starts at 08:00'), findsOneWidget);
    expect(find.byKey(const Key('startDayButton')), findsNothing);
  });

  testWidgets('automatic inside the window shows tracking active + label', (
    tester,
  ) async {
    final env = await pumpCard(tester, settings: _settings());

    expect(find.text('Working'), findsOneWidget);
    expect(find.text('Tracking Active'), findsOneWidget);
    expect(find.text('Started automatically'), findsOneWidget);
    expect(find.text('Automatic Work Day'), findsNothing);

    await disposeEnv(tester, env);
  });

  testWidgets('automatic waiting for permission is actionable', (tester) async {
    final env = await pumpCard(
      tester,
      settings: _settings(),
      foreground: LocationPermissionStatus.denied,
    );

    expect(find.text('Automatic tracking waiting'), findsOneWidget);
    expect(find.text('Location permission required'), findsOneWidget);
    expect(find.byKey(const Key('grantPermissionButton')), findsOneWidget);

    await disposeEnv(tester, env);
  });

  testWidgets('automatic missing privacy shows Review tracking policy', (
    tester,
  ) async {
    final env = await pumpCard(
      tester,
      settings: _settings(),
      acknowledge: false,
    );

    expect(find.text('Automatic tracking waiting'), findsOneWidget);
    expect(find.text('Review tracking policy'), findsOneWidget);

    // Acknowledging the disclosure re-runs the automatic evaluation and
    // starts the session through the same Start Day flow.
    await tester.tap(find.byKey(const Key('reviewTrackingPolicyButton')));
    await tester.pumpAndSettle();
    expect(find.text('Location tracking disclosure'), findsOneWidget);
    await tester.tap(find.byKey(const Key('gpsPrivacyAgree')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Tracking Active'), findsOneWidget);

    await disposeEnv(tester, env);
  });

  testWidgets('automatic outside schedule shows work day inactive', (
    tester,
  ) async {
    await pumpCard(
      tester,
      settings: _settings(),
      now: DateTime.utc(2026, 9, 18, 19),
    );

    expect(find.text('Work day not active'), findsOneWidget);
    expect(find.byKey(const Key('startDayButton')), findsNothing);
  });

  testWidgets('automatic after completion shows day completed', (tester) async {
    final env = await pumpCard(tester, settings: _settings());
    expect(find.text('Tracking Active'), findsOneWidget);

    await env.controller.endDay();
    await env.controller.evaluateAutomaticPolicy();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Day completed'), findsWidgets);
    expect(find.byKey(const Key('startDayButton')), findsNothing);
    expect(env.controller.activeSession, isNull);

    await disposeEnv(tester, env);
  });

  testWidgets('gpsTrackingEnabled=false keeps Start Day available', (
    tester,
  ) async {
    final env = await pumpCard(
      tester,
      settings: _settings(gpsTrackingEnabled: false),
    );

    expect(
      find.text('Continuous GPS is disabled by company policy.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('startDayButton')), findsOneWidget);

    await disposeEnv(tester, env);
  });

  testWidgets('location services disabled shows the settings action', (
    tester,
  ) async {
    final env = await pumpCard(
      tester,
      settings: _settings(),
      servicesEnabled: false,
    );

    expect(find.text('Location services disabled'), findsOneWidget);
    expect(find.byKey(const Key('openLocationSettingsButton')), findsOneWidget);

    await disposeEnv(tester, env);
  });
}

AttendanceTrackingSettings _settings({bool gpsTrackingEnabled = true}) =>
    AttendanceTrackingSettings(
      startMode: WorkSessionStartMode.automatic,
      workdayStartTime: '08:00',
      workdayEndTime: '17:00',
      gpsTrackingEnabled: gpsTrackingEnabled,
      timezone: 'UTC',
    );

class _UiEnv {
  _UiEnv({
    this.settings,
    required DateTime now,
    required LocationPermissionStatus foreground,
    required bool servicesEnabled,
  }) : clock = TestClock(now),
       permissions = FakeLocationPermissionService(
         serviceEnabled: servicesEnabled,
         foreground: foreground,
         background: BackgroundLocationAccess.granted,
       ),
       repo = AttendanceTrackingSettingsRepository(clock: TestClock(now));

  final TestClock clock;
  final FakeLocationPermissionService permissions;
  final AttendanceTrackingSettingsRepository repo;

  /// Null means "no trusted settings cached" (manual fallback).
  final AttendanceTrackingSettings? settings;
  final FakeLocationSource locationSource = FakeLocationSource();
  final FakeBoundaryScheduler scheduler = FakeBoundaryScheduler();

  late final AttendanceController controller = _build();

  AttendanceController _build() {
    locationSource.current = LocationFix(
      latitude: 34.5553,
      longitude: 69.2075,
      accuracy: 5,
      speed: 0,
      recordedAt: clock.now().toUtc(),
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
        gpsApi: GpsApi(
          apiClient: RecordingApiClient(
            handler: (request) async => throw ApiException(
              status: 0,
              message: 'offline',
              code: 'NETWORK',
            ),
          ),
        ),
        connectivity: FakeConnectivityService(online: false),
      ),
      attendanceSync: AttendanceSyncService(
        api: AttendanceApi(
          apiClient: RecordingApiClient(
            handler: (request) async => throw ApiException(
              status: 0,
              message: 'offline',
              code: 'NETWORK',
            ),
          ),
        ),
      ),
      connectivity: FakeConnectivityService(online: false),
      secureStorage: FakeSecretStore(installationUuid: 'ui-auto-device'),
      notificationPermissions: FakeNotificationPermissionService(),
      settingsRepository: repo,
      clock: clock,
      tenantTime: TenantTimeResolver(clock: clock),
      boundaryScheduler: scheduler,
    );
    return controller;
  }
}
