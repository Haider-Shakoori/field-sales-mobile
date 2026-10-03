import 'package:flutter_test/flutter_test.dart';

import 'package:field_sales_mobile/core/storage/secret_store.dart';
import 'package:field_sales_mobile/l10n/l10n.dart';
import 'package:field_sales_mobile/l10n/locale_controller.dart';

class _MemorySecretStore extends SecretStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('L10n', () {
    test('resolves exact English source through active catalog', () {
      L10n.installForTesting(
        english: const {'greeting': 'Hello'},
        active: const {'greeting': 'سلام'},
      );

      expect(L10n.text('Hello'), 'سلام');
      expect(L10n.text('Not translated'), 'Not translated');
    });

    test('preserves runtime values in placeholder translations', () {
      L10n.installForTesting(
        english: const {'welcome': 'Hello {name}, {count} pending'},
        active: const {'welcome': 'سلام {name}، {count} در انتظار'},
      );

      expect(L10n.text('Hello Ahmad, 3 pending'), 'سلام Ahmad، 3 در انتظار');
    });

    test('falls back to English when a translation is blank', () {
      L10n.installForTesting(
        english: const {'sync': 'Sync'},
        active: const {'sync': ''},
      );

      expect(L10n.text('Sync'), 'Sync');
    });
  });

  group('AppLocaleController', () {
    test('restores Dari and marks it RTL', () async {
      final store = _MemorySecretStore()..values['fieldpulse.locale'] = 'fa';
      final controller = AppLocaleController(storage: store);

      await controller.restore();

      expect(controller.code, 'fa');
      expect(controller.locale.languageCode, 'fa');
      expect(controller.locale.countryCode, 'AF');
      expect(controller.isRtl, isTrue);
    });

    test('persists Pashto selection', () async {
      final store = _MemorySecretStore();
      final controller = AppLocaleController(storage: store);

      await controller.restore();
      await controller.setLocale('ps');

      expect(controller.code, 'ps');
      expect(controller.isRtl, isTrue);
      expect(store.values['fieldpulse.locale'], 'ps');
    });
  });
}
