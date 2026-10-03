import 'package:flutter/material.dart';

import '../core/storage/secret_store.dart';

class LocaleController extends ChangeNotifier {
  LocaleController(this._secrets);

  static const _storageKey = 'app_locale';
  static const supportedLanguageCodes = {'en', 'fa', 'ps'};

  final SecretStore _secrets;

  Locale _locale = const Locale('en');
  bool _restored = false;

  Locale get locale => _locale;
  bool get restored => _restored;
  bool get isRtl => const {'fa', 'ps'}.contains(_locale.languageCode);

  Future<void> restore() async {
    final saved = (await _secrets.read(_storageKey))?.trim().toLowerCase();
    if (saved != null && supportedLanguageCodes.contains(saved)) {
      _locale = _localeFor(saved);
    }
    _restored = true;
  }

  Future<void> setLanguage(String languageCode) async {
    final normalized = languageCode.trim().toLowerCase();
    if (!supportedLanguageCodes.contains(normalized)) {
      throw ArgumentError.value(
        languageCode,
        'languageCode',
        'Unsupported FieldPulse locale.',
      );
    }

    final next = _localeFor(normalized);
    if (_locale.languageCode == next.languageCode &&
        _locale.countryCode == next.countryCode) {
      return;
    }

    _locale = next;
    await _secrets.write(_storageKey, normalized);
    notifyListeners();
  }

  Locale _localeFor(String code) => switch (code) {
    'fa' => const Locale('fa', 'AF'),
    'ps' => const Locale('ps', 'AF'),
    _ => const Locale('en'),
  };
}
