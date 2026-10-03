import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n.dart';

class AppLocaleController extends ChangeNotifier {
  static const _preferenceKey = 'fieldpulse.locale';

  String _code = 'en';

  String get code => _code;

  Locale get locale => switch (_code) {
    'fa' => const Locale('fa', 'AF'),
    'ps' => const Locale('ps', 'AF'),
    _ => const Locale('en'),
  };

  bool get isRtl => _code == 'fa' || _code == 'ps';

  static const supportedLocales = <Locale>[
    Locale('en'),
    Locale('fa', 'AF'),
    Locale('ps', 'AF'),
  ];

  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_preferenceKey) ?? 'en';
    _code = L10n.supportedCodes.contains(saved) ? saved : 'en';
    await L10n.initialize(_code);
  }

  Future<void> setLocale(String code) async {
    if (!L10n.supportedCodes.contains(code) || code == _code) return;

    await L10n.load(code);
    _code = code;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_preferenceKey, code);

    notifyListeners();
  }
}
