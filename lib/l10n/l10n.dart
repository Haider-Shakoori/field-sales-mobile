import 'dart:convert';

import 'package:flutter/services.dart';

class L10n {
  L10n._();

  static const supportedCodes = <String>['en', 'fa', 'ps'];

  static Map<String, String> _english = const {};
  static Map<String, String> _active = const {};
  static Map<String, String> _englishToKey = const {};
  static List<_TemplateMatcher> _templates = const [];
  static final Map<String, String> _cache = <String, String>{};
  static String _code = 'en';

  static String get code => _code;

  static Future<void> initialize([String code = 'en']) async {
    _english = await _loadCatalog('en');
    _englishToKey = {
      for (final entry in _english.entries) entry.value: entry.key,
    };
    _templates = _english.entries
        .where((entry) => entry.value.contains('{'))
        .map((entry) => _TemplateMatcher.from(entry.key, entry.value))
        .whereType<_TemplateMatcher>()
        .toList(growable: false);
    await load(code);
  }

  static Future<void> load(String code) async {
    _code = supportedCodes.contains(code) ? code : 'en';
    _active = _code == 'en' ? _english : await _loadCatalog(_code);
    _cache.clear();
  }

  static String t(String key, [Map<String, Object?> params = const {}]) {
    final selected = _active[key];
    final fallback = _english[key] ?? key;
    var value = selected != null && selected.trim().isNotEmpty
        ? selected
        : fallback;

    for (final entry in params.entries) {
      value = value.replaceAll('{${entry.key}}', '${entry.value ?? ''}');
    }

    return value;
  }

  static String text(String input) {
    if (input.isEmpty || _code == 'en') return input;

    final cached = _cache[input];
    if (cached != null) return cached;

    final exactKey = _englishToKey[input];
    if (exactKey != null) {
      final translated = t(exactKey);
      _cache[input] = translated;
      return translated;
    }

    for (final template in _templates) {
      final match = template.pattern.firstMatch(input);
      if (match == null) continue;

      final params = <String, Object?>{};
      for (var index = 0; index < template.placeholders.length; index++) {
        params[template.placeholders[index]] = match.group(index + 1) ?? '';
      }

      final translated = t(template.key, params);
      _cache[input] = translated;
      return translated;
    }

    _cache[input] = input;
    return input;
  }

  static void installForTesting({
    required Map<String, String> english,
    required Map<String, String> active,
    String code = 'fa',
  }) {
    _english = Map<String, String>.unmodifiable(english);
    _active = Map<String, String>.unmodifiable(active);
    _code = code;
    _englishToKey = {
      for (final entry in _english.entries) entry.value: entry.key,
    };
    _templates = _english.entries
        .where((entry) => entry.value.contains('{'))
        .map((entry) => _TemplateMatcher.from(entry.key, entry.value))
        .whereType<_TemplateMatcher>()
        .toList(growable: false);
    _cache.clear();
  }

  static Future<Map<String, String>> _loadCatalog(String code) async {
    final raw = await rootBundle.loadString('assets/lang/$code.json');
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((key, value) => MapEntry(key, value?.toString() ?? ''));
  }
}

class _TemplateMatcher {
  const _TemplateMatcher({
    required this.key,
    required this.pattern,
    required this.placeholders,
  });

  final String key;
  final RegExp pattern;
  final List<String> placeholders;

  static _TemplateMatcher? from(String key, String template) {
    final placeholders = <String>[];
    final buffer = StringBuffer('^');
    var cursor = 0;

    for (final match in RegExp(r'\{([^{}]+)\}').allMatches(template)) {
      buffer.write(RegExp.escape(template.substring(cursor, match.start)));
      buffer.write('(.*?)');
      placeholders.add(match.group(1)!);
      cursor = match.end;
    }

    if (placeholders.isEmpty) return null;

    buffer
      ..write(RegExp.escape(template.substring(cursor)))
      ..write(r'$');

    return _TemplateMatcher(
      key: key,
      pattern: RegExp(buffer.toString(), dotAll: true),
      placeholders: placeholders,
    );
  }
}
