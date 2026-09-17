import 'dart:convert';

import '../sync/sync_status.dart';

/// A single yet-to-be-synced local mutation.
///
/// Batch 6 is outbox-only: entries carry the standard status flow
/// (`pending → syncing → synced / failed`). Retry scheduling fields
/// ([attempts], [maxAttempts], [nextRetryAt], [isReadyForRetry]) exist for
/// forward-compatibility with the Batch 12 sync engine and are unused now.
class QueueEntry {
  QueueEntry({
    required this.entityType,
    required this.entityUuid,
    required this.action,
    required this.payload,
    this.priority = 5,
    this.attempts = 0,
    this.maxAttempts = 5,
    this.status = SyncStatus.pending,
    this.errorMessage,
    this.nextRetryAt,
    this.serverId,
    this.serverUuid,
  });

  final String entityType;
  final String entityUuid;
  final String action;
  final Map<String, dynamic> payload;
  final int priority;
  int attempts;
  int maxAttempts;
  SyncStatus status;
  String? errorMessage;
  DateTime? nextRetryAt;
  String? serverId;
  String? serverUuid;

  bool get isReadyForRetry {
    if (status != SyncStatus.pending && status != SyncStatus.failed) {
      return false;
    }
    if (attempts >= maxAttempts) {
      return false;
    }
    return nextRetryAt == null || !nextRetryAt!.isAfter(DateTime.now());
  }

  Map<String, dynamic> toRow() => {
    'entity_type': entityType,
    'entity_uuid': entityUuid,
    'action': action,
    'payload': jsonEncode(payload),
    'priority': priority,
    'attempts': attempts,
    'max_attempts': maxAttempts,
    'status': status.name,
    'error_message': errorMessage,
    'next_retry_at': nextRetryAt?.toIso8601String(),
    'server_id': serverId,
    'server_uuid': serverUuid,
    'created_at': DateTime.now().toIso8601String(),
    'updated_at': DateTime.now().toIso8601String(),
  };

  factory QueueEntry.fromRow(Map<String, Object?> row) => QueueEntry(
    entityType: row['entity_type'] as String,
    entityUuid: row['entity_uuid'] as String,
    action: row['action'] as String,
    payload: jsonDecode(row['payload'] as String) as Map<String, dynamic>,
    priority: row['priority'] as int? ?? 5,
    attempts: row['attempts'] as int? ?? 0,
    maxAttempts: row['max_attempts'] as int? ?? 5,
    status: SyncStatus.from(row['status'] as String?),
    errorMessage: row['error_message'] as String?,
    nextRetryAt: row['next_retry_at'] == null
        ? null
        : DateTime.parse(row['next_retry_at'] as String),
    serverId: row['server_id'] as String?,
    serverUuid: row['server_uuid'] as String?,
  );
}

class SyncQueueCounts {
  SyncQueueCounts(this.pending, this.synced, this.failed);

  final int pending;
  final int synced;
  final int failed;

  int get total => pending + synced + failed;
}
