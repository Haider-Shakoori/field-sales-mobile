import 'package:flutter/foundation.dart';

import '../features/inventory/inventory_repository.dart';
import 'app_state.dart';

class InventoryController extends ChangeNotifier {
  InventoryController({required this.appState, required this.repository});

  final AppState appState;
  final InventoryRepository repository;

  bool busy = false;
  bool enabled = false;
  String? message;
  String? loadedTenantId;
  int pending = 0;
  List<Map<String, dynamic>> stock = const [];
  List<Map<String, dynamic>> returns = const [];

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
      enabled = false;
      pending = 0;
      stock = const [];
      returns = const [];
      notifyListeners();
      return;
    }

    loadedTenantId = tenantId;
    enabled = await repository.isEnabled(tenantId);
    stock = await repository.stock(tenantId);
    returns = await repository.returns(tenantId);
    pending = await repository.pendingReturnCount(tenantId);
    notifyListeners();
  }

  Future<void> createReturn({
    required Map<String, dynamic> customer,
    required String reason,
    required List<ReturnDraftLine> lines,
    String? visitUuid,
    Map<String, dynamic>? order,
    String? notes,
  }) async {
    final tenantId = appState.session?.tenantId;
    if (tenantId == null || busy) return;

    busy = true;
    message = null;
    notifyListeners();

    try {
      await repository.createReturnOffline(
        tenantId: tenantId,
        customer: customer,
        returnedAt: DateTime.now().toUtc(),
        reason: reason,
        lines: lines,
        visitUuid: visitUuid,
        order: order,
        notes: notes,
      );

      await reloadLocal();
      message = 'Return saved locally.';
      await sync(silent: true);
    } catch (error) {
      message = error.toString().replaceFirst('Bad state: ', '');
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
      final result = await repository.syncPendingReturns(tenantId);
      await repository.refreshReturnHistory(tenantId);
      await repository.refreshStock(tenantId);
      await reloadLocal();

      if (!silent) {
        message = result.failed == 0
            ? 'Inventory sync complete. ${result.synced} returns processed.'
            : 'Inventory sync completed with ${result.failed} failures.';
      }
    } catch (_) {
      await reloadLocal();
      if (!silent) {
        message = 'Offline mode: cached stock and returns remain available.';
      }
    } finally {
      if (!silent) {
        busy = false;
        notifyListeners();
      }
    }
  }
}
