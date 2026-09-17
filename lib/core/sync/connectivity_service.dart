import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../api/api_config.dart';
import 'sync_status.dart';

/// Broadcasts current network state and exposes a probe to check reachability.
///
/// `connectivity_plus` reports interface availability (wifi/mobile), not
/// internet reachability, so [probe] opens a lightweight TCP connection to the
/// configured API host to confirm real connectivity.
class ConnectivityService {
  ConnectivityService({this.probeTimeout = const Duration(seconds: 4)});

  final Duration probeTimeout;

  final _controller = StreamController<NetworkState>.broadcast();
  late final StreamSubscription<List<ConnectivityResult>> _sub;

  NetworkState _state = NetworkState.offline;
  NetworkState get state => _state;

  /// Emits whenever connectivity changes (online/offline/limited).
  Stream<NetworkState> get states => _controller.stream;

  bool get isOnline => _state == NetworkState.online;

  Future<void> start() async {
    _sub = Connectivity().onConnectivityChanged.listen(_onChanged);
    await refresh();
  }

  Future<void> stop() async {
    await _sub.cancel();
    await _controller.close();
  }

  Future<void> refresh() async {
    final results = await Connectivity().checkConnectivity();
    await _onChanged(results);
  }

  Future<void> _onChanged(List<ConnectivityResult> results) async {
    final hasInterface =
        results.isNotEmpty && results.any((r) => r != ConnectivityResult.none);
    if (!hasInterface) {
      _set(NetworkState.offline);
      return;
    }

    final reachable = await probe();
    _set(reachable ? NetworkState.online : NetworkState.limited);
  }

  Future<bool> probe({Uri? target}) async {
    // Opens and closes a TCP connection; never sends a payload.
    try {
      final base = Uri.parse(ApiConfig.baseUrl);
      final uri =
          target ?? Uri(scheme: base.scheme, host: base.host, port: base.port);
      final socket = await Socket.connect(
        uri.host,
        uri.port,
        timeout: probeTimeout,
      );
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _set(NetworkState next) {
    if (_state == next) {
      return;
    }
    _state = next;
    if (!_controller.isClosed) {
      _controller.add(next);
    }
  }
}
