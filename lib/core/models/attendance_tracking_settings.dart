import 'time_utils.dart';

/// Company-configured work-session start behaviour.
enum WorkSessionStartMode {
  manual,
  automatic;

  static WorkSessionStartMode from(String? value) =>
      WorkSessionStartMode.values.firstWhere(
        (mode) => mode.name == value,
        orElse: () => WorkSessionStartMode.manual,
      );
}

/// Validation bounds for the company GPS interval settings.
///
/// Values outside these ranges are not trusted and fall back to the safe
/// Batch 7 defaults.
const int kMinGpsMovingIntervalSeconds = 10;
const int kMaxGpsMovingIntervalSeconds = 3600;
const int kMaxGpsStationaryIntervalSeconds = 7200;
const int kMinGpsStaleAfterMinutes = 1;
const int kMaxGpsStaleAfterMinutes = 720;

/// Company-controlled Attendance & Tracking policy.
///
/// This is the mobile mirror of the (future) Laravel-managed settings. Until a
/// trusted server payload has been cached, [AttendanceTrackingSettings.defaults]
/// is used — always MANUAL, so production stays on the verified Batch 7 path.
class AttendanceTrackingSettings {
  const AttendanceTrackingSettings({
    this.startMode = WorkSessionStartMode.manual,
    this.workdayStartTime = defaultWorkdayStartTime,
    this.workdayEndTime = defaultWorkdayEndTime,
    this.autoEndSession = false,
    this.gpsTrackingEnabled = true,
    this.gpsMovingIntervalSeconds = defaultGpsMovingIntervalSeconds,
    this.gpsStationaryIntervalSeconds = defaultGpsStationaryIntervalSeconds,
    this.gpsStaleAfterMinutes = defaultGpsStaleAfterMinutes,
    this.timezone,
    this.settingsVersion,
    this.updatedAt,
    this.fetchedAt,
    this.tenantId,
    this.trusted = false,
  });

  /// Safe production defaults: no automatic behaviour until a trusted company
  /// payload has been received and cached.
  const AttendanceTrackingSettings.defaults()
    : startMode = WorkSessionStartMode.manual,
      workdayStartTime = defaultWorkdayStartTime,
      workdayEndTime = defaultWorkdayEndTime,
      autoEndSession = false,
      gpsTrackingEnabled = true,
      gpsMovingIntervalSeconds = defaultGpsMovingIntervalSeconds,
      gpsStationaryIntervalSeconds = defaultGpsStationaryIntervalSeconds,
      gpsStaleAfterMinutes = defaultGpsStaleAfterMinutes,
      timezone = null,
      settingsVersion = null,
      updatedAt = null,
      fetchedAt = null,
      tenantId = null,
      trusted = false;

  /// Batch 7 canonical collection intervals (single source of truth).
  static const int defaultGpsMovingIntervalSeconds = 15;
  static const int defaultGpsStationaryIntervalSeconds = 60;
  static const int defaultGpsStaleAfterMinutes = 15;
  static const String defaultWorkdayStartTime = '08:00';
  static const String defaultWorkdayEndTime = '17:00';

  final WorkSessionStartMode startMode;

  /// Local `HH:mm` work window boundaries.
  final String workdayStartTime;
  final String workdayEndTime;

  /// Whether Flutter may end an active session after the window closes.
  final bool autoEndSession;

  /// Master switch for CONTINUOUS GPS. Attendance itself stays available.
  final bool gpsTrackingEnabled;

  final int gpsMovingIntervalSeconds;
  final int gpsStationaryIntervalSeconds;

  /// Latest accepted point older than this is considered stale.
  final int gpsStaleAfterMinutes;

  /// Optional IANA tenant timezone. Not used for conversion in this phase:
  /// the work window is evaluated in device-local time until the server
  /// contract defines timezone semantics. Kept for the future contract.
  final String? timezone;

  final String? settingsVersion;
  final DateTime? updatedAt;
  final DateTime? fetchedAt;

  /// Tenant the settings were fetched for; guards against cross-tenant reuse.
  final int? tenantId;

  /// True only for settings that came from a trusted server payload.
  final bool trusted;

  bool get isAutomatic => startMode == WorkSessionStartMode.automatic;

  /// Parses a cache/server payload. Tolerant of missing keys but NOT silently
  /// trusting them: the result must pass [sanitize] and be explicitly marked
  /// trusted by the repository before use.
  factory AttendanceTrackingSettings.fromJson(Map<String, dynamic> json) =>
      AttendanceTrackingSettings(
        startMode: WorkSessionStartMode.from(json['start_mode']?.toString()),
        workdayStartTime:
            json['workday_start_time']?.toString() ?? defaultWorkdayStartTime,
        workdayEndTime:
            json['workday_end_time']?.toString() ?? defaultWorkdayEndTime,
        autoEndSession: json['auto_end_session'] == true,
        gpsTrackingEnabled: json['gps_tracking_enabled'] != false,
        gpsMovingIntervalSeconds:
            (json['gps_moving_interval_seconds'] as num?)?.toInt() ??
            defaultGpsMovingIntervalSeconds,
        gpsStationaryIntervalSeconds:
            (json['gps_stationary_interval_seconds'] as num?)?.toInt() ??
            defaultGpsStationaryIntervalSeconds,
        gpsStaleAfterMinutes:
            (json['gps_stale_after_minutes'] as num?)?.toInt() ??
            defaultGpsStaleAfterMinutes,
        timezone: json['timezone']?.toString(),
        settingsVersion: json['settings_version']?.toString(),
        updatedAt: _parseDate(json['updated_at']),
        fetchedAt: _parseDate(json['fetched_at']),
        tenantId: (json['tenant_id'] as num?)?.toInt(),
        trusted: json['trusted'] == true,
      );

  Map<String, dynamic> toJson() => {
    'start_mode': startMode.name,
    'workday_start_time': workdayStartTime,
    'workday_end_time': workdayEndTime,
    'auto_end_session': autoEndSession,
    'gps_tracking_enabled': gpsTrackingEnabled,
    'gps_moving_interval_seconds': gpsMovingIntervalSeconds,
    'gps_stationary_interval_seconds': gpsStationaryIntervalSeconds,
    'gps_stale_after_minutes': gpsStaleAfterMinutes,
    'timezone': timezone,
    'settings_version': settingsVersion,
    'updated_at': updatedAt == null ? null : utcIso(updatedAt!),
    'fetched_at': fetchedAt == null ? null : utcIso(fetchedAt!),
    'tenant_id': tenantId,
    'trusted': trusted,
  };

  /// Returns a copy with invalid values replaced by safe defaults, recording a
  /// diagnostic per replaced field. Invalid company payloads must never crash
  /// or distort tracking.
  AttendanceTrackingSettings sanitized(List<String> issues) {
    var moving = gpsMovingIntervalSeconds;
    if (moving < kMinGpsMovingIntervalSeconds ||
        moving > kMaxGpsMovingIntervalSeconds) {
      issues.add(
        'gps_moving_interval_seconds=$moving outside '
        '[$kMinGpsMovingIntervalSeconds, $kMaxGpsMovingIntervalSeconds]',
      );
      moving = defaultGpsMovingIntervalSeconds;
    }

    var stationary = gpsStationaryIntervalSeconds;
    if (stationary < moving || stationary > kMaxGpsStationaryIntervalSeconds) {
      issues.add(
        'gps_stationary_interval_seconds=$stationary invalid for moving=$moving',
      );
      stationary = defaultGpsStationaryIntervalSeconds < moving
          ? moving
          : defaultGpsStationaryIntervalSeconds;
    }

    var stale = gpsStaleAfterMinutes;
    if (stale < kMinGpsStaleAfterMinutes || stale > kMaxGpsStaleAfterMinutes) {
      issues.add('gps_stale_after_minutes=$stale out of range');
      stale = defaultGpsStaleAfterMinutes;
    }

    var start = workdayStartTime;
    var end = workdayEndTime;
    if (parseHhMm(start) == null) {
      issues.add('workday_start_time="$start" is not HH:mm');
      start = defaultWorkdayStartTime;
    }
    if (parseHhMm(end) == null) {
      issues.add('workday_end_time="$end" is not HH:mm');
      end = defaultWorkdayEndTime;
    }
    if (start == end) {
      issues.add('workday window "$start"–"$end" is empty');
      start = defaultWorkdayStartTime;
      end = defaultWorkdayEndTime;
    }

    return copyWith(
      workdayStartTime: start,
      workdayEndTime: end,
      gpsMovingIntervalSeconds: moving,
      gpsStationaryIntervalSeconds: stationary,
      gpsStaleAfterMinutes: stale,
    );
  }

  AttendanceTrackingSettings copyWith({
    WorkSessionStartMode? startMode,
    String? workdayStartTime,
    String? workdayEndTime,
    bool? autoEndSession,
    bool? gpsTrackingEnabled,
    int? gpsMovingIntervalSeconds,
    int? gpsStationaryIntervalSeconds,
    int? gpsStaleAfterMinutes,
    String? timezone,
    String? settingsVersion,
    DateTime? updatedAt,
    DateTime? fetchedAt,
    int? tenantId,
    bool? trusted,
  }) => AttendanceTrackingSettings(
    startMode: startMode ?? this.startMode,
    workdayStartTime: workdayStartTime ?? this.workdayStartTime,
    workdayEndTime: workdayEndTime ?? this.workdayEndTime,
    autoEndSession: autoEndSession ?? this.autoEndSession,
    gpsTrackingEnabled: gpsTrackingEnabled ?? this.gpsTrackingEnabled,
    gpsMovingIntervalSeconds:
        gpsMovingIntervalSeconds ?? this.gpsMovingIntervalSeconds,
    gpsStationaryIntervalSeconds:
        gpsStationaryIntervalSeconds ?? this.gpsStationaryIntervalSeconds,
    gpsStaleAfterMinutes: gpsStaleAfterMinutes ?? this.gpsStaleAfterMinutes,
    timezone: timezone ?? this.timezone,
    settingsVersion: settingsVersion ?? this.settingsVersion,
    updatedAt: updatedAt ?? this.updatedAt,
    fetchedAt: fetchedAt ?? this.fetchedAt,
    tenantId: tenantId ?? this.tenantId,
    trusted: trusted ?? this.trusted,
  );

  static DateTime? _parseDate(Object? value) {
    if (value is! String || value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(value);
  }
}

/// Parses `HH:mm` or `HH:mm:ss` into minutes since midnight, or null.
int? parseHhMm(String value) {
  final parts = value.trim().split(':');
  if (parts.length < 2 || parts.length > 3) {
    return null;
  }
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) {
    return null;
  }
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
    return null;
  }
  return hour * 60 + minute;
}

/// Formats minutes-since-midnight as `HH:mm`.
String formatHhMm(int minutes) {
  final hour = (minutes ~/ 60).toString().padLeft(2, '0');
  final minute = (minutes % 60).toString().padLeft(2, '0');
  return '$hour:$minute';
}
