import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release candidate uses resolution-independent FieldPulse branding', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    final app = File('lib/app.dart').readAsStringSync();
    final splash = File('lib/ui/fieldpulse_splash_screen.dart')
        .readAsStringSync();
    final launchBackground = File(
      'android/app/src/main/res/drawable/launch_background.xml',
    ).readAsStringSync();
    final android12Style = File(
      'android/app/src/main/res/values-v31/styles.xml',
    ).readAsStringSync();
    final vector = File(
      'android/app/src/main/res/drawable/fieldpulse_splash_vector.xml',
    );

    expect(manifest, contains('android:label="FieldPulse"'));
    expect(manifest, contains('android:icon="@mipmap/ic_launcher"'));
    expect(app, contains("title: 'FieldPulse'"));

    expect(splash, contains('CustomPaint'));
    expect(splash, contains('_FieldPulseMarkPainter'));
    expect(splash, contains("'FieldPulse'"));
    expect(splash, contains("'BusinessOS'"));
    expect(splash, isNot(contains('AssetImage(')));

    expect(vector.existsSync(), isTrue);
    expect(launchBackground, contains('@drawable/fieldpulse_splash_vector'));
    expect(android12Style, contains('@drawable/fieldpulse_splash_vector'));
    expect(
      File(
        'android/app/src/main/res/drawable-nodpi/fieldpulse_launcher_foreground.png',
      ).existsSync(),
      isTrue,
    );
    expect(
      File('android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.webp')
          .existsSync(),
      isTrue,
    );
  });
}
