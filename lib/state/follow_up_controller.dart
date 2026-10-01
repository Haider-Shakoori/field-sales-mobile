import 'package:flutter/foundation.dart';

import '../features/followups/follow_up_repository.dart';
import 'app_state.dart';

class FollowUpController extends ChangeNotifier {
  FollowUpController({required this.appState, required this.repository});

  final AppState appState;
  final FollowUpRepository repository;

  bool busy = false;
  String? message;
  String? loadedTenantId;
  int pending = 0;
  List<Map<String, dynamic>> followUps = const [];

  Future<void> reloadLocal() async {
    final tenantId = appState.session?.tenantId;
    if (tenantId == null) {
      loadedTenantId = null;
      followUps = const [];
      pending = 0;
      notifyListeners();
      return;
    }

    if (loadedTenantId != tenantId) {
      loadedTenantId = tenantId;
      followUps = const [];
    }
    followUps = await repository.list(tenantId);
    pending = await repository.pendingCount(tenantId);
    notifyListeners();
  }

  Future<void> sync({bool silent = false}) async {
    final tenantId = appState.session?.tenantId;
    if (tenantId == null || busy) return;

    if (!silent) {
      busy = true;
      message = null;
      notifyListeners();
    }

    try {
      final result = await repository.syncPending(tenantId);
      await repository.refresh(tenantId);
      await reloadLocal();
      if (!silent) {
        message = result.failed == 0
            ? 'Follow-up sync complete.'
            : 'Follow-up sync completed with ${result.failed} pending failure(s).';
      }
    } catch (_) {
      await reloadLocal();
      if (!silent) {
        message = 'Offline mode: cached follow-ups remain available.';
      }
    } finally {
      if (!silent) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> create({
    required Map<String, dynamic> customer,
    required String type,
    required String priority,
    required DateTime dueAt,
    String? notes,
  }) async {
    final tenantId = appState.session?.tenantId;
    if (tenantId == null || busy) return;

    busy = true;
    message = null;
    notifyListeners();

    try {
      await repository.createLocal(
        tenantId: tenantId,
        customer: customer,
        type: type,
        priority: priority,
        dueAt: dueAt,
        notes: notes,
      );
      await reloadLocal();
      message = 'Follow-up saved locally.';
      await sync(silent: true);
    } catch (error) {
      message = error.toString();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> updateStatus(
    Map<String, dynamic> followUp,
    String status, {
    String? completionNote,
  }) async {
    final tenantId = appState.session?.tenantId;
    final uuid = followUp['offline_uuid']?.toString();
    if (tenantId == null || uuid == null || busy) return;

    busy = true;
    message = null;
    notifyListeners();

    try {
      await repository.updateStatusLocal(
        tenantId: tenantId,
        offlineUuid: uuid,
        status: status,
        completionNote: completionNote,
      );
      await reloadLocal();
      message = status == 'completed'
          ? 'Follow-up completed locally.'
          : 'Follow-up cancelled locally.';
      await sync(silent: true);
    } catch (error) {
      message = error.toString();
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
