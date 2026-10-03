import 'dart:async';

import 'package:flutter/foundation.dart';

import '../features/auth/auth_repository.dart';
import '../features/devices/device_health_repository.dart';
import '../features/settings/attendance_tracking_settings.dart';
import '../features/settings/settings_repository.dart';

class AppState extends ChangeNotifier {
  AppState({required this.auth, required this.settings, this.deviceHealth});

  final AuthRepository auth;
  final SettingsRepository settings;
  final DeviceHealthRepository? deviceHealth;
  bool restored = false;
  AuthSession? session;
  AttendanceTrackingSettings? policy;
  bool gamificationEnabled = false;
  String? authNotice;
  bool get signedIn => session != null;
  bool get isSalesman => session?.isSalesman == true;
  bool get isSupervisor => session?.isSupervisor == true;
  bool get isSalesManager => session?.isSalesManager == true;
  bool get isLeadership => session?.isLeadership == true;

  Timer? _heartbeat;
  bool _beatInFlight = false;

  void _syncHeartbeat() {
    if (session == null) {
      _heartbeat?.cancel();
      _heartbeat = null;
      return;
    }

    _heartbeat ??= Timer.periodic(const Duration(minutes: 3), (_) => _beat());
    _beat();
  }

  Future<void> heartbeatNow() => _beat();

  Future<void> _beat() async {
    if (_beatInFlight) return;
    _beatInFlight = true;

    try {
      await auth.me();
    } catch (_) {
      // Presence heartbeat is best-effort while offline.
    }

    final tenantId = session?.tenantId;
    final health = deviceHealth;
    if (tenantId != null && health != null) {
      try {
        await health.report(tenantId);
      } catch (_) {
        // Health reporting must never interrupt normal FieldPulse work.
      }
    }

    _beatInFlight = false;
  }

  Future<void> restore() async {
    session = await auth.restore();
    if (session != null) {
      policy = await settings.load(session!.tenantId);
      final features = await settings.features();
      gamificationEnabled = features['gamification_enabled'] == true;
    }
    restored = true;
    _syncHeartbeat();
    notifyListeners();
  }

  Future<String?> lastTenantCode() => auth.lastTenantCode();

  Future<void> login(String email, String password, {String? tenant}) async {
    session = await auth.login(email, password, tenant: tenant);
    authNotice = null;
    policy = await settings.refresh(session!.tenantId);
    final features = await settings.features();
    gamificationEnabled = features['gamification_enabled'] == true;
    _syncHeartbeat();
    notifyListeners();
  }

  Future<void> refreshPolicy() async {
    if (session == null) return;
    policy = await settings.refresh(session!.tenantId);
    notifyListeners();
  }

  Future<void> logout() async {
    await auth.logout();
    session = null;
    policy = null;
    gamificationEnabled = false;
    authNotice = null;
    _syncHeartbeat();
    notifyListeners();
  }

  Future<void> revokeLocal({String? notice}) async {
    _heartbeat?.cancel();
    _heartbeat = null;
    await auth.clearLocalAuth();
    session = null;
    policy = null;
    gamificationEnabled = false;
    authNotice = notice;
    notifyListeners();
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    super.dispose();
  }
}
