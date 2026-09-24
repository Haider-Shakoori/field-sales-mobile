import 'package:flutter/foundation.dart';

import '../features/leads/lead_repository.dart';
import 'app_state.dart';

class LeadController extends ChangeNotifier {
  LeadController({required this.appState, required this.repository});

  final AppState appState;
  final LeadRepository repository;

  bool busy = false;
  String? message;
  String? loadedTenantId;
  int pending = 0;
  List<Map<String, dynamic>> leads = const [];

  Future<void> reloadLocal() async {
    final tenantId = appState.session?.tenantId;
    if (tenantId == null) {
      loadedTenantId = null;
      leads = const [];
      pending = 0;
      notifyListeners();
      return;
    }
    if (loadedTenantId != tenantId) {
      loadedTenantId = tenantId;
      leads = const [];
    }
    leads = await repository.list(tenantId);
    pending = await repository.pendingCount(tenantId);
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> activities(String leadOfflineUuid) async {
    final tenantId = appState.session?.tenantId;
    if (tenantId == null) return const [];
    try {
      await repository.refreshDetails(tenantId, leadOfflineUuid);
    } catch (_) {}
    return repository.activities(tenantId, leadOfflineUuid);
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
            ? 'Lead pipeline sync complete.'
            : 'Lead sync completed with ${result.failed} pending failure(s).';
      }
    } catch (_) {
      await reloadLocal();
      if (!silent) message = 'Offline mode: cached leads remain available.';
    } finally {
      if (!silent) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> create({
    required String name,
    String? contactPerson,
    String? phone,
    String? email,
    String? address,
    String source = 'field',
    String priority = 'normal',
    double? estimatedValue,
    String currency = 'AFN',
    DateTime? expectedCloseDate,
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
        name: name,
        contactPerson: contactPerson,
        phone: phone,
        email: email,
        address: address,
        source: source,
        priority: priority,
        estimatedValue: estimatedValue,
        currency: currency,
        expectedCloseDate: expectedCloseDate,
        notes: notes,
      );
      await reloadLocal();
      message = 'Lead saved locally.';
      await sync(silent: true);
    } catch (error) {
      message = error.toString();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> updateStage(
    Map<String, dynamic> lead,
    String stage, {
    String? lostReason,
  }) async {
    final tenantId = appState.session?.tenantId;
    final uuid = lead['offline_uuid']?.toString();
    if (tenantId == null || uuid == null || busy) return;
    busy = true;
    notifyListeners();
    try {
      await repository.updateStageLocal(
        tenantId: tenantId,
        offlineUuid: uuid,
        stage: stage,
        lostReason: lostReason,
      );
      await reloadLocal();
      message = 'Lead stage updated locally.';
      await sync(silent: true);
    } catch (error) {
      message = error.toString();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> addActivity(
    Map<String, dynamic> lead,
    String type,
    String notes,
  ) async {
    final tenantId = appState.session?.tenantId;
    final uuid = lead['offline_uuid']?.toString();
    if (tenantId == null || uuid == null || notes.trim().isEmpty || busy)
      return;
    busy = true;
    notifyListeners();
    try {
      await repository.addActivityLocal(
        tenantId: tenantId,
        leadOfflineUuid: uuid,
        type: type,
        notes: notes,
      );
      await reloadLocal();
      message = 'Lead activity saved locally.';
      await sync(silent: true);
    } catch (error) {
      message = error.toString();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> convert(Map<String, dynamic> lead) async {
    final tenantId = appState.session?.tenantId;
    final uuid = lead['offline_uuid']?.toString();
    if (tenantId == null || uuid == null || busy) return;
    busy = true;
    notifyListeners();
    try {
      await repository.convertLocal(tenantId: tenantId, offlineUuid: uuid);
      await reloadLocal();
      message = 'Lead marked for customer conversion.';
      await sync(silent: true);
    } catch (error) {
      message = error.toString();
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
