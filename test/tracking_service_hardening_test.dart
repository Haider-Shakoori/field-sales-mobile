import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('GPS tracking serializes slow position persistence', () {
    final source = File('lib/features/gps/tracking_service.dart')
        .readAsStringSync();

    expect(source, contains('bool _processingPosition = false'));
    expect(source, contains('Position? _queuedPosition'));
    expect(source, contains('unawaited(_queuePosition(tenantId, position))'));
    expect(source, contains('if (_processingPosition)'));
    expect(source, contains('_queuedPosition = position'));
    expect(source, contains('await gpsRepository.store('));
    expect(source, contains('_queuedPosition = null'));
    expect(source, contains('A single failed GPS persistence attempt'));
  });
}
