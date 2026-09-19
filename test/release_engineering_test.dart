import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production manifest disables cleartext and debug explicitly restores it', () {
    final productionManifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final debugManifest = File(
      'android/app/src/debug/AndroidManifest.xml',
    ).readAsStringSync();

    expect(productionManifest, contains('android:usesCleartextTraffic="false"'));
    expect(debugManifest, contains('android:usesCleartextTraffic="true"'));
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
    final workflow = File(
      '.github/workflows/android-release.yml',
    ).readAsStringSync();

    expect(workflow, contains('ANDROID_KEYSTORE_BASE64'));
    expect(workflow, contains('PRODUCTION_API_BASE_URL'));
    expect(workflow, contains('flutter build appbundle --release'));
    expect(workflow, contains('flutter build apk --release'));
    expect(workflow, contains('SHA256SUMS.txt'));
  });
}
