import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppLocalizations {
  AppLocalizations({
    required this.locale,
    required Map<String, String> english,
    required Map<String, String> localized,
  }) : _english = english,
       _localized = localized;

  final Locale locale;
  final Map<String, String> _english;
  final Map<String, String> _localized;

  static const supportedLocales = <Locale>[
    Locale('en'),
    Locale('fa', 'AF'),
    Locale('ps', 'AF'),
  ];

  static const delegate = _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) {
    final value = Localizations.of<AppLocalizations>(
      context,
      AppLocalizations,
    );
    assert(value != null, 'AppLocalizations is not available in this context.');
    return value!;
  }

  String t(String key, [Map<String, Object?> args = const {}]) {
    var value = _localized[key]?.trim();
    if (value == null || value.isEmpty) {
      value = _english[key]?.trim();
    }
    value ??= key;

    for (final entry in args.entries) {
      value = value!.replaceAll('{${entry.key}}', '${entry.value ?? ''}');
    }

    return value;
  }

  bool get isRtl => const {'fa', 'ps'}.contains(locale.languageCode);

  static Future<Map<String, String>> _loadCatalog(String code) async {
    final raw = await rootBundle.loadString('assets/lang/$code.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;

    return json.map(
      (key, value) => MapEntry(key, value?.toString() ?? ''),
    );
  }

  static Future<AppLocalizations> load(Locale locale) async {
    final english = await _loadCatalog('en');
    final code = switch (locale.languageCode) {
      'fa' => 'fa',
      'ps' => 'ps',
      _ => 'en',
    };
    final localized = code == 'en' ? english : await _loadCatalog(code);

    return AppLocalizations(
      locale: locale,
      english: english,
      localized: localized,
    );
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      const {'en', 'fa', 'ps'}.contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) =>
      AppLocalizations.load(locale);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

extension AppLocalizationContext on BuildContext {
  String tr(String key, [Map<String, Object?> args = const {}]) =>
      AppLocalizations.of(this).t(key, args);
}
