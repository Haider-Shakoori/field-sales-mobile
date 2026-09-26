import 'package:flutter/foundation.dart';

import '../core/db/app_database.dart';
import '../core/sync/sync_coordinator.dart';
import '../core/sync/sync_retry_store.dart';
import 'app_state.dart';

class SyncController extends ChangeNotifier {
  SyncController({
    required this.appState,
    required this.db,
    required this.coordinator,
    required this.retryStore,
  });

  final AppState appState;
  final AppDatabase db;
  final SyncCoordinator coordinator;
  final SyncRetryStore retryStore;

  bool busy = false;
  String? message;
  int issueCount = 0;
  int waitingCount = 0;
  int blockedCount = 0;
  int infrastructurePending = 0;
  List<Map<String, dynamic>> issues = const [];
  Map<String, dynamic>? latestCycle;
  SyncCycleReport? lastReport;

  Future<void> initialize() => refreshHealth();

  Future<void> refreshHealth() async {
    final tenantId = appState.session?.tenantId;
    if (tenantId == null || appState.session?.isSalesman != true) {
      issueCount = 0;
      waitingCount = 0;
      blockedCount = 0;
      infrastructurePending = 0;
      issues = const [];
      latestCycle = null;
      notifyListeners();
      return;
    }

    issues = await retryStore.issues(tenantId);
    issueCount = issues.length;
    waitingCount = await retryStore.waitingCount(tenantId);
    blockedCount = await retryStore.blockedCount(tenantId);
    latestCycle = await coordinator.latestCycle(tenantId);
    infrastructurePending = await _infrastructurePending(tenantId);
    notifyListeners();
  }

  Future<SyncCycleReport?> run({String triggerSource = 'manual'}) async {
    final tenantId = appState.session?.tenantId;
    if (tenantId == null || appState.session?.isSalesman != true || busy) {
      return null;
    }

    busy = true;
    message = null;
    notifyListeners();

    try {
      lastReport = await coordinator.run(
        tenantId,
        triggerSource: triggerSource,
      );

      final report = lastReport!;
      message = switch (report.status) {
        'success' => 'Sync completed successfully.',
        'deferred' =>
          'Offline mode: changes are saved locally and will sync when online.',
        _ =>
          'Sync completed with ${report.issues} items needing retry or attention.',
      };

      return report;
    } catch (error) {
      message = 'Sync could not complete: $error';
      return null;
    } finally {
      busy = false;
      await refreshHealth();
      notifyListeners();
    }
  }

  Future<SyncCycleReport?> retryFailures() async {
    final tenantId = appState.session?.tenantId;
    if (tenantId == null || appState.session?.isSalesman != true || busy) {
      return null;
    }

    await retryStore.retryAll(tenantId);
    await refreshHealth();

    return run(triggerSource: 'manual_retry');
  }

  Future<int> _infrastructurePending(String tenantId) async {
    final queue = await db.db.rawQuery(
      'SELECT COUNT(*) AS total FROM sync_queue '
      'WHERE tenant_id=? AND status IN (?,?)',
      [tenantId, 'failed', 'blocked'],
    );
    final gps = await db.db.rawQuery(
      'SELECT COUNT(*) AS total FROM local_gps_points '
      'WHERE tenant_id=? AND sync_status=?',
      [tenantId, 'pending'],
    );
    final privacy = await db.db.rawQuery(
      'SELECT COUNT(*) AS total FROM privacy_acknowledgements '
      'WHERE tenant_id=? AND sync_status<>?',
      [tenantId, 'synced'],
    );

    return (queue.first['total'] as int? ?? 0) +
        (gps.first['total'] as int? ?? 0) +
        (privacy.first['total'] as int? ?? 0);
  }
}
