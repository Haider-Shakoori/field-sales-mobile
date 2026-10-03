import 'dart:convert';
import 'dart:io';

const _requiredHeaders = <String>{
  'key',
  'english_en',
  'dari_fa_AF',
  'pashto_ps_AF',
  'placeholders',
};

void main(List<String> args) {
  final checkOnly = args.contains('--check');
  final positional = args.where((arg) => !arg.startsWith('--'));
  final csvPath = positional.isEmpty
      ? 'translations/fieldpulse_mobile_translation_template.csv'
      : positional.first;

  final file = File(csvPath);
  if (!file.existsSync()) {
    stderr.writeln('Translation CSV not found: $csvPath');
    exitCode = 2;
    return;
  }

  final rows = _parseCsv(file.readAsStringSync());
  if (rows.isEmpty) {
    stderr.writeln('Translation CSV has no rows.');
    exitCode = 2;
    return;
  }

  final headers = rows.first;
  final missing = _requiredHeaders.difference(headers.toSet());
  if (missing.isNotEmpty) {
    stderr.writeln('Missing translation columns: ${missing.join(', ')}');
    exitCode = 2;
    return;
  }

  final byKey = <String, Map<String, String>>{};
  for (final values in rows.skip(1)) {
    final row = <String, String>{
      for (var i = 0; i < headers.length; i++)
        headers[i]: i < values.length ? values[i] : '',
    };
    final key = row['key']!.trim();
    if (key.isEmpty) continue;
    if (byKey.containsKey(key)) {
      stderr.writeln('Duplicate translation key: $key');
      exitCode = 2;
      return;
    }

    final english = row['english_en'] ?? '';
    final expected = _placeholders(english);
    for (final localeColumn in ['dari_fa_AF', 'pashto_ps_AF']) {
      final translated = row[localeColumn]?.trim() ?? '';
      if (translated.isEmpty) continue;
      final actual = _placeholders(translated);
      if (!_sameSet(expected, actual)) {
        stderr.writeln(
          'Placeholder mismatch for $key in $localeColumn. '
          'Expected $expected, found $actual.',
        );
        exitCode = 2;
        return;
      }
    }

    byKey[key] = row;
  }

  final catalogs = <String, Map<String, String>>{
    'en': {
      for (final entry in byKey.entries)
        entry.key: entry.value['english_en'] ?? '',
    },
    'fa': {
      for (final entry in byKey.entries)
        entry.key: entry.value['dari_fa_AF'] ?? '',
    },
    'ps': {
      for (final entry in byKey.entries)
        entry.key: entry.value['pashto_ps_AF'] ?? '',
    },
  };

  var mismatch = false;
  for (final entry in catalogs.entries) {
    final output = const JsonEncoder.withIndent(' ').convert(entry.value) + '\n';
    final path = 'assets/lang/${entry.key}.json';
    final outputFile = File(path);

    if (checkOnly) {
      if (!outputFile.existsSync() || outputFile.readAsStringSync() != output) {
        stderr.writeln('$path is not synchronized with $csvPath');
        mismatch = true;
      }
    } else {
      outputFile.parent.createSync(recursive: true);
      outputFile.writeAsStringSync(output);
      stdout.writeln('Updated $path (${entry.value.length} keys)');
    }
  }

  if (mismatch) {
    exitCode = 1;
  }
}

Set<String> _placeholders(String value) => RegExp(r'\{([A-Za-z0-9_]+)\}')
    .allMatches(value)
    .map((match) => match.group(1)!)
    .toSet();

bool _sameSet(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

List<List<String>> _parseCsv(String input) {
  final rows = <List<String>>[];
  var row = <String>[];
  var value = StringBuffer();
  var quoted = false;

  for (var i = 0; i < input.length; i++) {
    final char = input[i];

    if (quoted) {
      if (char == '"' && i + 1 < input.length && input[i + 1] == '"') {
        value.write('"');
        i++;
      } else if (char == '"') {
        quoted = false;
      } else {
        value.write(char);
      }
      continue;
    }

    if (char == '"') {
      quoted = true;
    } else if (char == ',') {
      row.add(value.toString());
      value = StringBuffer();
    } else if (char == '\n') {
      row.add(value.toString());
      rows.add(row);
      row = <String>[];
      value = StringBuffer();
    } else if (char != '\r') {
      value.write(char);
    }
  }

  if (value.isNotEmpty || row.isNotEmpty) {
    row.add(value.toString());
    rows.add(row);
  }

  return rows;
}
