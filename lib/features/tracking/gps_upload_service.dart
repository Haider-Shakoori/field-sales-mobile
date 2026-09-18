import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/gps_api.dart';
import '../../core/models/gps_point.dart';
import '../../core/storage/gps_point_repository.dart';
import '../../core/sync/connectivity_service.dart';
import 'gps_tracking_config.dart';

/// Result of one uploader drain.
class GpsUploadOutcome {
  const GpsUploadOutcome({
    this.uploaded = 0,
    this.rejected = 0,
    this.duplicates = 0,
    this.batches = 0,
    this.skipped = false,
    this.authorizationLost = false,
    this.error,
  });

  final int uploaded;
  final int rejected;
  final int duplicates;
  final int batches;
  final bool skipped;
  final bool authorizationLost;
  final String? error;

  bool get didWork => batches > 0;
}

/// Dedicated GPS batch uploader for `POST /api/v1/gps/locations`.
///
/// Intentionally separate from the deferred Batch 12 sync engine: it drains
/// only the local GPS buffer, in chunks of at most 100 points, reusing each
/// point's original `client_uuid` and a fresh `batch_uuid` (also sent as the
/// idempotency key). Retry is deliberately simple — triggered by connectivity
/// restoration, Start/End Day and a 5-minute timer while tracking — with no
/// exponential backoff scheduler.
class GpsUploadService {
  GpsUploadService({
    required GpsPointRepository gpsPoints,
    required GpsApi gpsApi,
    required ConnectivityService connectivity,
    this.config = const GpsTrackingConfig(),
    Uuid? uuid,
  }) : _gpsPoints = gpsPoints,
       _gpsApi = gpsApi,
       _connectivity = connectivity,
       _uuid = uuid ?? const Uuid();

  final GpsPointRepository _gpsPoints;
  final GpsApi _gpsApi;
  final ConnectivityService _connectivity;
  final GpsTrackingConfig config;
  final Uuid _uuid;

  Timer? _timer;
  bool _flushing = false;
  bool _disposed = false;

  DateTime? _lastFlushAt;
  DateTime? get lastFlushAt => _lastFlushAt;

  String? _lastError;
  String? get lastError => _lastError;

  /// Called when the server rejects the token/device; the attendance
  /// controller stops tracking and preserves all local points.
  void Function(ApiException error)? onAuthorizationLost;

  bool get flushing => _flushing;

  /// Starts the 5-minute GPS flush cadence used while a session is tracking.
  void startPeriodicFlush() {
    _timer ??= Timer.periodic(config.batchFlushInterval, (_) {
      unawaited(flush());
    });
  }

  void stopPeriodicFlush() {
    _timer?.cancel();
    _timer = null;
  }

  /// Drains pending points until the buffer is empty, the server errors, or
  /// authorization is lost. Never throws; failures leave points pending.
  Future<GpsUploadOutcome> flush() async {
    if (_flushing || _disposed) {
      return const GpsUploadOutcome(skipped: true);
    }
    if (!_connectivity.isOnline) {
      return const GpsUploadOutcome(skipped: true);
    }

    _flushing = true;
    var uploaded = 0;
    var rejected = 0;
    var duplicates = 0;
    var batches = 0;
    try {
      while (!_disposed) {
        final points = await _gpsPoints.pending(limit: config.batchSize);
        if (points.isEmpty) {
          break;
        }

        final batchUuid = _uuid.v4();
        final clientUuids = points.map((p) => p.clientUuid).toList();
        await _gpsPoints.assignBatch(clientUuids, batchUuid);

        try {
          final result = await _gpsApi.uploadBatch(
            batchUuid: batchUuid,
            points: points,
          );
          batches++;
          uploaded += result.accepted;
          duplicates += result.duplicates;
          rejected += result.rejected;
          await _applyResult(points, result, batchUuid);
        } on ApiException catch (error) {
          if (error.isUnauthenticated || error.isDeviceRevoked) {
            _lastError = error.message;
            onAuthorizationLost?.call(error);
            return GpsUploadOutcome(
              uploaded: uploaded,
              rejected: rejected,
              duplicates: duplicates,
              batches: batches,
              authorizationLost: true,
              error: error.message,
            );
          }
          _lastError = error.message;
          return GpsUploadOutcome(
            uploaded: uploaded,
            rejected: rejected,
            duplicates: duplicates,
            batches: batches,
            error: error.message,
          );
        }
      }

      _lastError = null;
      _lastFlushAt = DateTime.now();
      await _purgeOldUploaded();
      return GpsUploadOutcome(
        uploaded: uploaded,
        rejected: rejected,
        duplicates: duplicates,
        batches: batches,
      );
    } finally {
      _flushing = false;
    }
  }

  Future<void> _applyResult(
    List<LocalGpsPoint> points,
    GpsUploadResult result,
    String batchUuid,
  ) async {
    final batchUuids = points.map((p) => p.clientUuid).toSet();

    if (result.hasPerPointVerdicts) {
      final uploaded = <String>{
        ...result.acceptedUuids,
        ...result.duplicateUuids,
      }.where(batchUuids.contains).toList();
      final rejected = result.rejectedUuids.where(batchUuids.contains).toList();
      await _gpsPoints.markUploaded(uploaded, batchUuid: batchUuid);
      await _gpsPoints.markRejected(
        rejected,
        batchUuid: batchUuid,
        error: 'Rejected by server (per-point verdict).',
      );
      return;
    }

    final all = points.map((p) => p.clientUuid).toList();
    if (result.rejected == 0) {
      await _gpsPoints.markUploaded(all, batchUuid: batchUuid);
      return;
    }
    if (result.uploadedCount == 0) {
      await _gpsPoints.markRejected(
        all,
        batchUuid: batchUuid,
        error:
            'Server rejected ${result.rejected} of ${points.length} '
            'points (accepted=${result.accepted}, '
            'duplicates=${result.duplicates}).',
      );
      return;
    }

    // Mixed verdict without per-point detail: the aggregate contract cannot
    // tell us WHICH points failed, so the whole chunk is preserved as
    // rejected (diagnostic state) rather than guessing. Server-side
    // deduplication by client_uuid makes a future precise re-upload safe.
    await _gpsPoints.markRejected(
      all,
      batchUuid: batchUuid,
      error:
          'Server partially rejected the batch '
          '(accepted=${result.accepted}, duplicates=${result.duplicates}, '
          'rejected=${result.rejected}); per-point verdicts unavailable.',
    );
  }

  Future<void> _purgeOldUploaded() async {
    final cutoff = DateTime.now().toUtc().subtract(config.uploadedRetention);
    await _gpsPoints.purgeUploadedBefore(cutoff);
  }

  void dispose() {
    _disposed = true;
    stopPeriodicFlush();
  }
}
