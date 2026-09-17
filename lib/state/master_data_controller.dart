import 'package:flutter/foundation.dart';

import '../core/storage/master_data_repository.dart';

/// Orchestrates the offline master-data cache: exposes refresh progress and
/// errors so screens can subscribe, while reads always come from SQLite via
/// the repository (never the network).
class MasterDataController extends ChangeNotifier {
  MasterDataController(this._repository);

  final MasterDataRepository _repository;

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  DateTime? _lastRefreshed;
  DateTime? get lastRefreshed => _lastRefreshed;

  Map<String, int> _counts = const {};
  Map<String, int> get counts => _counts;

  MasterDataRepository get repository => _repository;

  /// Pulls every master-data domain (all pages) into the SQLite cache.
  Future<void> refresh({bool includeRouteCustomers = true}) async {
    if (_loading) {
      return;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await _repository.refreshAll(
        includeRouteCustomers: includeRouteCustomers,
      );
      _lastRefreshed = DateTime.now();
      _counts = await _repository.localCounts();
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Reloads cached counts without touching the network (used on screen open).
  Future<void> reloadCounts() async {
    _counts = await _repository.localCounts();
    notifyListeners();
  }
}
