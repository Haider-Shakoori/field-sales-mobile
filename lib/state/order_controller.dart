import 'package:flutter/foundation.dart';

import '../features/orders/order_repository.dart';
import 'app_state.dart';

class OrderController extends ChangeNotifier {
  OrderController({required this.appState, required this.repository});

  final AppState appState;
  final OrderRepository repository;

  bool busy = false;
  String? message;
  String? loadedTenantId;
  int pending = 0;
  List<Map<String, dynamic>> orders = const [];

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
      orders = const [];
      pending = 0;
      notifyListeners();
      return;
    }

    if (loadedTenantId != tenantId) {
      loadedTenantId = tenantId;
      orders = const [];
    }

    orders = await repository.list(tenantId);
    pending = await repository.pendingCount(tenantId);
    notifyListeners();
  }

  Future<OrderPreview> preview({
    required Map<String, dynamic> customer,
    required List<OrderDraftLine> lines,
  }) async {
    final tenantId = appState.session?.tenantId;
    if (tenantId == null) {
      throw StateError('Signed-in tenant is unavailable.');
    }

    return repository.preview(
      tenantId: tenantId,
      customer: customer,
      orderedAt: DateTime.now(),
      lines: lines,
    );
  }

  Future<void> create({
    required Map<String, dynamic> customer,
    required String paymentType,
    required List<OrderDraftLine> lines,
    String? visitUuid,
    String? notes,
  }) async {
    final tenantId = appState.session?.tenantId;
    if (tenantId == null || busy) return;

    busy = true;
    message = null;
    notifyListeners();

    try {
      await repository.createOffline(
        tenantId: tenantId,
        customer: customer,
        orderedAt: DateTime.now().toUtc(),
        paymentType: paymentType,
        lines: lines,
        visitUuid: visitUuid,
        notes: notes,
      );

      await reloadLocal();
      message = 'Order saved locally.';
      await sync(silent: true);
    } catch (error) {
      message = error.toString().replaceFirst('Bad state: ', '');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<List<Map<String, dynamic>>> items(Map<String, dynamic> order) async {
    final tenantId = appState.session?.tenantId;
    if (tenantId == null) return const [];

    return repository.items(tenantId, order['offline_uuid'].toString());
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
      await repository.refreshServerHistory(tenantId);
      await reloadLocal();

      if (!silent) {
        message = result.failed == 0
            ? 'Order sync complete. ' +
                  result.synced.toString() +
                  ' pending orders processed.'
            : 'Order sync completed with ' +
                  result.failed.toString() +
                  ' pending failures.';
      }
    } catch (_) {
      await reloadLocal();
      if (!silent) {
        message = 'Offline mode: orders remain stored locally.';
      }
    } finally {
      if (!silent) {
        busy = false;
        notifyListeners();
      }
    }
  }
}
