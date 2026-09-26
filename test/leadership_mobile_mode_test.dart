import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('leadership mobile mode uses team overview and live map', () {
    final repository = File('lib/features/team/team_repository.dart')
        .readAsStringSync();
    final dashboard = File('lib/ui/leadership_dashboard_screen.dart')
        .readAsStringSync();
    final shell = File('lib/ui/dashboard_screen.dart').readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();

    expect(repository, contains("api.get('team/overview')"));
    expect(dashboard, contains('Team live map'));
    expect(dashboard, contains('Reporting hierarchy'));
    expect(dashboard, contains('Recent field activity'));
    expect(dashboard, contains('FlutterMap('));
    expect(shell, contains('isLeadership'));
    expect(shell, contains('LeadershipDashboardScreen'));
    expect(main, contains('if (appState.isSalesman)'));
  });
}
