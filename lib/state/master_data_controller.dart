import 'package:flutter/foundation.dart';

import '../features/customers/customer_repository.dart';
import '../features/master_data/master_data_repository.dart';
import 'app_state.dart';

class MasterDataController extends ChangeNotifier {
  MasterDataController({
    required this.appState,
    required this.masterData,
    required this.customersRepository,
  });

  final AppState appState;
  final MasterDataRepository masterData;
  final CustomerRepository customersRepository;

  bool busy = false;
  String? message;
  String? loadedTenantId;
  DateTime? lastSyncedAt;
  int pending = 0;

  List<Map<String, dynamic>> customers = const [];
  List<Map<String, dynamic>> territories = const [];
  List<Map<String, dynamic>> routes = const [];
  List<Map<String, dynamic>> routeCustomers = const [];
  List<Map<String, dynamic>> products = const [];
  List<Map<String, dynamic>> priceLists = const [];

  Future<void> initialize() async {
    await reloadLocal();

    if (appState.signedIn) {
      await sync(silent: true);
    }
  }

  Future<void> reloadLocal() async {
    final tenantId = appState.session?.tenantId;

    if (tenantId == null) {
      _clear();
      return;
    }

    if (loadedTenantId != tenantId) {
      _clear();
      loadedTenantId = tenantId;
    }

    customers = await masterData.list('customers', tenantId);
    territories = await masterData.list('territories', tenantId);
    routes = await masterData.list('routes', tenantId);
    routeCustomers = await masterData.list('route_customers', tenantId);
    products = await masterData.list('products', tenantId);
    priceLists = await masterData.list('price_lists', tenantId);
    pending = await masterData.pendingCount(tenantId);
    notifyListeners();
  }

  Future<void> sync({bool silent = false}) async {
    final tenantId = appState.session?.tenantId;

    if (tenantId == null || busy) {
      return;
    }

    busy = true;
    if (!silent) {
      message = null;
    }
    notifyListeners();

    try {
      final customerResult = await customersRepository.syncPending(tenantId);
      await masterData.refreshAll(tenantId);
      await reloadLocal();
      lastSyncedAt = DateTime.now().toUtc();

      if (!silent) {
        message = customerResult.failed == 0
            ? 'Sync complete. ${customerResult.synced} pending customers uploaded.'
            : 'Sync completed with ${customerResult.failed} customer upload failures.';
      }
    } catch (_) {
      await reloadLocal();
      if (!silent) {
        message = 'Offline mode: showing the latest local data.';
      }
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> createCustomer({
    required String name,
    String? code,
    String? phone,
    String? address,
    double? latitude,
    double? longitude,
  }) async {
    final tenantId = appState.session?.tenantId;
    if (tenantId == null) {
      return;
    }

    await customersRepository.createOffline(
      tenantId: tenantId,
      name: name,
      code: code,
      phone: phone,
      address: address,
      latitude: latitude,
      longitude: longitude,
    );

    await reloadLocal();
    message = 'Customer saved locally. It will sync when online.';
    notifyListeners();

    await sync(silent: true);
  }

  Future<void> updateCustomer({
    required String customerUuid,
    required String name,
    String? code,
    String? phone,
    String? address,
    required double latitude,
    required double longitude,
  }) async {
    final tenantId = appState.session?.tenantId;
    if (tenantId == null) {
      return;
    }

    await customersRepository.updateOffline(
      tenantId: tenantId,
      customerUuid: customerUuid,
      name: name,
      code: code,
      phone: phone,
      address: address,
      latitude: latitude,
      longitude: longitude,
    );

    await reloadLocal();
    message = 'Customer changes saved locally. They will sync when online.';
    notifyListeners();

    await sync(silent: true);
  }

  void _clear() {
    loadedTenantId = null;
    customers = const [];
    territories = const [];
    routes = const [];
    routeCustomers = const [];
    products = const [];
    priceLists = const [];
    pending = 0;
    lastSyncedAt = null;
    message = null;
  }
}
