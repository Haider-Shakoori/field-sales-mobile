import 'dart:async';

import 'package:flutter/foundation.dart';

import '../features/auth/auth_repository.dart';
import '../features/settings/attendance_tracking_settings.dart';
import '../features/settings/settings_repository.dart';

class AppState extends ChangeNotifier {
  AppState({required this.auth, required this.settings});
  final AuthRepository auth;
  final SettingsRepository settings;
  bool restored = false;
  AuthSession? session;
  AttendanceTrackingSettings? policy;
  bool get signedIn => session != null;

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

  Future<void> _beat() async {
    if (_beatInFlight) return;
    _beatInFlight = true;

    try {
      await auth.me();
    } catch (_) {
    } finally {
      _beatInFlight = false;
    }
  }

  Future<void> restore() async {
    session = await auth.restore();
    if (session != null) policy = await settings.load(session!.tenantId);
    restored = true;
    _syncHeartbeat();
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    session = await auth.login(email, password);
    policy = await settings.refresh(session!.tenantId);
    _syncHeartbeat();
    notifyListeners();
  }

  Future<void> refreshPolicy() async {
    if (session == null) return;
    policy = await settings.refresh(session!.tenantId);
    notifyListeners();
  }

  Future<void> logout() async {
    _syncHeartbeat();
    await auth.logout();
    session = null;
    policy = null;
    notifyListeners();
  }

  Future<void> revokeLocal() async {
    _syncHeartbeat();
    await auth.clearLocalAuth();
    session = null;
    policy = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    super.dispose();
  }
}
