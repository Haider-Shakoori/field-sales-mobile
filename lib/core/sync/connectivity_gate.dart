import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityGate {
  ConnectivityGate({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  static ConnectivityGate instance = ConnectivityGate();

  final Connectivity _connectivity;

  Future<bool> isOnline() async {
    try {
      return _isOnline(await _connectivity.checkConnectivity());
    } catch (_) {
      return true;
    }
  }

  Stream<bool> get statusChanges =>
      _connectivity.onConnectivityChanged.map(_isOnline).distinct();

  static bool _isOnline(List<ConnectivityResult> results) => results.any(
    (result) =>
        result == ConnectivityResult.wifi ||
        result == ConnectivityResult.mobile ||
        result == ConnectivityResult.ethernet ||
        result == ConnectivityResult.vpn,
  );
}
