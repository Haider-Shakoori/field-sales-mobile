import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../features/collections/collection_repository.dart';
import 'app_state.dart';

class CollectionController extends ChangeNotifier {
  CollectionController({required this.appState, required this.repository});

  final AppState appState;
  final CollectionRepository repository;

  bool busy = false;
  String? message;
  String? loadedTenantId;
  int pending = 0;
  List<Map<String, dynamic>> collections = const [];
  List<Map<String, dynamic>> balances = const [];

  Future<void> initialize() async {
    await reloadLocal();
    if (appState.signedIn) {
      await sync(silent: true);
    }
  }

  Future<void> reloadLocal() async {
    final tenantId = appState.session?.tenantId;
    if (tenantId == null) {
      loadedTenantId = null;
      pending = 0;
      collections = const [];
      balances = const [];
      notifyListeners();
      return;
    }

    loadedTenantId = tenantId;
    collections = await repository.list(tenantId);
    balances = await repository.balances(tenantId);
    pending = await repository.pendingCount(tenantId);
    notifyListeners();
  }

  List<Map<String, dynamic>> balancesForCustomer(String customerUuid) {
    return balances
        .where((row) => row['customer_uuid']?.toString() == customerUuid)
        .toList();
  }

  Future<void> create({
    required Map<String, dynamic> customer,
    required String currency,
    required double amount,
    required String paymentMethod,
    String? referenceNumber,
    String? visitUuid,
    String? notes,
  }) async {
    final tenantId = appState.session?.tenantId;
    if (tenantId == null || busy) return;

    busy = true;
    message = null;
    notifyListeners();

    try {
      final position = await _position();

      await repository.createOffline(
        tenantId: tenantId,
        customer: customer,
        collectedAt: DateTime.now().toUtc(),
        currency: currency,
        amount: amount,
        paymentMethod: paymentMethod,
        referenceNumber: referenceNumber,
        visitUuid: visitUuid,
        notes: notes,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
      );

      await reloadLocal();
      message = 'Collection saved locally.';
      await sync(silent: true);
    } catch (error) {
      message = error.toString().replaceFirst('Bad state: ', '');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> sync({bool silent = false}) async {
    final tenantId = appState.session?.tenantId;
    if (tenantId == null) return;

    if (!silent) {
      busy = true;
      message = null;
      notifyListeners();
    }

    try {
      final result = await repository.syncPending(tenantId);
      await repository.refreshServerHistory(tenantId);
      await repository.refreshBalances(tenantId);
      await reloadLocal();

      if (!silent) {
        message = result.failed == 0
            ? 'Collection sync complete. ${result.synced} pending collections processed.'
            : 'Collection sync completed with ${result.failed} pending failures.';
      }
    } catch (_) {
      await reloadLocal();
      if (!silent) {
        message = 'Offline mode: collections remain stored locally.';
      }
    } finally {
      if (!silent) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<Position> _position() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Location services are disabled.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError('Location permission is required for collections.');
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }
}
