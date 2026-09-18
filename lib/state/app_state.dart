import 'package:flutter/foundation.dart';

import '../core/api/api_exception.dart';
import '../core/api/auth_repository.dart';
import '../core/models/session.dart';
import '../core/storage/secret_store.dart';
import '../core/storage/session_meta_store.dart';
import '../core/sync/sync_controller.dart';
import '../features/attendance/attendance_controller.dart';

/// Root application state: whether the user is signed in and the current
/// session. The UI flips between the login flow and the home shell based on
/// [session].
class AppState extends ChangeNotifier {
  AppState({
    required AuthRepository auth,
    required SyncController sync,
    required SecretStore secureStorage,
    required SessionMetaStore sessionMeta,
    required AttendanceController attendance,
  }) : _auth = auth,
       _sync = sync,
       _secureStorage = secureStorage,
       _sessionMeta = sessionMeta,
       _attendance = attendance;

  final AuthRepository _auth;
  final SyncController _sync;
  final SecretStore _secureStorage;
  final SessionMetaStore _sessionMeta;
  final AttendanceController _attendance;

  Session? _session;
  bool get isSignedIn => _session != null;
  Session? get session => _session;

  bool _restoring = true;
  bool get restoring => _restoring;

  /// Restores the persisted token and the last cached user/tenant metadata so
  /// identity is available offline without a server round trip.
  Future<void> restore() async {
    _restoring = true;
    notifyListeners();
    final token = await _secureStorage.readToken();
    _restoring = false;
    if (token != null && token.isNotEmpty) {
      final meta = await _sessionMeta.load();
      _session = Session(
        token: token,
        user: meta.user,
        tenant: meta.tenant,
        permissions: meta.permissions,
      );
      _attendance.updateIdentity(
        userId: meta.user.key,
        tenantId: meta.tenant.key,
      );
      notifyListeners();
      await _attendance.setSignedIn(true);
      return;
    }
    notifyListeners();
    await _attendance.setSignedIn(false);
  }

  Future<void> signIn({
    required String email,
    required String password,
    String pushToken = '',
  }) async {
    final session = await _auth.login(
      email: email,
      password: password,
      pushToken: pushToken,
    );
    await _sessionMeta.save(session);
    _session = session;
    _attendance.updateIdentity(
      userId: session.user.key,
      tenantId: session.tenant.key,
    );
    notifyListeners();
    await _sync.maybeSync();
    await _attendance.setSignedIn(true);
  }

  /// Maps transport failures to friendly codes for the login form.
  String friendlyError(Object error) {
    if (error is ApiException) {
      if (error.isDeviceRevoked) {
        return 'DEVICE_REVOKED';
      }
      if (error.isUpgradeRequired) {
        return 'UPDATE_REQUIRED';
      }
      if (error.isUnauthenticated) {
        return 'INVALID_CREDENTIALS';
      }
      if (error.status == 403) {
        return 'DEACTIVATED';
      }
      if (error.retryable) {
        return 'NETWORK';
      }
      return error.message;
    }
    return error.toString();
  }

  Future<void> signOut() async {
    final auth = _auth;
    final sync = _sync;
    // Stop GPS tracking before the token is cleared so no foreground service
    // keeps collecting after logout. Local attendance/GPS rows are preserved.
    await _attendance.stopTrackingForLogout();
    await auth.logout();
    await _sessionMeta.clear();
    _session = null;
    notifyListeners();
    await sync.maybeSync();
  }
}
