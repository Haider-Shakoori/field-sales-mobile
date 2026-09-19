import 'package:flutter/foundation.dart';

import '../features/calls/call_activity_repository.dart';
import 'app_state.dart';

class CallActivityController extends ChangeNotifier {
  CallActivityController({required this.appState, required this.repository});

  final AppState appState;
  final CallActivityRepository repository;

  bool busy = false;
  String? message;
  String? loadedTenantId;
  int pending = 0;
  List<Map<String, dynamic>> activities = const [];

  Future<void> initialize() async {
    await reloadLocal();
    if (appState.signedIn) {
      await sync(silent: true);
    }
  }

  Future<void> reloadLocal() async {
    final tenantId = appState.session?.tenantId;

    if (tenantId == null) {
      loadedTenantId = null;
      pending = 0;
      activities = const [];
      notifyListeners();
      return;
    }

    if (loadedTenantId != tenantId) {
      loadedTenantId = tenantId;
      activities = const [];
    }

    activities = await repository.list(tenantId);
    pending = await repository.pendingCount(tenantId);
    notifyListeners();
  }

  Future<void> record({
    required Map<String, dynamic> customer,
    required String phoneNumber,
    required DateTime calledAt,
    String? outcome,
    String? notes,
  }) async {
    final tenantId = appState.session?.tenantId;
    if (tenantId == null || busy) return;

    busy = true;
    message = null;
    notifyListeners();

    try {
      await repository.recordLocal(
        tenantId: tenantId,
        customer: customer,
        phoneNumber: phoneNumber,
        calledAt: calledAt,
        outcome: outcome,
        notes: notes,
      );
      await reloadLocal();
      message = 'Call activity saved locally.';
      await sync(silent: true);
    } catch (error) {
      message = error.toString();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> sync({bool silent = false}) async {
    final tenantId = appState.session?.tenantId;
    if (tenantId == null) return;

    if (!silent) {
      busy = true;
      message = null;
      notifyListeners();
    }

    try {
      final result = await repository.syncPending(tenantId);
      await reloadLocal();

      if (!silent) {
        message = result.failed == 0
            ? 'Call activity sync complete. ${result.synced} records processed.'
            : 'Call activity sync completed with ${result.failed} pending failures.';
      }
    } catch (_) {
      await reloadLocal();
      if (!silent) {
        message = 'Offline mode: call activities remain stored locally.';
      }
    } finally {
      if (!silent) {
        busy = false;
        notifyListeners();
      }
    }
  }
}
