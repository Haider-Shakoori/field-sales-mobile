import 'package:field_sales_mobile/core/api/api_client.dart';
import 'package:field_sales_mobile/core/api/attendance_tracking_settings_api.dart';
import 'package:field_sales_mobile/core/models/attendance_tracking_settings.dart';
import 'package:field_sales_mobile/core/storage/attendance_tracking_settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_harness.dart';

void main() {
  setUp(initTestDatabase);
  tearDown(tearDownDatabase);

  Map<String, dynamic> laravelPayload() => {
    'work_session_start_mode': 'automatic',
    'workday_start_time': '09:00',
    'workday_end_time': '18:30',
    'auto_end_session': true,
    'gps_tracking_enabled': false,
    'gps_moving_interval_seconds': 30,
    'gps_stationary_interval_seconds': 120,
    'gps_stale_after_minutes': 20,
    'timezone': 'Asia/Kabul',
    'privacy_policy_version': '1',
    'updated_at': '2026-09-18T06:00:00+00:00',
  };

  group('SETTINGS API — real endpoint', () {
    test(
      'GET /settings/attendance-tracking maps the Laravel payload',
      () async {
        final client = RecordingApiClient(
          handler: (request) async => ApiEnvelope(data: laravelPayload()),
        );
        final api = AttendanceTrackingSettingsApi(apiClient: client);

        final settings = await api.fetch();

        expect(client.requests.single.method, 'GET');
        expect(client.requests.single.path, '/settings/attendance-tracking');
        expect(settings.startMode, WorkSessionStartMode.automatic);
        expect(settings.workdayStartTime, '09:00');
        expect(settings.workdayEndTime, '18:30');
        expect(settings.autoEndSession, isTrue);
        expect(settings.gpsTrackingEnabled, isFalse);
        expect(settings.gpsMovingIntervalSeconds, 30);
        expect(settings.gpsStationaryIntervalSeconds, 120);
        expect(settings.gpsStaleAfterMinutes, 20);
        expect(settings.timezone, 'Asia/Kabul');
        expect(settings.privacyPolicyVersion, '1');
        expect(settings.updatedAt, DateTime.utc(2026, 9, 18, 6));
        // Trust is stamped by the repository, never by the raw payload.
        expect(settings.trusted, isFalse);
      },
    );

    test(
      'repository refresh caches trusted settings for the active tenant',
      () async {
        final client = RecordingApiClient(
          handler: (request) async => ApiEnvelope(data: laravelPayload()),
        );
        final repo = AttendanceTrackingSettingsRepository(
          remoteSource: HttpAttendanceTrackingSettingsSource(
            api: AttendanceTrackingSettingsApi(apiClient: client),
          ),
          clock: TestClock(DateTime.utc(2026, 9, 18, 7)),
        );

        final result = await repo.refreshFromServer(tenantId: '3');

        expect(result.trusted, isTrue);
        expect(result.settings.tenantId, '3');
        expect(result.settings.trusted, isTrue);
        expect(result.settings.fetchedAt, DateTime.utc(2026, 9, 18, 7));
        expect(result.settings.updatedAt, DateTime.utc(2026, 9, 18, 6));
        expect(result.settings.privacyPolicyVersion, '1');

        final loaded = await repo.load(tenantId: '3');
        expect(loaded.trusted, isTrue);
        expect(loaded.settings.isAutomatic, isTrue);
        expect(loaded.settings.gpsTrackingEnabled, isFalse);
      },
    );

    test(
      'failed refresh keeps the last trusted cache and never throws',
      () async {
        final good = AttendanceTrackingSettingsRepository(
          remoteSource: _StaticSource(
            AttendanceTrackingSettings.fromApiJson(laravelPayload()),
          ),
        );
        await good.saveTrusted(
          AttendanceTrackingSettings.fromApiJson(laravelPayload()),
          tenantId: '3',
        );

        final failing = AttendanceTrackingSettingsRepository(
          remoteSource: _FailingSource(),
        );
        final result = await failing.refreshFromServer(tenantId: '3');

        expect(result.trusted, isTrue);
        expect(result.settings.isAutomatic, isTrue);
        expect(result.settings.timezone, 'Asia/Kabul');
        expect(result.issues.join(' '), contains('refresh failed'));
      },
    );

    test('no cache + failed refresh falls back to MANUAL defaults', () async {
      final failing = AttendanceTrackingSettingsRepository(
        remoteSource: _FailingSource(),
      );

      final result = await failing.refreshFromServer(tenantId: '3');

      expect(result.source, SettingsSource.defaults);
      expect(result.trusted, isFalse);
      expect(result.settings.startMode, WorkSessionStartMode.manual);
      expect(result.issues, isNotEmpty);
    });

    test('one failing refresh never erases a valid trusted cache', () async {
      final failing = AttendanceTrackingSettingsRepository(
        remoteSource: _FailingSource(),
      );
      await failing.saveTrusted(
        AttendanceTrackingSettings.fromApiJson(laravelPayload()),
        tenantId: '3',
      );

      final refreshed = await failing.refreshFromServer(tenantId: '3');
      final loaded = await failing.load(tenantId: '3');

      expect(refreshed.trusted, isTrue);
      expect(loaded.trusted, isTrue);
      expect(loaded.settings.isAutomatic, isTrue);
    });
  });
}

class _FailingSource implements AttendanceTrackingSettingsSource {
  @override
  Future<AttendanceTrackingSettings?> fetch() async {
    throw StateError('network down');
  }
}

class _StaticSource implements AttendanceTrackingSettingsSource {
  _StaticSource(this.settings);

  final AttendanceTrackingSettings settings;

  @override
  Future<AttendanceTrackingSettings?> fetch() async => settings;
}
