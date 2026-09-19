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
  Future<void> restore() async {
    session = await auth.restore();
    if (session != null) policy = await settings.load(session!.tenantId);
    restored = true;
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    session = await auth.login(email, password);
    policy = await settings.refresh(session!.tenantId);
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
    notifyListeners();
  }

  Future<void> revokeLocal() async {
    await auth.clearLocalAuth();
    session = null;
    policy = null;
    notifyListeners();
  }
}
