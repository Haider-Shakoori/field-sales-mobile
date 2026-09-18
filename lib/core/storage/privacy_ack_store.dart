import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/privacy_ack.dart';
import 'app_database.dart';

/// Persists the GPS tracking acknowledgement in `local_settings`.
///
/// Kept deliberately server-shaped (see [GpsPrivacyAcknowledgement]) so the
/// acceptance can later be synchronized/audited without a migration.
class PrivacyAckStore {
  PrivacyAckStore._();

  static final PrivacyAckStore instance = PrivacyAckStore._();

  static const settingKey = 'gps_privacy_ack';

  Future<GpsPrivacyAcknowledgement?> load() async {
    final db = await AppDatabase.instance;
    final rows = await db.query(
      'local_settings',
      where: 'key = ?',
      whereArgs: [settingKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    final raw = rows.first['value'] as String?;
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return GpsPrivacyAcknowledgement.fromJson(decoded);
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  Future<GpsPrivacyAcknowledgement> save(
    GpsPrivacyAcknowledgement acknowledgement,
  ) async {
    final db = await AppDatabase.instance;
    await db.insert('local_settings', {
      'key': settingKey,
      'value': jsonEncode(acknowledgement.toJson()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return acknowledgement;
  }

  Future<void> clear() async {
    final db = await AppDatabase.instance;
    await db.delete(
      'local_settings',
      where: 'key = ?',
      whereArgs: [settingKey],
    );
  }

  /// Marks the stored acknowledgement as audited server-side, keeping the
  /// original policy version / acknowledged_at metadata for idempotent retries.
  Future<GpsPrivacyAcknowledgement?> markSynced({
    required int serverId,
    String? serverUuid,
  }) async {
    final current = await load();
    if (current == null) {
      return null;
    }
    return save(
      current.copyWith(
        syncStatus: 'synced',
        serverId: serverId,
        serverUuid: serverUuid,
      ),
    );
  }
}
