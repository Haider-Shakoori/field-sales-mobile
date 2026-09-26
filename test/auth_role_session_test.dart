import 'package:field_sales_mobile/features/auth/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('auth session preserves leadership role and permissions', () {
    final session = AuthSession.fromJson({
      'user_id': 'user-1',
      'tenant_id': 'tenant-1',
      'device_id': 'device-1',
      'name': 'Team Supervisor',
      'role': 'supervisor',
      'permissions': ['tracking:view', 'sales-team:view'],
    });

    expect(session.isSupervisor, isTrue);
    expect(session.isLeadership, isTrue);
    expect(session.isSalesman, isFalse);
    expect(session.permissions, contains('tracking:view'));
    expect(session.toJson()['role'], 'supervisor');
  });

  test('legacy role-less session data remains salesman compatible', () {
    final session = AuthSession.fromJson({
      'user_id': 'user-1',
      'tenant_id': 'tenant-1',
      'device_id': 'device-1',
      'name': 'Legacy Salesman',
    });

    expect(session.role, 'salesman');
    expect(session.isSalesman, isTrue);
    expect(session.isLeadership, isFalse);
  });
}
