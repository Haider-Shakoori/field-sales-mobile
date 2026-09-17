import 'package:flutter/foundation.dart';

import 'connectivity_service.dart';
import 'sync_engine.dart';
import 'sync_queue.dart';
import 'sync_repository.dart';
import 'sync_status.dart';

/// Owns the device network state and the outbox queue counts, exposing a
/// change-notification stream for the UI status bar.
///
/// Batch 6 does NOT auto-drain the queue: there is no periodic ticker and no
/// push happens when the device comes back online, because the sync transport
/// endpoint is deferred to Batch 12. [maybeSync] remains available for an
/// explicit manual drain, but the engine the app is wired to is
/// [SyncEngine.deferred], i.e. it never transmits.
class SyncController extends ChangeNotifier {
  SyncController({
    required ConnectivityService connectivity,
    required SyncEngine engine,
  }) : _connectivity = connectivity,
       _engine = engine {
    _connectivity.states.listen(_onNetworkChanged);
  }

  final ConnectivityService _connectivity;
  final SyncEngine _engine;

  NetworkState _network = NetworkState.offline;
  NetworkState get network => _network;
  bool get isOnline => _network == NetworkState.online;

  bool _syncing = false;
  bool get syncing => _syncing;

  DateTime? _lastSuccessfulSync;
  DateTime? get lastSuccessfulSync => _lastSuccessfulSync;

  SyncQueueCounts _counts = SyncQueueCounts(0, 0, 0);
  SyncQueueCounts get counts => _counts;

  Future<void> start() async {
    await _connectivity.start();
    _refreshCounts();
  }

  Future<void> shutdown() async {
    await _connectivity.stop();
    super.dispose();
  }

  Future<void> _onNetworkChanged(NetworkState next) async {
    _network = next;
    notifyListeners();
  }

  /// Drains the queue when online and not already running. With the deferred
  /// engine this is a no-op that reports `false` without touching the network.
  Future<bool> maybeSync() async {
    if (!isOnline || _syncing) {
      return false;
    }
    _syncing = true;
    notifyListeners();
    try {
      final outcome = await _engine.drain();
      if (outcome.pushed > 0) {
        _lastSuccessfulSync = DateTime.now();
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      _syncing = false;
      _refreshCounts();
      notifyListeners();
    }
  }

  Future<void> _refreshCounts() async {
    _counts = await SyncQueueRepository.instance.counts();
    notifyListeners();
  }
}
