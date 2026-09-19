import '../db/app_database.dart';

class LocalDependencyGuard {
  const LocalDependencyGuard(this.db);

  final AppDatabase db;

  Future<bool> customerReady(String tenantId, String customerUuid) async {
    final rows = await db.db.query(
      'customers',
      columns: ['sync_status'],
      where: 'tenant_id=? AND uuid=?',
      whereArgs: [tenantId, customerUuid],
      limit: 1,
    );

    if (rows.isEmpty) {
      return true;
    }

    return rows.first['sync_status'] == 'synced';
  }

  Future<bool> visitReady(String tenantId, String visitUuid) async {
    final rows = await db.db.query(
      'local_visits',
      columns: ['server_uuid'],
      where: 'tenant_id=? AND offline_uuid=?',
      whereArgs: [tenantId, visitUuid],
      limit: 1,
    );

    if (rows.isEmpty) {
      return true;
    }

    final serverUuid = rows.first['server_uuid']?.toString();
    return serverUuid != null && serverUuid.isNotEmpty;
  }

  Future<bool> hasPendingAttendance(String tenantId) async {
    final rows = await db.db.rawQuery(
      'SELECT COUNT(*) AS total FROM sync_queue '
      'WHERE tenant_id=? AND entity_type=? AND status NOT IN (?,?)',
      [tenantId, 'attendance', 'done', 'synced'],
    );

    return (rows.first['total'] as int? ?? 0) > 0;
  }
}
