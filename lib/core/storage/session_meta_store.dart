import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/session.dart';
import 'app_database.dart';

/// Persists the current user/tenant session metadata in the `session_meta`
/// table so identity (name, email, tenant, permissions) stays available
/// offline and can be restored on app start without a network round trip.
class SessionMetaStore {
  static const _userKey = 'current_user';
  static const _tenantKey = 'current_tenant';
  static const _permissionsKey = 'current_permissions';

  Future<void> save(Session session) async {
    final db = await AppDatabase.instance;
    await db.transaction((txn) async {
      await txn.insert('session_meta', {
        'key': _userKey,
        'value': jsonEncode({
          'id': session.user.id,
          'public_id': session.user.publicId,
          'name': session.user.name,
          'email': session.user.email,
          'role': session.user.role,
          'branch_id': session.user.branchId,
        }),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('session_meta', {
        'key': _tenantKey,
        'value': jsonEncode({
          'id': session.tenant.id,
          'public_id': session.tenant.publicId,
          'name': session.tenant.name,
          'slug': session.tenant.slug,
        }),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('session_meta', {
        'key': _permissionsKey,
        'value': jsonEncode(session.permissions),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<({UserInfo user, TenantInfo tenant, List<String> permissions})>
  load() async {
    final db = await AppDatabase.instance;
    final rows = await db.query('session_meta');
    final byKey = {
      for (final r in rows) r['key'] as String: r['value'] as String?,
    };

    final userMap = _decode(byKey[_userKey]);
    final tenantMap = _decode(byKey[_tenantKey]);
    final permissions = (byKey[_permissionsKey] == null)
        ? <String>[]
        : (jsonDecode(byKey[_permissionsKey]!) as List<dynamic>)
              .map((e) => e.toString())
              .toList();

    return (
      user: UserInfo(
        id: tolerantIntId(userMap?['id']),
        publicId: userMap?['public_id']?.toString() ?? '',
        name: userMap?['name']?.toString() ?? '',
        email: userMap?['email']?.toString() ?? '',
        role: userMap?['role']?.toString(),
        branchId: (userMap?['branch_id'] as num?)?.toInt(),
      ),
      tenant: TenantInfo(
        id: tolerantIntId(tenantMap?['id']),
        publicId: tenantMap?['public_id']?.toString() ?? '',
        name: tenantMap?['name']?.toString() ?? '',
        slug: tenantMap?['slug']?.toString(),
      ),
      permissions: permissions,
    );
  }

  Future<void> clear() async {
    final db = await AppDatabase.instance;
    await db.delete('session_meta');
  }

  Map<String, dynamic>? _decode(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    final decoded = jsonDecode(value);
    return decoded is Map<String, dynamic> ? decoded : null;
  }
}
