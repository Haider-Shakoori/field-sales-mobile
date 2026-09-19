import '../../core/api/api_client.dart';
import '../../core/db/app_database.dart';

class TargetRepository {
  TargetRepository({required this.api, required this.db});

  final ApiClient api;
  final AppDatabase db;

  Future<List<Map<String, dynamic>>> current(String tenantId) async {
    final rows = await db.db.query(
      'local_targets',
      where: 'tenant_id=? AND is_current=1',
      whereArgs: [tenantId],
      orderBy: 'target_type ASC',
    );

    return rows.map(Map<String, dynamic>.from).toList();
  }

  Future<List<Map<String, dynamic>>> history(String tenantId) async {
    final rows = await db.db.query(
      'local_targets',
      where: 'tenant_id=?',
      whereArgs: [tenantId],
      orderBy: 'period_start DESC, target_type ASC',
    );

    return rows.map(Map<String, dynamic>.from).toList();
  }

  Future<void> refresh(String tenantId) async {
    final historyData = await api.get(
      'targets/history',
      query: {'per_page': 100},
    );
    final currentData = await api.get('targets/current');

    final history = (historyData as List? ?? const [])
        .whereType<Map>()
        .map(Map<String, dynamic>.from)
        .toList();
    final current = (currentData as List? ?? const [])
        .whereType<Map>()
        .map(Map<String, dynamic>.from)
        .toList();
    final currentIds = current
        .map((row) => row['id']?.toString())
        .whereType<String>()
        .toSet();
    final now = DateTime.now().toUtc().toIso8601String();

    await db.db.transaction((txn) async {
      await txn.delete(
        'local_targets',
        where: 'tenant_id=?',
        whereArgs: [tenantId],
      );

      for (final target in history) {
        final uuid = target['id']?.toString();
        if (uuid == null || uuid.isEmpty) continue;

        await txn.insert('local_targets', {
          'tenant_id': tenantId,
          'target_uuid': uuid,
          'target_type': target['target_type']?.toString() ?? '',
          'currency': target['currency']?.toString(),
          'target_value': _number(target['target_value']),
          'achieved_value': _number(target['achieved_value']),
          'remaining_value': _number(target['remaining_value']),
          'progress_percent': _number(target['progress_percent']),
          'period_start': target['period_start']?.toString() ?? '',
          'period_end': target['period_end']?.toString() ?? '',
          'notes': target['notes']?.toString(),
          'is_current': currentIds.contains(uuid) ? 1 : 0,
          'updated_at': now,
        });
      }

      for (final target in current) {
        final uuid = target['id']?.toString();
        if (uuid == null || uuid.isEmpty) continue;

        final exists = history.any((row) => row['id']?.toString() == uuid);
        if (exists) continue;

        await txn.insert('local_targets', {
          'tenant_id': tenantId,
          'target_uuid': uuid,
          'target_type': target['target_type']?.toString() ?? '',
          'currency': target['currency']?.toString(),
          'target_value': _number(target['target_value']),
          'achieved_value': _number(target['achieved_value']),
          'remaining_value': _number(target['remaining_value']),
          'progress_percent': _number(target['progress_percent']),
          'period_start': target['period_start']?.toString() ?? '',
          'period_end': target['period_end']?.toString() ?? '',
          'notes': target['notes']?.toString(),
          'is_current': 1,
          'updated_at': now,
        });
      }
    });
  }

  static double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
