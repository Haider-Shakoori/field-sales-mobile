import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/attendance_tracking_settings.dart';
import '../time/clock.dart';
import 'app_database.dart';

/// Where a settings load came from.
enum SettingsSource { defaults, cache }

/// Effective settings plus provenance and validation diagnostics.
class SettingsLoadResult {
  const SettingsLoadResult({
    required this.settings,
    required this.source,
    this.issues = const [],
  });

  final AttendanceTrackingSettings settings;
  final SettingsSource source;

  /// Validation problems found while loading (invalid values were replaced by
  /// safe defaults).
  final List<String> issues;

  /// Only trusted, server-sourced cached settings may drive automatic policy.
  bool get trusted => settings.trusted && source == SettingsSource.cache;
}

/// Future Laravel settings transport.
///
/// Deliberately has no production implementation/endpoint yet: the backend
/// contract is reconciled in the Laravel ↔ Flutter pass. Tests (and later the
/// real integration) bind an implementation via the repository constructor.
abstract class AttendanceTrackingSettingsSource {
  Future<AttendanceTrackingSettings?> fetch();
}

/// Caches the company Attendance & Tracking policy in `local_settings`.
///
/// Offline-first: the last TRUSTED server payload is obeyed while offline; when
/// nothing trusted has ever been received, safe MANUAL defaults are returned.
/// This is intentionally not general remote-config infrastructure.
class AttendanceTrackingSettingsRepository {
  AttendanceTrackingSettingsRepository({
    AttendanceTrackingSettingsSource? remoteSource,
    Clock clock = const Clock(),
  }) : _remoteSource = remoteSource,
       _clock = clock;

  static final AttendanceTrackingSettingsRepository instance =
      AttendanceTrackingSettingsRepository();

  static const cacheKey = 'attendance_tracking_settings';

  final AttendanceTrackingSettingsSource? _remoteSource;
  final Clock _clock;

  /// Reads the last trusted settings, or safe defaults.
  Future<SettingsLoadResult> load({int? tenantId}) async {
    final db = await AppDatabase.instance;
    final rows = await db.query(
      'local_settings',
      where: 'key = ?',
      whereArgs: [cacheKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      return const SettingsLoadResult(
        settings: AttendanceTrackingSettings.defaults(),
        source: SettingsSource.defaults,
      );
    }

    final raw = rows.first['value'] as String?;
    if (raw == null || raw.isEmpty) {
      return const SettingsLoadResult(
        settings: AttendanceTrackingSettings.defaults(),
        source: SettingsSource.defaults,
        issues: ['cached settings value is empty'],
      );
    }

    AttendanceTrackingSettings parsed;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('settings payload is not an object');
      }
      parsed = AttendanceTrackingSettings.fromJson(decoded);
    } catch (error) {
      return SettingsLoadResult(
        settings: const AttendanceTrackingSettings.defaults(),
        source: SettingsSource.defaults,
        issues: ['cached settings are corrupted: $error'],
      );
    }

    if (!parsed.trusted) {
      return const SettingsLoadResult(
        settings: AttendanceTrackingSettings.defaults(),
        source: SettingsSource.defaults,
        issues: ['cached settings are not trusted'],
      );
    }

    if (parsed.tenantId != null &&
        tenantId != null &&
        parsed.tenantId != tenantId) {
      return SettingsLoadResult(
        settings: const AttendanceTrackingSettings.defaults(),
        source: SettingsSource.defaults,
        issues: [
          'cached settings belong to tenant ${parsed.tenantId}, '
              'current tenant is $tenantId',
        ],
      );
    }

    final issues = <String>[];
    final sanitized = parsed.sanitized(issues);
    return SettingsLoadResult(
      settings: sanitized,
      source: SettingsSource.cache,
      issues: issues,
    );
  }

  /// Validates and persists a trusted (server-sourced) payload.
  Future<SettingsLoadResult> saveTrusted(
    AttendanceTrackingSettings settings, {
    int? tenantId,
  }) async {
    final issues = <String>[];
    final sanitized = settings.sanitized(issues);
    final stored = sanitized.copyWith(
      trusted: true,
      fetchedAt: settings.fetchedAt ?? _clock.now().toUtc(),
      tenantId: settings.tenantId ?? tenantId,
    );

    final db = await AppDatabase.instance;
    await db.insert('local_settings', {
      'key': cacheKey,
      'value': jsonEncode(stored.toJson()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    return SettingsLoadResult(
      settings: stored,
      source: SettingsSource.cache,
      issues: issues,
    );
  }

  /// Attempts a server refresh when a transport has been bound; otherwise
  /// returns the cached/default load unchanged. This is the single seam the
  /// future Laravel settings endpoint plugs into.
  Future<SettingsLoadResult> refreshFromServer({int? tenantId}) async {
    final source = _remoteSource;
    if (source == null) {
      return load(tenantId: tenantId);
    }
    final remote = await source.fetch();
    if (remote == null) {
      return load(tenantId: tenantId);
    }
    return saveTrusted(remote, tenantId: tenantId);
  }

  Future<void> clear() async {
    final db = await AppDatabase.instance;
    await db.delete('local_settings', where: 'key = ?', whereArgs: [cacheKey]);
  }
}
