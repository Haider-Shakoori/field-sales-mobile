import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release candidate uses original high-quality FieldPulse branding', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final app = File('lib/app.dart').readAsStringSync();
    final splash = File('lib/ui/fieldpulse_splash_screen.dart')
        .readAsStringSync();
    final splashAsset = File('assets/branding/fieldpulse_splash.webp');

    expect(manifest, contains('android:label="FieldPulse"'));
    expect(manifest, contains('android:icon="@mipmap/ic_launcher"'));
    expect(pubspec, contains('assets/branding/fieldpulse_splash.webp'));
    expect(app, contains("title: 'FieldPulse'"));
    expect(
      splash,
      contains("AssetImage('assets/branding/fieldpulse_splash.webp')"),
    );
    expect(splash, contains('fit: BoxFit.cover'));
    expect(splash, contains('filterQuality: FilterQuality.high'));

    expect(splashAsset.existsSync(), isTrue);
    expect(
      splashAsset.lengthSync(),
      greaterThan(100000),
      reason: 'The production splash must use the enhanced high-resolution asset.',
    );
    expect(
      File(
        'android/app/src/main/res/drawable-nodpi/fieldpulse_splash_mark.webp',
      ).existsSync(),
      isTrue,
    );
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
    expect(
      File('android/app/src/main/res/drawable/fieldpulse_splash_vector.xml')
          .existsSync(),
      isFalse,
    );
    expect(
      File(
        'android/app/src/main/res/drawable/fieldpulse_launcher_foreground.xml',
      ).existsSync(),
      isFalse,
    );
  });
}
