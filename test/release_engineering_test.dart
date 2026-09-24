import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'production manifest disables cleartext and debug explicitly restores it',
    () {
      final productionManifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      final debugManifest = File('android/app/src/debug/AndroidManifest.xml')
          .readAsStringSync();

      expect(
        productionManifest,
        contains('android:usesCleartextTraffic="false"'),
      );
      expect(productionManifest, contains('android:allowBackup="false"'));
      expect(debugManifest, contains('android:usesCleartextTraffic="true"'));
    },
  );

  test('Android permission bridge serializes notification permission', () {
    final activity = File(
      'android/app/src/main/kotlin/com/businessos/fieldpulse/MainActivity.kt',
    ).readAsStringSync();
    final attendance = File('lib/state/attendance_controller.dart')
        .readAsStringSync();

    expect(activity, contains('pendingNotificationPermissionResult = result'));
    expect(activity, contains('onRequestPermissionsResult'));
    expect(
      activity,
      contains('pendingNotificationPermissionResult?.success(granted)'),
    );
    expect(attendance, contains('.timeout(const Duration(seconds: 15))'));
  });

  test('visit GPS acquisition fails closed instead of hanging', () {
    final visits = File('lib/state/visit_controller.dart').readAsStringSync();

    expect(
      visits,
      contains(
        'Geolocator.getCurrentPosition(\n'
        '        locationSettings: const LocationSettings(\n'
        '          accuracy: LocationAccuracy.high,\n'
        '        ),\n'
        '      ).timeout(const Duration(seconds: 20))',
      ),
    );
    expect(visits, contains('position.accuracy > 200'));
    expect(visits, contains('Unable to get a GPS fix within 20 seconds.'));
  });

  test('release signing is externalized and fails closed', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();

    expect(gradle, contains('FIELD_SALES_KEYSTORE_FILE'));
    expect(gradle, contains('FIELD_SALES_KEYSTORE_PASSWORD'));
    expect(gradle, contains('FIELD_SALES_KEY_ALIAS'));
    expect(gradle, contains('FIELD_SALES_KEY_PASSWORD'));
    expect(gradle, contains('Release signing is not configured'));
  });

  test('production release workflow builds signed artifacts from secrets', () {
    final workflow = File('.github/workflows/android-release.yml')
        .readAsStringSync();

    expect(workflow, contains('ANDROID_KEYSTORE_BASE64'));
    expect(workflow, contains('PRODUCTION_API_BASE_URL'));
    expect(workflow, contains('flutter build appbundle --release'));
    expect(workflow, contains('flutter build apk --release'));
    expect(workflow, contains('SHA256SUMS.txt'));
    expect(workflow, contains('flutter pub get --enforce-lockfile'));
  });

  test('Flutter dependency graph is committed for reproducible builds', () {
    expect(File('pubspec.lock').existsSync(), isTrue);

    final ci = File('.github/workflows/ci.yml').readAsStringSync();
    expect(ci, contains('flutter pub get --enforce-lockfile'));
    expect(ci, contains('permissions:\n  contents: read'));
  });
}
