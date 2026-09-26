import 'dart:io';

import 'package:field_sales_mobile/features/auth/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('auth session identifies salesman and management roles', () {
    const salesman = AuthSession(
      userId: 'u1',
      tenantId: 't1',
      deviceId: 'd1',
      name: 'Salesman',
      role: 'salesman',
      permissions: [],
    );
    const supervisor = AuthSession(
      userId: 'u2',
      tenantId: 't1',
      deviceId: 'd2',
      name: 'Supervisor',
      role: 'supervisor',
      permissions: ['sales-team:view'],
    );
    const manager = AuthSession(
      userId: 'u3',
      tenantId: 't1',
      deviceId: 'd3',
      name: 'Manager',
      role: 'sales_manager',
      permissions: ['sales-team:view'],
    );

    expect(salesman.isSalesman, isTrue);
    expect(salesman.isManagement, isFalse);
    expect(supervisor.isSalesman, isFalse);
    expect(supervisor.isManagement, isTrue);
    expect(manager.isManagement, isTrue);
  });

  test('management mode is separated from salesman offline workflows', () {
    final app = File('lib/app.dart').readAsStringSync();
    final sync = File('lib/state/sync_controller.dart').readAsStringSync();
    final attendance =
        File('lib/state/attendance_controller.dart').readAsStringSync();

    expect(app, contains('ManagementDashboardScreen'));
    expect(app, contains('state.session?.isManagement == true'));
    expect(sync, contains('appState.session?.isSalesman != true'));
    expect(attendance, contains('appState.session?.isSalesman != true'));
  });

  test('management dashboard includes team overview and live map', () {
    final team = File('lib/ui/team_overview_screen.dart').readAsStringSync();
    final repository =
        File('lib/features/management/management_repository.dart')
            .readAsStringSync();

    expect(repository, contains("api.get('mobile/team/overview')"));
    expect(team, contains('FlutterMap('));
    expect(team, contains('work_status'));
    expect(team, contains('collections'));
    expect(team, contains('orders'));
  });

  test('End Day includes closing summary and diagnostic reporting', () {
    final home = File('lib/ui/home_tab.dart').readAsStringSync();
    final attendance =
        File('lib/state/attendance_controller.dart').readAsStringSync();
    final diagnostics =
        File('lib/features/diagnostics/diagnostic_reporter.dart')
            .readAsStringSync();

    expect(home, contains('dayClosingSummary()'));
    expect(home, contains('Complete the active customer visit'));
    expect(home, contains('Pending sync:'));
    expect(attendance, contains("area: 'attendance.end_day'"));
    expect(attendance, contains('diagnostics.report('));
    expect(diagnostics, contains("api.post("));
    expect(diagnostics, contains("'mobile/diagnostics'"));
  });
}
