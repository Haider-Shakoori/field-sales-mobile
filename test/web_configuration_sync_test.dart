import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web configuration participates in the normal sync lifecycle', () {
    final settings = File(
      'lib/features/settings/settings_repository.dart',
    ).readAsStringSync();
    final appState = File('lib/state/app_state.dart').readAsStringSync();
    final coordinator = File(
      'lib/core/sync/sync_coordinator.dart',
    ).readAsStringSync();
    final syncScreen = File('lib/ui/sync_screen.dart').readAsStringSync();

    expect(settings, contains("api.get('settings/sync')"));
    expect(settings, contains('mobile_configuration_meta'));
    expect(settings, contains('mobile_feature_settings'));
    expect(settings, contains('mobile_device_policy'));

    expect(appState, contains('configurationVersion'));
    expect(appState, contains('refreshServerConfiguration'));
    expect(appState, contains('gamificationEnabled'));

    expect(coordinator, contains("stage('configuration'"));
    expect(coordinator, contains('refreshConfiguration?.call()'));

    expect(syncScreen, contains('Web configuration'));
    expect(syncScreen, contains('during every online sync'));
  });
}
