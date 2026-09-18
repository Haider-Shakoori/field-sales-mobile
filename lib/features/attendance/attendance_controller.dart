import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/api/api_exception.dart';
import '../../core/location/location_fix.dart';
import '../../core/location/location_permission_service.dart';
import '../../core/location/location_source.dart';
import '../../core/models/attendance.dart';
import '../../core/models/attendance_tracking_settings.dart';
import '../../core/models/gps_point.dart';
import '../../core/models/privacy_ack.dart';
import '../../core/models/time_utils.dart';
import '../../core/models/workday_window.dart';
import '../../core/permissions/notification_permission_service.dart';
import '../../core/storage/attendance_tracking_settings_repository.dart';
import '../../core/storage/privacy_ack_store.dart';
import '../../core/storage/secret_store.dart';
import '../../core/storage/work_session_repository.dart';
import '../../core/sync/connectivity_service.dart';
import '../../core/sync/sync_status.dart';
import '../../core/time/clock.dart';
import '../tracking/gps_tracking_config.dart';
import '../tracking/gps_tracking_service.dart';
import '../tracking/gps_upload_service.dart';
import 'attendance_sync_service.dart';
import 'boundary_scheduler.dart';

enum StartDayOutcome {
  started,
  alreadyActive,
  needsPrivacyAck,
  servicesDisabled,
  permissionDenied,
  permissionPermanentlyDenied,
  locationUnavailable,
  failed,
}

class StartDayResult {
  const StartDayResult(
    this.outcome, {
    this.message,
    this.backgroundAccess = BackgroundLocationAccess.unsupported,
    this.notificationPermissionGranted = true,
    this.trackingStarted = false,
    this.gpsTrackingEnabled = true,
  });

  final StartDayOutcome outcome;
  final String? message;
  final BackgroundLocationAccess backgroundAccess;
  final bool notificationPermissionGranted;
  final bool trackingStarted;
  final bool gpsTrackingEnabled;

  bool get isSuccess => outcome == StartDayOutcome.started;
}

enum EndDayOutcome { ended, notActive, failed }

class EndDayResult {
  const EndDayResult(this.outcome, {this.message, this.usedFallback = false});

  final EndDayOutcome outcome;
  final String? message;

  /// True when the final fix came from the recent-point / session-start
  /// fallback instead of a fresh GPS read.
  final bool usedFallback;

  bool get isSuccess => outcome == EndDayOutcome.ended;
}

enum TrackingPauseReason {
  none,
  signedOut,
  permissionMissing,
  servicesDisabled,
  noAcknowledgement,
  authorizationLost,
  gpsDisabled,
  failed,
}

/// Why automatic attendance is (not) running, for the dashboard UI.
enum AutomaticPolicyState {
  notSignedIn,

  /// Company policy is manual — the Start Day button is the only trigger.
  manual,

  /// Automatic mode, currently before the configured window.
  waitingForSchedule,

  /// Automatic mode, the configured window for today has already closed.
  outsideSchedule,

  /// Inside the window, but the tracking disclosure is not acknowledged.
  waitingForPrivacy,

  /// Inside the window, but foreground location permission is missing.
  waitingForPermission,

  /// Inside the window, but device location services are disabled.
  waitingForServices,

  /// Inside the window, but no acceptable GPS fix could be obtained.
  waitingForLocation,

  /// Automatic mode with `gpsTrackingEnabled = false`; no auto start.
  gpsDisabled,

  /// Automatic start is in progress (permissions + fix + local commit).
  starting,

  /// An active session exists (manual or automatic).
  active,

  /// Automatic evaluation hit an unexpected error.
  failed,
}

/// Freshness of the latest accepted GPS point.
enum TrackingFreshness { noLocationYet, fresh, stale }

/// Orchestrates the offline-first Start Day / End Day lifecycle and the
/// tracking state machine for the UI.
///
/// Local SQLite is authoritative: Start Day commits locally before any network
/// attempt, the UI updates immediately, and server sync failures never roll the
/// work session back.
///
/// Company policy ([AttendanceTrackingSettings]) is cached locally and obeyed
/// offline. Without a trusted server payload the controller stays on the
/// verified Batch 7 MANUAL behaviour.
class AttendanceController extends ChangeNotifier {
  AttendanceController({
    required WorkSessionRepository workSessions,
    required PrivacyAckStore privacyAcks,
    required LocationPermissionService permissions,
    required LocationSource locationSource,
    required GpsTrackingService tracking,
    required GpsUploadService gpsUpload,
    required AttendanceSyncService attendanceSync,
    required ConnectivityService connectivity,
    required SecretStore secureStorage,
    required NotificationPermissionService notificationPermissions,
    AttendanceTrackingSettingsRepository? settingsRepository,
    Clock clock = const Clock(),
    BoundaryScheduler? boundaryScheduler,
    this.config = const GpsTrackingConfig(),
    String appVersion = '1.0.0',
  }) : _workSessions = workSessions,
       _privacyAcks = privacyAcks,
       _permissions = permissions,
       _locationSource = locationSource,
       _tracking = tracking,
       _gpsUpload = gpsUpload,
       _attendanceSync = attendanceSync,
       _connectivity = connectivity,
       _secureStorage = secureStorage,
       _notificationPermissions = notificationPermissions,
       _settingsRepository =
           settingsRepository ?? AttendanceTrackingSettingsRepository.instance,
       _clock = clock,
       _boundaryScheduler = boundaryScheduler ?? TimerBoundaryScheduler(),
       _appVersion = appVersion {
    _tracking.addListener(_onTrackingChanged);
    _gpsUpload.onAuthorizationLost = _handleAuthorizationLost;
    _attendanceSync.onAuthorizationLost = _handleAuthorizationLost;
    _connectivitySub = _connectivity.states.listen(_onNetworkChanged);
  }

  final WorkSessionRepository _workSessions;
  final PrivacyAckStore _privacyAcks;
  final LocationPermissionService _permissions;
  final LocationSource _locationSource;
  final GpsTrackingService _tracking;
  final GpsUploadService _gpsUpload;
  final AttendanceSyncService _attendanceSync;
  final ConnectivityService _connectivity;
  final SecretStore _secureStorage;
  final NotificationPermissionService _notificationPermissions;
  final AttendanceTrackingSettingsRepository _settingsRepository;
  final Clock _clock;
  final BoundaryScheduler _boundaryScheduler;
  final GpsTrackingConfig config;
  final String _appVersion;

  StreamSubscription<NetworkState>? _connectivitySub;

  LocalWorkSession? _activeSession;
  LocalWorkSession? get activeSession => _activeSession;
  bool get hasActiveSession => _activeSession != null;

  LocalWorkSession? _completedToday;
  LocalWorkSession? get completedToday => _completedToday;

  bool _restoring = true;
  bool get restoring => _restoring;

  bool _privacyAcknowledged = false;
  bool get privacyAcknowledged => _privacyAcknowledged;
  GpsPrivacyAcknowledgement? get acknowledgement => _acknowledgement;
  GpsPrivacyAcknowledgement? _acknowledgement;

  bool _signedIn = false;
  bool get signedIn => _signedIn;

  bool _authorizationLost = false;
  bool get authorizationLost => _authorizationLost;

  TrackingPauseReason _pauseReason = TrackingPauseReason.none;
  TrackingPauseReason get pauseReason => _pauseReason;

  String? _lastError;
  String? get lastError => _lastError;

  int? _userId;
  int? _tenantId;

  // ---------------------------------------------------------------------------
  // Company settings / automatic policy
  // ---------------------------------------------------------------------------

  SettingsLoadResult _settingsLoad = const SettingsLoadResult(
    settings: AttendanceTrackingSettings.defaults(),
    source: SettingsSource.defaults,
  );
  AttendanceTrackingSettings _settings =
      const AttendanceTrackingSettings.defaults();
  WorkdayWindow? _window;
  AutomaticPolicyState _automaticState = AutomaticPolicyState.notSignedIn;

  bool _autoEvaluationInFlight = false;
  bool _autoEndInFlight = false;

  AttendanceTrackingSettings get settings => _settings;
  AttendanceTrackingSettingsRepository get settingsRepository =>
      _settingsRepository;

  /// True only when a trusted server payload has been cached and is in use.
  bool get settingsTrusted => _settingsLoad.trusted;
  List<String> get settingsIssues => _settingsLoad.issues;
  bool get automaticMode => _settings.isAutomatic;
  bool get gpsTrackingEnabled => _settings.gpsTrackingEnabled;
  AutomaticPolicyState get automaticState => _automaticState;
  WorkdayWindow? get workdayWindow => _window;
  String? get workdayStartLabel => _window?.startLabel;
  String? get workdayEndLabel => _window?.endLabel;

  /// Freshness of the latest accepted point against `gpsStaleAfterMinutes`.
  TrackingFreshness get trackingFreshness {
    final last = _tracking.lastAcceptedPoint;
    if (last == null) {
      return TrackingFreshness.noLocationYet;
    }
    final age = _clock.now().toUtc().difference(last.recordedAt);
    return age > Duration(minutes: _settings.gpsStaleAfterMinutes)
        ? TrackingFreshness.stale
        : TrackingFreshness.fresh;
  }

  /// Tracking service state, mirrored for convenient widget access.
  TrackingState get trackingState => _tracking.state;
  bool get isTracking => _tracking.isTracking;
  LocalGpsPoint? get lastGpsPoint => _tracking.lastAcceptedPoint;
  int get pendingGpsCount => _tracking.pendingCount;
  GpsUploadService get gpsUploader => _gpsUpload;

  List<LocalWorkSession> _history = const [];
  List<LocalWorkSession> get history => _history;

  bool _historyLoading = false;
  bool get historyLoading => _historyLoading;

  /// Loads local attendance state at app start. Never starts tracking by
  /// itself — [setSignedIn] performs the safe reconciliation once the auth
  /// state is known.
  Future<void> restore() async {
    _restoring = true;
    notifyListeners();
    try {
      _acknowledgement = await _privacyAcks.load();
      _privacyAcknowledged =
          _acknowledgement != null &&
          _acknowledgement!.policyVersion == kGpsTrackingPolicyVersion;
      _activeSession = await _workSessions.activeSession();
      _completedToday = _activeSession == null
          ? await _recentCompletedToday()
          : null;
      await _tracking.restoreLastPoint();
      await _tracking.refreshPendingCount();
      await reloadSettings();
    } finally {
      _restoring = false;
      notifyListeners();
    }
    if (_signedIn) {
      await _reconcileTracking();
      await evaluateAutomaticPolicy();
    }
  }

  /// Called by [AppState] whenever the auth state is known/changes.
  Future<void> setSignedIn(bool signedIn) async {
    _signedIn = signedIn;
    if (signedIn) {
      _authorizationLost = false;
      await _attendanceSync.resetFailedEntries();
      await reloadSettings(refreshFromServer: true);
      unawaited(_flushPending());
      await _reconcileTracking();
      await evaluateAutomaticPolicy();
    } else {
      _automaticState = AutomaticPolicyState.notSignedIn;
      _boundaryScheduler.cancel();
      notifyListeners();
    }
  }

  void updateIdentity({int? userId, int? tenantId}) {
    _userId = userId ?? _userId;
    _tenantId = tenantId ?? _tenantId;
  }

  /// (Re)loads the cached company policy. When [refreshFromServer] is true the
  /// repository's future Laravel transport is asked first; with no transport
  /// bound (production today) this is identical to a cache read.
  Future<SettingsLoadResult> reloadSettings({
    bool refreshFromServer = false,
  }) async {
    final result = refreshFromServer
        ? await _settingsRepository.refreshFromServer(tenantId: _tenantId)
        : await _settingsRepository.load(tenantId: _tenantId);
    _applySettings(result);
    return result;
  }

  void _applySettings(SettingsLoadResult result) {
    _settingsLoad = result;
    _settings = result.settings;
    _window = WorkdayWindow.fromSettings(_settings);
    _tracking.applyConfig(GpsTrackingConfig.fromSettings(_settings));

    if (!_settings.gpsTrackingEnabled && _tracking.isTracking) {
      unawaited(_stopTrackingForGpsPolicy());
    } else if (_settings.gpsTrackingEnabled &&
        _pauseReason == TrackingPauseReason.gpsDisabled) {
      _pauseReason = TrackingPauseReason.none;
    } else if (!_settings.gpsTrackingEnabled &&
        _activeSession != null &&
        _pauseReason == TrackingPauseReason.none) {
      _pauseReason = TrackingPauseReason.gpsDisabled;
    }
    notifyListeners();
  }

  Future<void> _stopTrackingForGpsPolicy() async {
    _pauseReason = TrackingPauseReason.gpsDisabled;
    await _tracking.stop();
    _gpsUpload.stopPeriodicFlush();
    notifyListeners();
  }

  /// Lifecycle hook: the app was resumed to the foreground. Re-evaluates the
  /// automatic policy and re-arms the single boundary timer.
  Future<void> onAppResumed() async {
    if (!_signedIn || _restoring) {
      return;
    }
    await evaluateAutomaticPolicy();
  }

  /// Central automatic-policy evaluation. Safe to call from every trigger:
  /// startup/session restore, app resume, settings reload and the work-window
  /// boundary timer. It never prompts for permissions; missing prerequisites
  /// are surfaced as an actionable state instead.
  Future<void> evaluateAutomaticPolicy() async {
    if (_restoring || _autoEvaluationInFlight) {
      return;
    }
    _autoEvaluationInFlight = true;
    try {
      if (!_signedIn) {
        _setAutomaticState(AutomaticPolicyState.notSignedIn);
        _boundaryScheduler.cancel();
        return;
      }

      final window = _window;

      // An existing active session always takes priority over auto-start.
      if (_activeSession != null) {
        await _maybeAutoEnd(window);
        _setAutomaticState(
          _activeSession == null
              ? _onNoSessionState(window)
              : AutomaticPolicyState.active,
        );
        _rescheduleBoundaryTimer();
        return;
      }

      if (!_settings.isAutomatic) {
        _setAutomaticState(AutomaticPolicyState.manual);
        _rescheduleBoundaryTimer();
        return;
      }

      if (!_settings.gpsTrackingEnabled) {
        _setAutomaticState(AutomaticPolicyState.gpsDisabled);
        _rescheduleBoundaryTimer();
        return;
      }

      if (window == null) {
        _setAutomaticState(AutomaticPolicyState.failed);
        return;
      }

      final now = _clock.now();
      if (!window.contains(now)) {
        _setAutomaticState(
          window.isBeforeStart(now)
              ? AutomaticPolicyState.waitingForSchedule
              : AutomaticPolicyState.outsideSchedule,
        );
        _rescheduleBoundaryTimer();
        return;
      }

      if (!_privacyAcknowledged) {
        _setAutomaticState(AutomaticPolicyState.waitingForPrivacy);
        _rescheduleBoundaryTimer();
        return;
      }

      if (!await _permissions.isServiceEnabled()) {
        _setAutomaticState(AutomaticPolicyState.waitingForServices);
        _rescheduleBoundaryTimer();
        return;
      }

      final permission = await _permissions.checkForeground();
      if (!permission.granted) {
        _setAutomaticState(AutomaticPolicyState.waitingForPermission);
        _rescheduleBoundaryTimer();
        return;
      }

      _setAutomaticState(AutomaticPolicyState.starting);
      final result = await startDay(
        source: WorkSessionStartSource.automatic,
        requestPermissions: false,
      );
      _setAutomaticState(_stateForStartResult(result));
      _rescheduleBoundaryTimer();
    } finally {
      _autoEvaluationInFlight = false;
      notifyListeners();
    }
  }

  AutomaticPolicyState _stateForStartResult(
    StartDayResult result,
  ) => switch (result.outcome) {
    StartDayOutcome.started ||
    StartDayOutcome.alreadyActive => AutomaticPolicyState.active,
    StartDayOutcome.needsPrivacyAck => AutomaticPolicyState.waitingForPrivacy,
    StartDayOutcome.servicesDisabled => AutomaticPolicyState.waitingForServices,
    StartDayOutcome.permissionDenied ||
    StartDayOutcome.permissionPermanentlyDenied =>
      AutomaticPolicyState.waitingForPermission,
    StartDayOutcome.locationUnavailable =>
      AutomaticPolicyState.waitingForLocation,
    StartDayOutcome.failed => AutomaticPolicyState.failed,
  };

  AutomaticPolicyState _onNoSessionState(WorkdayWindow? window) {
    if (!_settings.isAutomatic) {
      return AutomaticPolicyState.manual;
    }
    if (!_settings.gpsTrackingEnabled) {
      return AutomaticPolicyState.gpsDisabled;
    }
    final now = _clock.now();
    if (window == null) {
      return AutomaticPolicyState.failed;
    }
    if (window.contains(now)) {
      return _privacyAcknowledged
          ? AutomaticPolicyState.waitingForLocation
          : AutomaticPolicyState.waitingForPrivacy;
    }
    return window.isBeforeStart(now)
        ? AutomaticPolicyState.waitingForSchedule
        : AutomaticPolicyState.outsideSchedule;
  }

  Future<void> _maybeAutoEnd(WorkdayWindow? window) async {
    if (!_settings.autoEndSession ||
        window == null ||
        _autoEndInFlight ||
        _activeSession == null) {
      return;
    }
    final now = _clock.now();
    if (window.contains(now)) {
      return;
    }
    // Never auto-end a session that was started outside the window (e.g. a
    // manual late start); only sessions begun inside the company window are
    // closed by the automatic policy.
    if (!window.contains(_activeSession!.startTime.toLocal())) {
      return;
    }

    _autoEndInFlight = true;
    try {
      await endDay();
    } finally {
      _autoEndInFlight = false;
    }
  }

  void _rescheduleBoundaryTimer() {
    _boundaryScheduler.cancel();
    if (!_signedIn || _window == null) {
      return;
    }
    if (!_settings.isAutomatic && !_settings.autoEndSession) {
      return;
    }
    final delay = _window!.nextBoundaryDelay(_clock.now());
    if (delay == null) {
      return;
    }
    _boundaryScheduler.schedule(delay, () {
      unawaited(evaluateAutomaticPolicy());
    });
  }

  void _setAutomaticState(AutomaticPolicyState state) {
    if (_automaticState == state) {
      return;
    }
    _automaticState = state;
    notifyListeners();
  }

  /// Persists the GPS tracking disclosure acknowledgement locally (structured
  /// so it can be pushed to the server audit log later).
  Future<GpsPrivacyAcknowledgement> acknowledgePrivacy() async {
    final acknowledgement = GpsPrivacyAcknowledgement(
      acknowledgedAt: _clock.now().toUtc(),
      userId: _userId,
      tenantId: _tenantId,
      deviceUuid: await _secureStorage.readInstallationUuid(),
      appVersion: _appVersion,
    );
    await _privacyAcks.save(acknowledgement);
    _acknowledgement = acknowledgement;
    _privacyAcknowledged = true;
    notifyListeners();
    return acknowledgement;
  }

  /// The single Start Day flow used by BOTH manual taps and automatic policy.
  ///
  /// [requestPermissions] is false for automatic starts: the automatic path
  /// must never silently pop Android permission dialogs; it surfaces
  /// [AutomaticPolicyState.waitingForPermission] instead.
  Future<StartDayResult> startDay({
    bool privacyAlreadyAcknowledged = false,
    WorkSessionStartSource source = WorkSessionStartSource.manual,
    bool requestPermissions = true,
  }) async {
    if (_activeSession != null) {
      return const StartDayResult(StartDayOutcome.alreadyActive);
    }

    if (!_privacyAcknowledged) {
      if (!privacyAlreadyAcknowledged) {
        return const StartDayResult(StartDayOutcome.needsPrivacyAck);
      }
      await acknowledgePrivacy();
    }

    if (!await _permissions.isServiceEnabled()) {
      return const StartDayResult(StartDayOutcome.servicesDisabled);
    }

    var permission = await _permissions.checkForeground();
    if (!permission.granted && requestPermissions) {
      permission = await _permissions.requestForeground();
    }
    if (permission == LocationPermissionStatus.deniedForever) {
      return const StartDayResult(StartDayOutcome.permissionPermanentlyDenied);
    }
    if (!permission.granted) {
      return const StartDayResult(StartDayOutcome.permissionDenied);
    }

    // The foreground-service notification is part of the tracking disclosure;
    // manual starts ask for the Android 13+ permission in context.
    var notificationPermissionGranted = true;
    if (!await _notificationPermissions.isGranted()) {
      notificationPermissionGranted = requestPermissions
          ? await _notificationPermissions.request()
          : false;
    }

    final background = await _permissions.checkBackground();
    final gpsEnabled = _settings.gpsTrackingEnabled;

    final fix = await _locationSource.currentFix(
      timeout: config.startFixTimeout,
    );
    if (fix == null) {
      return StartDayResult(
        StartDayOutcome.locationUnavailable,
        backgroundAccess: background,
        notificationPermissionGranted: notificationPermissionGranted,
        gpsTrackingEnabled: gpsEnabled,
      );
    }

    try {
      final session = await _workSessions.startSession(
        latitude: fix.latitude,
        longitude: fix.longitude,
        accuracy: fix.accuracy,
        privacyAckAt: _acknowledgement == null
            ? null
            : utcIso(_acknowledgement!.acknowledgedAt),
        startedAt: _clock.now(),
        source: source,
      );
      _activeSession = session;
      _completedToday = null;
      _authorizationLost = false;
      _pauseReason = TrackingPauseReason.none;
      _lastError = null;
      notifyListeners();

      var trackingStarted = false;
      if (gpsEnabled) {
        try {
          await _tracking.start(initialFix: fix);
          _gpsUpload.startPeriodicFlush();
          trackingStarted = true;
        } catch (error) {
          _lastError = error.toString();
          _pauseReason = TrackingPauseReason.failed;
        }
      } else {
        // Attendance remains active; continuous GPS is disabled by policy.
        _pauseReason = TrackingPauseReason.gpsDisabled;
      }
      await _tracking.refreshPendingCount();
      _setAutomaticState(AutomaticPolicyState.active);
      _rescheduleBoundaryTimer();
      notifyListeners();

      unawaited(_flushPending());
      return StartDayResult(
        StartDayOutcome.started,
        backgroundAccess: background,
        notificationPermissionGranted: notificationPermissionGranted,
        trackingStarted: trackingStarted,
        gpsTrackingEnabled: gpsEnabled,
      );
    } on ActiveSessionExistsException {
      _activeSession = await _workSessions.activeSession();
      _setAutomaticState(AutomaticPolicyState.active);
      notifyListeners();
      return const StartDayResult(StartDayOutcome.alreadyActive);
    } catch (error) {
      _lastError = error.toString();
      notifyListeners();
      return StartDayResult(StartDayOutcome.failed, message: error.toString());
    }
  }

  Future<EndDayResult> endDay() async {
    final session = _activeSession ?? await _workSessions.activeSession();
    if (session == null) {
      return const EndDayResult(EndDayOutcome.notActive);
    }

    var usedFallback = false;
    final now = _clock.now().toUtc();
    var fix = await _locationSource.currentFix(
      timeout: config.endFixTimeout,
      accuracy: LocationAccuracyPreset.balanced,
    );
    if (fix == null) {
      final recent = _tracking.lastAcceptedPoint;
      if (recent != null &&
          now.difference(recent.recordedAt) <= config.recentFixMaxAge) {
        fix = LocationFix(
          latitude: recent.latitude,
          longitude: recent.longitude,
          accuracy: recent.accuracy,
          recordedAt: now,
        );
      } else {
        // Last resort so the salesman is never trapped: close the session at
        // its start coordinates.
        fix = LocationFix(
          latitude: session.startLatitude,
          longitude: session.startLongitude,
          accuracy: session.startAccuracy,
          recordedAt: now,
        );
      }
      usedFallback = true;
    }

    await _tracking.stop();
    _gpsUpload.stopPeriodicFlush();

    try {
      final closed = await _workSessions.endSession(
        session: session,
        latitude: fix.latitude,
        longitude: fix.longitude,
        accuracy: fix.accuracy,
        endedAt: now,
      );
      _activeSession = null;
      _completedToday = closed;
      _pauseReason = TrackingPauseReason.none;
      _setAutomaticState(_onNoSessionState(_window));
      _rescheduleBoundaryTimer();
      notifyListeners();
      unawaited(_flushPending(uploadGps: true));
      return EndDayResult(EndDayOutcome.ended, usedFallback: usedFallback);
    } on NoActiveSessionException {
      _activeSession = null;
      _completedToday = await _recentCompletedToday();
      _setAutomaticState(_onNoSessionState(_window));
      notifyListeners();
      return const EndDayResult(EndDayOutcome.notActive);
    } catch (error) {
      _lastError = error.toString();
      notifyListeners();
      return EndDayResult(EndDayOutcome.failed, message: error.toString());
    }
  }

  /// Stops tracking on logout without deleting any local attendance/GPS data.
  Future<void> stopTrackingForLogout() async {
    _signedIn = false;
    _automaticState = AutomaticPolicyState.notSignedIn;
    _boundaryScheduler.cancel();
    await _tracking.stop();
    _gpsUpload.stopPeriodicFlush();
    if (_pauseReason == TrackingPauseReason.none) {
      _pauseReason = TrackingPauseReason.signedOut;
    }
    notifyListeners();
  }

  Future<void> refreshPendingGpsCount() async {
    await _tracking.refreshPendingCount();
    notifyListeners();
  }

  /// Re-attempts tracking when a session is active but collection is paused
  /// (permission granted later, services re-enabled, tracking start failed).
  Future<void> resumeTracking() async {
    await _reconcileTracking();
    notifyListeners();
  }

  /// Re-runs the automatic evaluation after the user satisfied a prerequisite
  /// (for example acknowledged the disclosure). Never prompts by itself.
  Future<void> retryAutomaticStart() => evaluateAutomaticPolicy();

  Future<bool> openAppSettings() => _permissions.openAppSettings();

  Future<bool> openLocationSettings() => _permissions.openLocationSettings();

  Future<BackgroundLocationAccess> requestBackgroundAccess() =>
      _permissions.requestBackground();

  Future<List<LocalWorkSession>> loadHistory({int limit = 30}) async {
    _historyLoading = true;
    notifyListeners();
    try {
      _history = await _workSessions.recent(limit: limit);
      return _history;
    } finally {
      _historyLoading = false;
      notifyListeners();
    }
  }

  /// Attempts the attendance outbox and (optionally) the GPS buffer exactly
  /// once — used after Start/End Day and when connectivity returns.
  Future<void> flushPendingNow({bool uploadGps = true}) =>
      _flushPending(uploadGps: uploadGps);

  Future<void> _flushPending({bool uploadGps = false}) async {
    if (!_signedIn || _authorizationLost || !_connectivity.isOnline) {
      return;
    }
    try {
      await _attendanceSync.flushPending();
      if (uploadGps) {
        await _gpsUpload.flush();
      }
    } catch (error) {
      _lastError = error.toString();
    } finally {
      await _tracking.refreshPendingCount();
      notifyListeners();
    }
  }

  Future<void> _reconcileTracking() async {
    if (_activeSession == null) {
      await _tracking.stop();
      _gpsUpload.stopPeriodicFlush();
      _pauseReason = TrackingPauseReason.none;
      return;
    }
    if (!_signedIn) {
      _pauseReason = TrackingPauseReason.signedOut;
      await _tracking.stop();
      return;
    }
    if (!_privacyAcknowledged) {
      _pauseReason = TrackingPauseReason.noAcknowledgement;
      await _tracking.stop();
      return;
    }
    if (!_settings.gpsTrackingEnabled) {
      _pauseReason = TrackingPauseReason.gpsDisabled;
      await _tracking.stop();
      _gpsUpload.stopPeriodicFlush();
      return;
    }
    if (!await _permissions.isServiceEnabled()) {
      _pauseReason = TrackingPauseReason.servicesDisabled;
      await _tracking.stop();
      return;
    }
    final permission = await _permissions.checkForeground();
    if (!permission.granted) {
      _pauseReason = TrackingPauseReason.permissionMissing;
      await _tracking.stop();
      return;
    }

    _pauseReason = TrackingPauseReason.none;
    if (!_tracking.isTracking) {
      try {
        await _tracking.start();
        _gpsUpload.startPeriodicFlush();
      } catch (error) {
        _lastError = error.toString();
        _pauseReason = TrackingPauseReason.failed;
      }
    }
  }

  Future<void> _handleAuthorizationLost(ApiException error) async {
    _authorizationLost = true;
    _lastError = error.message;
    _pauseReason = TrackingPauseReason.authorizationLost;
    // Stop collecting, but keep every unsynced point and attendance row.
    await _tracking.stop();
    _gpsUpload.stopPeriodicFlush();
    notifyListeners();
  }

  void _onNetworkChanged(NetworkState state) {
    if (_signedIn && state == NetworkState.online) {
      unawaited(_flushPending());
    }
  }

  void _onTrackingChanged() {
    notifyListeners();
  }

  Future<LocalWorkSession?> _recentCompletedToday() async {
    final session = await _workSessions.sessionForDay(_clock.now());
    return session != null && session.status == WorkSessionStatus.completed
        ? session
        : null;
  }

  @override
  void dispose() {
    _boundaryScheduler.cancel();
    _connectivitySub?.cancel();
    _tracking.removeListener(_onTrackingChanged);
    _gpsUpload.dispose();
    super.dispose();
  }
}
