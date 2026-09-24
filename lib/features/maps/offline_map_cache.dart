import 'dart:io';

import 'package:flutter_map/flutter_map.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class OfflineMapCache {
  OfflineMapCache._();

  static const maxCacheBytes = 512 * 1024 * 1024;

  static MapCachingProvider? _provider;
  static String? _directoryPath;

  static Future<void> initialize() async {
    if (_provider != null) {
      return;
    }

    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      p.join(support.path, 'fieldpulse', 'map_tiles'),
    );
    await directory.create(recursive: true);

    _directoryPath = directory.path;
    _provider = BuiltInMapCachingProvider.getOrCreateInstance(
      cacheDirectory: directory.path,
      maxCacheSize: maxCacheBytes,
    );
  }

  static MapCachingProvider get provider {
    final value = _provider;
    if (value == null) {
      throw StateError('OfflineMapCache.initialize() must run before maps.');
    }

    return value;
  }

  static String get directoryPath {
    final value = _directoryPath;
    if (value == null) {
      throw StateError('OfflineMapCache.initialize() must run before maps.');
    }

    return value;
  }

  static Future<int> sizeBytes() async {
    final directory = Directory(directoryPath);
    if (!await directory.exists()) {
      return 0;
    }

    var total = 0;

    await for (final entity in directory.list(recursive: true)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } catch (_) {
          // Cache accounting is best-effort.
        }
      }
    }

    return total;
  }
}
