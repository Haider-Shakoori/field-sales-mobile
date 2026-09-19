import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

class LocalFirstTransaction {
  const LocalFirstTransaction(this.database);

  final AppDatabase database;

  Future<T> run<T>(
    Future<T> Function(Transaction transaction) operation,
  ) =>
      database.db.transaction(operation);

  Future<void> enqueue(
    Transaction transaction, {
    required String tenantId,
    required String entityType,
    required String entityUuid,
    required String action,
    required String payload,
    int priority = 100,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();

    await transaction.insert('sync_queue', {
      'tenant_id': tenantId,
      'entity_type': entityType,
      'entity_uuid': entityUuid,
      'action': action,
      'payload': payload,
      'priority': priority,
      'status': 'pending',
      'created_at': now,
      'updated_at': now,
    });
  }
}
