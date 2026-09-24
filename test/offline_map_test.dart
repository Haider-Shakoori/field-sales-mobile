import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('offline map cache is durable and bounded', () {
    final source = File(
      'lib/features/maps/offline_map_cache.dart',
    ).readAsStringSync();

    expect(source, contains('getApplicationSupportDirectory()'));
    expect(source, contains("p.join(support.path, 'fieldpulse', 'map_tiles')"));
    expect(source, contains('BuiltInMapCachingProvider.getOrCreateInstance'));
    expect(source, contains('maxCacheBytes = 512 * 1024 * 1024'));
    expect(source, isNot(contains('getTemporaryDirectory()')));
  });

  test('visit map uses persistent caching without a fallback layer', () {
    final source = File('lib/ui/visits_map_view.dart').readAsStringSync();

    expect(source, contains('cachingProvider: OfflineMapCache.provider'));
    expect(source, contains('Offline map · cached tiles only'));
    expect(source, isNot(contains('fallbackUrl:')));
  });

  test('tile source is configurable and defaults to compliant HTTPS OSM', () {
    final source = File('lib/core/config.dart').readAsStringSync();

    expect(source, contains("String.fromEnvironment('TILE_URL_TEMPLATE'"));
    expect(
      source,
      contains('https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
    );
    expect(
      source,
      contains('TILE_URL_TEMPLATE must contain {z}, {x}, and {y} placeholders.'),
    );
    expect(
      source,
      contains('Release builds require an HTTPS TILE_URL_TEMPLATE.'),
    );
  });
}
