import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../../core/db/app_database.dart';
import 'gps_repository.dart';

class TrackingService {
  TrackingService({required this.db, required this.gpsRepository});
  final AppDatabase db;
  final GpsRepository gpsRepository;
  StreamSubscription<Position>? _sub;
  bool get active => _sub != null;
  Future<void> start({required int movingSeconds}) async {
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
      (p) => gpsRepository.store(
        latitude: p.latitude,
        longitude: p.longitude,
        accuracy: p.accuracy,
        altitude: p.altitude,
        speed: p.speed,
        heading: p.heading,
        isMock: p.isMocked,
        recordedAt: p.timestamp,
      ),
    );
  }

  void stop() {
    final s = _sub;
    _sub = null;
    unawaited(s?.cancel());
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
