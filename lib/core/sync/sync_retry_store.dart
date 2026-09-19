import '../api/api_exception.dart';
import '../db/app_database.dart';

class SyncRetryStore {
  const SyncRetryStore(this.db);

  final AppDatabase db;

  Future<bool> shouldAttempt({
    required String tenantId,
    required String entityType,
    required String entityUuid,
    DateTime? now,
  }) async {
    final rows = await db.db.query(
      'local_sync_failures',
      where: 'tenant_id=? AND entity_type=? AND entity_uuid=?',
      whereArgs: [tenantId, entityType, entityUuid],
      limit: 1,
    );

    if (rows.isEmpty) return true;

    final row = rows.first;
    if (row['status'] == 'blocked') return false;

    final next = row['next_retry_at']?.toString();
    if (next == null || next.isEmpty) return true;

    final due = DateTime.tryParse(next);
    if (due == null) return true;

    return !(now ?? DateTime.now().toUtc()).isBefore(due);
  }

  Future<SyncFailureState> recordFailure({
    required String tenantId,
    required String entityType,
    required String entityUuid,
    required Object error,
    bool? retryableOverride,
    int maxAttempts = 8,
  }) async {
    final existing = await db.db.query(
      'local_sync_failures',
      where: 'tenant_id=? AND entity_type=? AND entity_uuid=?',
      whereArgs: [tenantId, entityType, entityUuid],
      limit: 1,
    );

    final previousAttempts = existing.isEmpty
        ? 0
        : (existing.first['attempts'] as int? ?? 0);
    final attempts = previousAttempts + 1;
    final decision = _classify(error, retryableOverride: retryableOverride);
    final blocked = !decision.retryable || attempts >= maxAttempts;
    final now = DateTime.now().toUtc();
    final nextRetry = blocked ? null : now.add(_delayFor(attempts));

    final values = <String, Object?>{
      'tenant_id': tenantId,
      'entity_type': entityType,
      'entity_uuid': entityUuid,
      'attempts': attempts,
      'max_attempts': maxAttempts,
      'status': blocked ? 'blocked' : 'retry_wait',
      'error_code': decision.code,
      'error_message': decision.message,
      'next_retry_at': nextRetry?.toIso8601String(),
      'first_failed_at': existing.isEmpty
          ? now.toIso8601String()
          : existing.first['first_failed_at'],
      'last_failed_at': now.toIso8601String(),
    };

    await db.db.insert(
      'local_sync_failures',
      values,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    return SyncFailureState(
      attempts: attempts,
      blocked: blocked,
      retryable: decision.retryable,
      code: decision.code,
      message: decision.message,
      nextRetryAt: nextRetry,
    );
  }

  Future<void> clear({
    required String tenantId,
    required String entityType,
    required String entityUuid,
  }) async {
    await db.db.delete(
      'local_sync_failures',
      where: 'tenant_id=? AND entity_type=? AND entity_uuid=?',
      whereArgs: [tenantId, entityType, entityUuid],
    );
  }

  Future<List<Map<String, dynamic>>> issues(String tenantId) async {
    final rows = await db.db.query(
      'local_sync_failures',
      where: 'tenant_id=?',
      whereArgs: [tenantId],
      orderBy: 'status DESC, last_failed_at DESC',
    );

    return rows.map(Map<String, dynamic>.from).toList();
  }

  Future<int> blockedCount(String tenantId) async {
    final rows = await db.db.rawQuery(
      'SELECT COUNT(*) AS total FROM local_sync_failures '
      'WHERE tenant_id=? AND status=?',
      [tenantId, 'blocked'],
    );

    return rows.first['total'] as int? ?? 0;
  }

  Future<void> retryAll(String tenantId) async {
    await db.db.update(
      'local_sync_failures',
      {
        'attempts': 0,
        'status': 'retry_wait',
        'next_retry_at': null,
      },
      where: 'tenant_id=?',
      whereArgs: [tenantId],
    );
  }

  _FailureDecision _classify(
    Object error, {
    bool? retryableOverride,
  }) {
    if (error is ApiException) {
      final code = error.code;
      final dependencyCodes = {
        'VISIT_NOT_SYNCED',
        'VISIT_OUTSIDE_WORK_SESSION',
        'SESSION_NOT_FOUND',
      };

      final retryable = retryableOverride ??
          error.retryable ||
          dependencyCodes.contains(code);

      return _FailureDecision(
        retryable: retryable,
        code: code,
        message: error.message,
      );
    }

    return _FailureDecision(
      retryable: retryableOverride ?? true,
      code: null,
      message: error.toString(),
    );
  }

  Duration _delayFor(int attempts) {
    switch (attempts) {
      case 1:
        return const Duration(minutes: 1);
      case 2:
        return const Duration(minutes: 5);
      case 3:
        return const Duration(minutes: 15);
      case 4:
        return const Duration(hours: 1);
      case 5:
        return const Duration(hours: 4);
      default:
        return const Duration(hours: 12);
    }
  }
}

class SyncFailureState {
  const SyncFailureState({
    required this.attempts,
    required this.blocked,
    required this.retryable,
    required this.code,
    required this.message,
    required this.nextRetryAt,
  });

  final int attempts;
  final bool blocked;
  final bool retryable;
  final String? code;
  final String message;
  final DateTime? nextRetryAt;
}

class _FailureDecision {
  const _FailureDecision({
    required this.retryable,
    required this.code,
    required this.message,
  });

  final bool retryable;
  final String? code;
  final String message;
}
