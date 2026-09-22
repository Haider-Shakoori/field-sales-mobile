import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../features/attendance/attendance_repository.dart';
import '../../features/calls/call_activity_repository.dart';
import '../../features/collections/collection_repository.dart';
import '../../features/customers/customer_repository.dart';
import '../../features/expenses/expense_repository.dart';
import '../../features/gps/gps_repository.dart';
import '../../features/master_data/master_data_repository.dart';
import '../../features/orders/order_repository.dart';
import '../../features/targets/target_repository.dart';
import '../../features/visits/visit_repository.dart';
import '../db/app_database.dart';
import 'connectivity_gate.dart';
import 'local_dependency_guard.dart';
import 'sync_retry_store.dart';

class SyncCoordinator {
  SyncCoordinator({
    required this.db,
    required this.retryStore,
    required this.customers,
    required this.masterData,
    required this.attendance,
    required this.gps,
    required this.visits,
    required this.calls,
    required this.orders,
    required this.collections,
    required this.expenses,
    required this.targets,
  });

  final AppDatabase db;
  final SyncRetryStore retryStore;
  final CustomerRepository customers;
  final MasterDataRepository masterData;
  final AttendanceRepository attendance;
  final GpsRepository gps;
  final VisitRepository visits;
  final CallActivityRepository calls;
  final OrderRepository orders;
  final CollectionRepository collections;
  final ExpenseRepository expenses;
  final TargetRepository targets;

  Future<SyncCycleReport> run(
    String tenantId, {
    String triggerSource = 'manual',
  }) async {
    final cycleUuid = const Uuid().v4();
    final startedAt = DateTime.now().toUtc();
    final stages = <SyncStageReport>[];

    await db.db.insert('local_sync_cycles', {
      'tenant_id': tenantId,
      'cycle_uuid': cycleUuid,
      'trigger_source': triggerSource,
      'status': 'running',
      'started_at': startedAt.toIso8601String(),
      'stage_summary': '[]',
    });

    var synced = 0;
    var failed = 0;

    if (!await ConnectivityGate.instance.isOnline()) {
      final issues = await retryStore.issueCount(tenantId);
      final waiting = await retryStore.waitingCount(tenantId);
      final blocked = await retryStore.blockedCount(tenantId);
      final completedAt = DateTime.now().toUtc();
      const offlineStage = SyncStageReport.deferred(
        'network',
        'Device is offline; changes stay queued locally.',
      );

      await db.db.update(
        'local_sync_cycles',
        {
          'status': 'deferred',
          'completed_at': completedAt.toIso8601String(),
          'synced_count': 0,
          'failed_count': 0,
          'issue_count': issues,
          'waiting_count': waiting,
          'blocked_count': blocked,
          'stage_summary': jsonEncode([offlineStage.toJson()]),
        },
        where: 'tenant_id=? AND cycle_uuid=?',
        whereArgs: [tenantId, cycleUuid],
      );

      return SyncCycleReport(
        cycleUuid: cycleUuid,
        status: 'deferred',
        startedAt: startedAt,
        completedAt: completedAt,
        synced: 0,
        failed: 0,
        issues: issues,
        waiting: waiting,
        blocked: blocked,
        stages: const [offlineStage],
      );
    }

    Future<void> stage(
      String name,
      Future<SyncStageReport> Function() action,
    ) async {
      try {
        final result = await action();
        stages.add(result);
        synced += result.synced;
        failed += result.failed;
      } catch (error) {
        stages.add(
          SyncStageReport(
            name: name,
            status: 'failed',
            synced: 0,
            failed: 1,
            message: error.toString(),
          ),
        );
        failed++;
      }
    }

    await stage('customers', () async {
      final result = await customers.syncPending(tenantId);
      return SyncStageReport.fromCounts(
        'customers',
        result.synced,
        result.failed,
      );
    });

    await stage('master_data', () async {
      await masterData.refreshAll(tenantId);
      return const SyncStageReport.success('master_data');
    });

    await stage('privacy', () async {
      await gps.uploadPrivacyAcknowledgements(tenantId);
      return const SyncStageReport.success('privacy');
    });

    await stage('attendance', () async {
      await attendance.drain(tenantId);
      return const SyncStageReport.success('attendance');
    });

    final attendancePending = await LocalDependencyGuard(db)
        .hasPendingAttendance(tenantId);

    if (attendancePending) {
      stages.add(
        const SyncStageReport.deferred(
          'gps',
          'Waiting for attendance to synchronize.',
        ),
      );
      stages.add(
        const SyncStageReport.deferred(
          'visits',
          'Waiting for attendance to synchronize.',
        ),
      );
    } else {
      await stage('gps', () async {
        await gps.upload(tenantId);
        return const SyncStageReport.success('gps');
      });

      await stage('visits', () async {
        await visits.refreshForms(tenantId);
        final result = await visits.syncPending(tenantId);
        return SyncStageReport.fromCounts(
          'visits',
          result.synced,
          result.failed,
        );
      });
    }

    await stage('calls', () async {
      final result = await calls.syncPending(tenantId);
      return SyncStageReport.fromCounts('calls', result.synced, result.failed);
    });

    await stage('orders', () async {
      final result = await orders.syncPending(tenantId);
      await orders.refreshServerHistory(tenantId);
      return SyncStageReport.fromCounts('orders', result.synced, result.failed);
    });

    await stage('collections', () async {
      final result = await collections.syncPending(tenantId);
      await collections.refreshServerHistory(tenantId);
      await collections.refreshBalances(tenantId);
      return SyncStageReport.fromCounts(
        'collections',
        result.synced,
        result.failed,
      );
    });

    await stage('expenses', () async {
      final result = await expenses.syncPending(tenantId);
      await expenses.refreshHistory(tenantId);
      return SyncStageReport.fromCounts(
        'expenses',
        result.synced,
        result.failed,
      );
    });

    await stage('targets', () async {
      await targets.refresh(tenantId);
      return const SyncStageReport.success('targets');
    });

    final issues = await retryStore.issueCount(tenantId);
    final waiting = await retryStore.waitingCount(tenantId);
    final blocked = await retryStore.blockedCount(tenantId);
    final completedAt = DateTime.now().toUtc();
    final hasDeferred = stages.any((stage) => stage.status == 'deferred');
    final status = failed > 0 || issues > 0 || hasDeferred
        ? 'partial'
        : 'success';

    await db.db.update(
      'local_sync_cycles',
      {
        'status': status,
        'completed_at': completedAt.toIso8601String(),
        'synced_count': synced,
        'failed_count': failed,
        'issue_count': issues,
        'waiting_count': waiting,
        'blocked_count': blocked,
        'stage_summary': jsonEncode(
          stages.map((stage) => stage.toJson()).toList(),
        ),
      },
      where: 'tenant_id=? AND cycle_uuid=?',
      whereArgs: [tenantId, cycleUuid],
    );

    return SyncCycleReport(
      cycleUuid: cycleUuid,
      status: status,
      startedAt: startedAt,
      completedAt: completedAt,
      synced: synced,
      failed: failed,
      issues: issues,
      waiting: waiting,
      blocked: blocked,
      stages: stages,
    );
  }

  Future<Map<String, dynamic>?> latestCycle(String tenantId) async {
    final rows = await db.db.query(
      'local_sync_cycles',
      where: 'tenant_id=?',
      whereArgs: [tenantId],
      orderBy: 'started_at DESC',
      limit: 1,
    );

    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
  }
}

class SyncCycleReport {
  const SyncCycleReport({
    required this.cycleUuid,
    required this.status,
    required this.startedAt,
    required this.completedAt,
    required this.synced,
    required this.failed,
    required this.issues,
    required this.waiting,
    required this.blocked,
    required this.stages,
  });

  final String cycleUuid;
  final String status;
  final DateTime startedAt;
  final DateTime completedAt;
  final int synced;
  final int failed;
  final int issues;
  final int waiting;
  final int blocked;
  final List<SyncStageReport> stages;
}

class SyncStageReport {
  const SyncStageReport({
    required this.name,
    required this.status,
    required this.synced,
    required this.failed,
    this.message,
  });

  const SyncStageReport.success(String name)
    : this(name: name, status: 'success', synced: 0, failed: 0);

  const SyncStageReport.deferred(String name, String message)
    : this(
        name: name,
        status: 'deferred',
        synced: 0,
        failed: 0,
        message: message,
      );

  factory SyncStageReport.fromCounts(String name, int synced, int failed) {
    return SyncStageReport(
      name: name,
      status: failed > 0 ? 'partial' : 'success',
      synced: synced,
      failed: failed,
    );
  }

  final String name;
  final String status;
  final int synced;
  final int failed;
  final String? message;

  Map<String, dynamic> toJson() => {
    'name': name,
    'status': status,
    'synced': synced,
    'failed': failed,
    if (message != null) 'message': message,
  };
}
