import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../../core/db/app_database.dart';
import 'gps_repository.dart';

class TrackingService {
  TrackingService({required this.db, required this.gpsRepository});
  final AppDatabase db;
  final GpsRepository gpsRepository;
  StreamSubscription<Position>? _sub;
  bool _processingPosition = false;
  Position? _queuedPosition;

  bool get active => _sub != null;
  Future<void> start({
    required String tenantId,
    required int movingSeconds,
  }) async {
    if (_sub != null) return;
    final session = await db.db.query(
      'local_work_sessions',
      where: 'status=?',
      whereArgs: ['active'],
      limit: 1,
    );
    if (session.isEmpty) return;
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }
    final settings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
      intervalDuration: Duration(seconds: movingSeconds),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'Field Sales',
        notificationText: 'Location tracking active',
        enableWakeLock: true,
        setOngoing: true,
      ),
    );
    _sub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (position) {
        unawaited(_queuePosition(tenantId, position));
      },
      onError: (_) {
        stop();
      },
      cancelOnError: false,
    );
  }

  Future<void> _queuePosition(String tenantId, Position position) async {
    if (_processingPosition) {
      // Keep only the newest fix while a previous point is still being
      // persisted. This prevents a slow emulator/device from building an
      // unbounded backlog of battery/network/database work.
      _queuedPosition = position;
      return;
    }

    _processingPosition = true;
    var current = position;

    try {
      while (true) {
        try {
          await gpsRepository.store(
            tenantId: tenantId,
            latitude: current.latitude,
            longitude: current.longitude,
            accuracy: current.accuracy,
            altitude: current.altitude,
            speed: current.speed,
            heading: current.heading,
            isMock: current.isMocked,
            recordedAt: current.timestamp,
          );
        } catch (_) {
          // A single failed GPS persistence attempt must never block the
          // location stream or freeze the UI. The next valid fix can continue.
        }

        final next = _queuedPosition;
        _queuedPosition = null;
        if (next == null) break;
        current = next;
      }
    } finally {
      _processingPosition = false;
    }
  }

  void stop() {
    final subscription = _sub;
    _sub = null;
    _queuedPosition = null;
    unawaited(subscription?.cancel());
  }

  Future<Position?> oneShot({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (p == LocationPermission.denied ||
        p == LocationPermission.deniedForever) {
      return null;
    }
    try {
      final x = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(timeout);
      return x.accuracy <= 200 ? x : null;
    } catch (_) {
      return null;
    }
  }
}
