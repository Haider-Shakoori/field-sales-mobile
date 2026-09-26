import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release candidate uses approved FieldPulse branding', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    final app = File('lib/app.dart').readAsStringSync();
    final splash = File('lib/ui/fieldpulse_splash_screen.dart')
        .readAsStringSync();

    expect(manifest, contains('android:label="FieldPulse"'));
    expect(manifest, contains('android:icon="@mipmap/ic_launcher"'));
    expect(manifest, isNot(contains('sym_def_app_icon')));
    expect(app, contains("title: 'FieldPulse'"));
    expect(splash, contains("text: 'Field'"));
    expect(splash, contains("text: 'Pulse'"));
    expect(splash, contains("'by BusinessOS'"));
    expect(splash, contains('_FieldPulseMarkPainter'));
    expect(splash, isNot(contains('AssetImage(')));
    expect(
      File('android/app/src/main/res/drawable/fieldpulse_launcher_foreground.xml')
          .existsSync(),
      isTrue,
    );
    expect(
      File('android/app/src/main/res/mipmap-anydpi/ic_launcher.xml').existsSync(),
      isTrue,
    );
    expect(
      File('android/app/src/main/res/drawable-nodpi/fieldpulse_launcher_foreground.png')
          .existsSync(),
      isFalse,
    );
    expect(
      File('android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.webp').existsSync(),
      isFalse,
    );
    expect(
      File('android/app/src/main/res/drawable/fieldpulse_splash_vector.xml')
          .existsSync(),
      isTrue,
    );
    expect(
      File('android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml')
          .existsSync(),
      isTrue,
    );
    expect(
      File('android/app/src/main/res/values-v31/styles.xml').existsSync(),
      isTrue,
    );
  });
}
