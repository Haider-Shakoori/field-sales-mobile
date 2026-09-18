import 'dart:convert';

import 'package:field_sales_mobile/core/models/attendance_tracking_settings.dart';
import 'package:field_sales_mobile/core/storage/app_database.dart';
import 'package:field_sales_mobile/core/storage/attendance_tracking_settings_repository.dart';
import 'package:field_sales_mobile/features/tracking/gps_tracking_config.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_harness.dart';

void main() {
  setUp(initTestDatabase);
  tearDown(tearDownDatabase);

  group('SETTINGS MODEL', () {
    test('safe defaults are MANUAL with canonical Batch 7 intervals', () {
      const settings = AttendanceTrackingSettings.defaults();

      expect(settings.startMode, WorkSessionStartMode.manual);
      expect(settings.isAutomatic, isFalse);
      expect(settings.autoEndSession, isFalse);
      expect(settings.gpsTrackingEnabled, isTrue);
      expect(settings.gpsMovingIntervalSeconds, 15);
      expect(settings.gpsStationaryIntervalSeconds, 60);
      expect(settings.gpsStaleAfterMinutes, 15);
      expect(settings.trusted, isFalse);
      expect(settings.workdayStartTime, '08:00');
      expect(settings.workdayEndTime, '17:00');
    });

    test('sanitize replaces invalid intervals and records diagnostics', () {
      const invalid = AttendanceTrackingSettings(
        gpsMovingIntervalSeconds: 2,
        gpsStationaryIntervalSeconds: 5,
        gpsStaleAfterMinutes: 5000,
      );
      final issues = <String>[];

      final sanitized = invalid.sanitized(issues);

      expect(sanitized.gpsMovingIntervalSeconds, 15);
      expect(sanitized.gpsStationaryIntervalSeconds, 60);
      expect(sanitized.gpsStaleAfterMinutes, 15);
      expect(issues, hasLength(3));
    });

    test('sanitize repairs a stationary interval below moving', () {
      const invalid = AttendanceTrackingSettings(
        gpsMovingIntervalSeconds: 120,
        gpsStationaryIntervalSeconds: 30,
      );
      final issues = <String>[];

      final sanitized = invalid.sanitized(issues);

      expect(sanitized.gpsMovingIntervalSeconds, 120);
      expect(sanitized.gpsStationaryIntervalSeconds, 120);
      expect(issues, isNotEmpty);
    });

    test('sanitize rejects malformed and empty work windows', () {
      final issues = <String>[];

      final badFormat = const AttendanceTrackingSettings(
        workdayStartTime: '8am',
        workdayEndTime: '17:00',
      ).sanitized(issues);
      expect(badFormat.workdayStartTime, '08:00');
      expect(issues, isNotEmpty);

      issues.clear();
      final emptyWindow = const AttendanceTrackingSettings(
        workdayStartTime: '09:00',
        workdayEndTime: '09:00',
      ).sanitized(issues);
      expect(emptyWindow.workdayStartTime, '08:00');
      expect(emptyWindow.workdayEndTime, '17:00');
      expect(issues, isNotEmpty);
    });

    test('toJson/fromJson round trip preserves every field', () {
      final settings = AttendanceTrackingSettings(
        startMode: WorkSessionStartMode.automatic,
        workdayStartTime: '20:00',
        workdayEndTime: '04:00',
        autoEndSession: true,
        gpsTrackingEnabled: false,
        gpsMovingIntervalSeconds: 30,
        gpsStationaryIntervalSeconds: 120,
        gpsStaleAfterMinutes: 45,
        timezone: 'Asia/Kabul',
        settingsVersion: '7',
        updatedAt: DateTime.utc(2026, 9, 18, 6),
        fetchedAt: DateTime.utc(2026, 9, 18, 6, 5),
        tenantId: 3,
        trusted: true,
      );

      final restored = AttendanceTrackingSettings.fromJson(
        jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>,
      );

      expect(restored.startMode, WorkSessionStartMode.automatic);
      expect(restored.workdayStartTime, '20:00');
      expect(restored.workdayEndTime, '04:00');
      expect(restored.autoEndSession, isTrue);
      expect(restored.gpsTrackingEnabled, isFalse);
      expect(restored.gpsMovingIntervalSeconds, 30);
      expect(restored.gpsStationaryIntervalSeconds, 120);
      expect(restored.gpsStaleAfterMinutes, 45);
      expect(restored.timezone, 'Asia/Kabul');
      expect(restored.settingsVersion, '7');
      expect(restored.updatedAt, DateTime.utc(2026, 9, 18, 6));
      expect(restored.tenantId, 3);
      expect(restored.trusted, isTrue);
    });
  });

  group('SETTINGS REPOSITORY', () {
    final repo = AttendanceTrackingSettingsRepository(
      clock: TestClock(DateTime.utc(2026, 9, 18, 6)),
    );

    test('missing cache returns untrusted MANUAL defaults', () async {
      final result = await repo.load();

      expect(result.source, SettingsSource.defaults);
      expect(result.trusted, isFalse);
      expect(result.settings.startMode, WorkSessionStartMode.manual);
    });

    test(
      'saveTrusted validates, stamps metadata and load returns trusted',
      () async {
        final result = await repo.saveTrusted(
          const AttendanceTrackingSettings(
            startMode: WorkSessionStartMode.automatic,
            workdayStartTime: '08:00',
            workdayEndTime: '17:00',
            autoEndSession: true,
          ),
          tenantId: 3,
        );

        expect(result.trusted, isTrue);
        expect(result.settings.tenantId, 3);
        expect(result.settings.fetchedAt, DateTime.utc(2026, 9, 18, 6));

        final loaded = await repo.load(tenantId: 3);
        expect(loaded.trusted, isTrue);
        expect(loaded.settings.isAutomatic, isTrue);
        expect(loaded.settings.autoEndSession, isTrue);
      },
    );

    test(
      'invalid cached values are sanitized on load with diagnostics',
      () async {
        final payload = {
          'start_mode': 'automatic',
          'workday_start_time': '08:00',
          'workday_end_time': '17:00',
          'gps_moving_interval_seconds': 1,
          'gps_stationary_interval_seconds': 0,
          'gps_stale_after_minutes': 0,
          'trusted': true,
        };
        final db = await AppDatabase.instance;
        await db.insert('local_settings', {
          'key': AttendanceTrackingSettingsRepository.cacheKey,
          'value': jsonEncode(payload),
        });

        final loaded = await repo.load();

        expect(loaded.trusted, isTrue);
        expect(loaded.settings.gpsMovingIntervalSeconds, 15);
        expect(loaded.settings.gpsStationaryIntervalSeconds, 60);
        expect(loaded.settings.gpsStaleAfterMinutes, 15);
        expect(loaded.issues, isNotEmpty);
      },
    );

    test('corrupted cache falls back to untrusted defaults', () async {
      final db = await AppDatabase.instance;
      await db.insert('local_settings', {
        'key': AttendanceTrackingSettingsRepository.cacheKey,
        'value': '{not-json',
      });

      final loaded = await repo.load();

      expect(loaded.source, SettingsSource.defaults);
      expect(loaded.trusted, isFalse);
      expect(loaded.issues, isNotEmpty);
    });

    test('untrusted cached payload is ignored', () async {
      final db = await AppDatabase.instance;
      await db.insert('local_settings', {
        'key': AttendanceTrackingSettingsRepository.cacheKey,
        'value': jsonEncode({'start_mode': 'automatic', 'trusted': false}),
      });

      final loaded = await repo.load();

      expect(loaded.source, SettingsSource.defaults);
      expect(loaded.settings.isAutomatic, isFalse);
    });

    test('tenant mismatch falls back to safe defaults', () async {
      await repo.saveTrusted(
        const AttendanceTrackingSettings(
          startMode: WorkSessionStartMode.automatic,
        ),
        tenantId: 3,
      );

      final loaded = await repo.load(tenantId: 99);

      expect(loaded.source, SettingsSource.defaults);
      expect(loaded.settings.isAutomatic, isFalse);
      expect(loaded.issues.single, contains('tenant'));
    });

    test('refreshFromServer without a transport reads the cache', () async {
      await repo.saveTrusted(
        const AttendanceTrackingSettings(
          startMode: WorkSessionStartMode.automatic,
        ),
        tenantId: 3,
      );

      final refreshed = await repo.refreshFromServer(tenantId: 3);

      expect(refreshed.trusted, isTrue);
      expect(refreshed.settings.isAutomatic, isTrue);
    });

    test('refreshFromServer saves a trusted transport payload', () async {
      final source = _FakeSettingsSource(
        const AttendanceTrackingSettings(
          startMode: WorkSessionStartMode.automatic,
          workdayStartTime: '07:00',
          workdayEndTime: '15:00',
          settingsVersion: '9',
        ),
      );
      final remoteRepo = AttendanceTrackingSettingsRepository(
        remoteSource: source,
        clock: TestClock(DateTime.utc(2026, 9, 18, 6)),
      );

      final refreshed = await remoteRepo.refreshFromServer(tenantId: 3);

      expect(source.fetchCalls, 1);
      expect(refreshed.trusted, isTrue);
      expect(refreshed.settings.workdayStartTime, '07:00');
      expect(refreshed.settings.settingsVersion, '9');

      final loaded = await remoteRepo.load(tenantId: 3);
      expect(loaded.settings.workdayEndTime, '15:00');
    });

    test(
      'refreshFromServer keeps cached settings when transport is empty',
      () async {
        final source = _FakeSettingsSource(null);
        final remoteRepo = AttendanceTrackingSettingsRepository(
          remoteSource: source,
        );
        await remoteRepo.saveTrusted(
          const AttendanceTrackingSettings(
            startMode: WorkSessionStartMode.automatic,
          ),
          tenantId: 3,
        );

        final refreshed = await remoteRepo.refreshFromServer(tenantId: 3);

        expect(source.fetchCalls, 1);
        expect(refreshed.settings.isAutomatic, isTrue);
      },
    );
  });

  group('GPS CONFIG', () {
    test('fromSettings maps company intervals', () {
      const settings = AttendanceTrackingSettings(
        gpsMovingIntervalSeconds: 30,
        gpsStationaryIntervalSeconds: 120,
      );

      final config = GpsTrackingConfig.fromSettings(settings);

      expect(config.movingInterval, const Duration(seconds: 30));
      expect(config.stationaryInterval, const Duration(seconds: 120));
      expect(config.maxAccuracyMeters, 100);
      expect(config.startFixTimeout, const Duration(seconds: 20));
      expect(config.batchSize, 100);
    });

    test('defaults keep the Batch 7 canonical intervals', () {
      final config = GpsTrackingConfig.fromSettings(
        const AttendanceTrackingSettings.defaults(),
      );

      expect(config.movingInterval, const Duration(seconds: 15));
      expect(config.stationaryInterval, const Duration(seconds: 60));
    });
  });
}

class _FakeSettingsSource implements AttendanceTrackingSettingsSource {
  _FakeSettingsSource(this.settings);

  AttendanceTrackingSettings? settings;
  int fetchCalls = 0;

  @override
  Future<AttendanceTrackingSettings?> fetch() async {
    fetchCalls++;
    return settings;
  }
}
