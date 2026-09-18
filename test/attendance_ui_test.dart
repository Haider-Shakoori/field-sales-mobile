import 'package:field_sales_mobile/core/api/api_exception.dart';
import 'package:field_sales_mobile/core/api/attendance_api.dart';
import 'package:field_sales_mobile/core/api/gps_api.dart';
import 'package:field_sales_mobile/core/location/location_permission_service.dart';
import 'package:field_sales_mobile/core/storage/gps_point_repository.dart';
import 'package:field_sales_mobile/core/storage/privacy_ack_store.dart';
import 'package:field_sales_mobile/core/storage/work_session_repository.dart';
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

  Future<_UiHarness> pumpAttendanceCard(
    WidgetTester tester, {
    FakeLocationPermissionService? permissions,
  }) async {
    final harness = _UiHarness(
      permissions:
          permissions ??
          FakeLocationPermissionService(
            background: BackgroundLocationAccess.granted,
          ),
    );
    final controller = harness.controller;
    await controller.restore();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<AttendanceController>.value(
            value: controller,
            child: const SingleChildScrollView(child: AttendanceCard()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return harness;
  }

  testWidgets('shows Start Day when no session is active', (tester) async {
    await pumpAttendanceCard(tester);

    expect(find.text('Day not started'), findsOneWidget);
    expect(find.byKey(const Key('startDayButton')), findsOneWidget);
    expect(find.text('Tracking Active'), findsNothing);
  });

  testWidgets('first Start Day shows the disclosure, then starts tracking', (
    tester,
  ) async {
    await pumpAttendanceCard(tester);

    await tester.tap(find.byKey(const Key('startDayButton')));
    await tester.pumpAndSettle();

    expect(find.text('Location tracking disclosure'), findsOneWidget);
    expect(
      find.textContaining('Location is collected only while a work session'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Tracking continues while the app is in the'),
      findsOneWidget,
    );
    expect(
      find.textContaining('persistent "Location tracking active"'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('gpsPrivacyAgree')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Working'), findsOneWidget);
    expect(find.text('Tracking Active'), findsOneWidget);
    expect(find.byKey(const Key('endDayButton')), findsOneWidget);

    await tester.tap(find.byKey(const Key('endDayButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('endDayConfirm')));
    await tester.pumpAndSettle();
  });

  testWidgets('declining the disclosure does not start the day', (
    tester,
  ) async {
    await pumpAttendanceCard(tester);

    await tester.tap(find.byKey(const Key('startDayButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(find.text('Day not started'), findsOneWidget);
    expect(await WorkSessionRepository.instance.activeSession(), isNull);
  });

  testWidgets('End Day confirms, completes and stops tracking', (tester) async {
    await pumpAttendanceCard(tester);

    await tester.tap(find.byKey(const Key('startDayButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gpsPrivacyAgree')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byKey(const Key('endDayButton')));
    await tester.pumpAndSettle();
    expect(find.text('End your work session?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('endDayConfirm')));
    await tester.pumpAndSettle();

    // The completed card title and the End Day snackbar both say it.
    expect(find.text('Day completed'), findsWidgets);
    expect(find.text('Tracking Active'), findsNothing);
    expect(find.byKey(const Key('startDayButton')), findsNothing);
    expect(await WorkSessionRepository.instance.activeSession(), isNull);
  });

  testWidgets('denied location permission surfaces an error dialog', (
    tester,
  ) async {
    final permissions = FakeLocationPermissionService(
      foreground: LocationPermissionStatus.denied,
      requestForegroundResult: LocationPermissionStatus.denied,
      background: BackgroundLocationAccess.granted,
    );
    await pumpAttendanceCard(tester, permissions: permissions);

    await tester.tap(find.byKey(const Key('startDayButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gpsPrivacyAgree')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Location permission required'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(await WorkSessionRepository.instance.activeSession(), isNull);
  });
}

class _UiHarness {
  _UiHarness({required this.permissions});

  final FakeLocationPermissionService permissions;
  final FakeLocationSource locationSource = FakeLocationSource();

  late final AttendanceController controller = _build();

  AttendanceController _build() {
    final tracking = GpsTrackingService(
      locationSource: locationSource,
      workSessions: WorkSessionRepository.instance,
      gpsPoints: GpsPointRepository.instance,
      telemetry: FakeDeviceTelemetryProvider(),
      config: const GpsTrackingConfig(),
    );
    final uploader = GpsUploadService(
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
    );
    final sync = AttendanceSyncService(
      api: AttendanceApi(
        apiClient: RecordingApiClient(
          handler: (request) async => throw ApiException(
            status: 0,
            message: 'offline',
            code: 'NETWORK',
          ),
        ),
      ),
    );
    return AttendanceController(
      workSessions: WorkSessionRepository.instance,
      privacyAcks: PrivacyAckStore.instance,
      permissions: permissions,
      locationSource: locationSource,
      tracking: tracking,
      gpsUpload: uploader,
      attendanceSync: sync,
      connectivity: FakeConnectivityService(online: false),
      secureStorage: FakeSecretStore(installationUuid: 'ui-device'),
      notificationPermissions: FakeNotificationPermissionService(),
    );
  }
}
