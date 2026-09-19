class AttendanceTrackingSettings {
  const AttendanceTrackingSettings({
    required this.startMode,
    required this.workdayStartTime,
    required this.workdayEndTime,
    required this.autoEndSession,
    required this.gpsTrackingEnabled,
    required this.movingSeconds,
    required this.stationarySeconds,
    required this.staleMinutes,
    required this.timezone,
    required this.privacyPolicyVersion,
    required this.trusted,
    this.tenantId,
    this.fetchedAt,
  });
  final String startMode,
      workdayStartTime,
      workdayEndTime,
      timezone,
      privacyPolicyVersion;
  final bool autoEndSession, gpsTrackingEnabled, trusted;
  final int movingSeconds, stationarySeconds, staleMinutes;
  final String? tenantId;
  final DateTime? fetchedAt;
  static AttendanceTrackingSettings defaults({String? tenantId}) =>
      AttendanceTrackingSettings(
        startMode: 'manual',
        workdayStartTime: '08:00',
        workdayEndTime: '17:00',
        autoEndSession: false,
        gpsTrackingEnabled: true,
        movingSeconds: 15,
        stationarySeconds: 60,
        staleMinutes: 15,
        timezone: '',
        privacyPolicyVersion: '1',
        trusted: false,
        tenantId: tenantId,
      );
  factory AttendanceTrackingSettings.fromJson(
    Map<String, dynamic> j, {
    required String tenantId,
    required bool trusted,
  }) {
    int bounded(dynamic v, int min, int max, int fallback) {
      final x = int.tryParse('$v');
      return x != null && x >= min && x <= max ? x : fallback;
    }

    String time(dynamic v, String f) =>
        RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch('$v') ? '$v' : f;
    final moving = bounded(j['gps_moving_interval_seconds'], 10, 3600, 15);
    final stationary = bounded(
      j['gps_stationary_interval_seconds'],
      moving,
      7200,
      60,
    );
    return AttendanceTrackingSettings(
      startMode: ['manual', 'automatic'].contains(j['work_session_start_mode'])
          ? '${j['work_session_start_mode']}'
          : 'manual',
      workdayStartTime: time(j['workday_start_time'], '08:00'),
      workdayEndTime: time(j['workday_end_time'], '17:00'),
      autoEndSession: j['auto_end_session'] == true,
      gpsTrackingEnabled: j['gps_tracking_enabled'] != false,
      movingSeconds: moving,
      stationarySeconds: stationary,
      staleMinutes: bounded(j['gps_stale_after_minutes'], 1, 720, 15),
      timezone: '${j['timezone'] ?? ''}',
      privacyPolicyVersion: '${j['privacy_policy_version'] ?? '1'}',
      trusted: trusted,
      tenantId: tenantId,
      fetchedAt: DateTime.now().toUtc(),
    );
  }
  Map<String, dynamic> toJson() => {
    'work_session_start_mode': startMode,
    'workday_start_time': workdayStartTime,
    'workday_end_time': workdayEndTime,
    'auto_end_session': autoEndSession,
    'gps_tracking_enabled': gpsTrackingEnabled,
    'gps_moving_interval_seconds': movingSeconds,
    'gps_stationary_interval_seconds': stationarySeconds,
    'gps_stale_after_minutes': staleMinutes,
    'timezone': timezone,
    'privacy_policy_version': privacyPolicyVersion,
    'trusted': trusted,
    'tenant_id': tenantId,
    'fetched_at': fetchedAt?.toIso8601String(),
  };
}
