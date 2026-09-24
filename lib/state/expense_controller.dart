import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../features/expenses/expense_repository.dart';
import 'app_state.dart';

class ExpenseController extends ChangeNotifier {
  ExpenseController({required this.appState, required this.repository});

  final AppState appState;
  final ExpenseRepository repository;

  bool busy = false;
  String? message;
  int pending = 0;
  List<Map<String, dynamic>> expenses = const [];

  Future<void> initialize() async {
    await reloadLocal();
    if (appState.signedIn) {
      await sync(silent: true);
    }
  }

  Future<void> reloadLocal() async {
    final tenantId = appState.session?.tenantId;
    if (tenantId == null) {
      pending = 0;
      expenses = const [];
      notifyListeners();
      return;
    }

    expenses = await repository.list(tenantId);
    pending = await repository.pendingCount(tenantId);
    notifyListeners();
  }

  Future<void> create({
    required String category,
    required String currency,
    required double amount,
    double? fuelLiters,
    double? fuelUnitPrice,
    double? odometerKm,
    String? merchant,
    String? referenceNumber,
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
        spentAt: DateTime.now().toUtc(),
        category: category,
        currency: currency,
        amount: amount,
        fuelLiters: fuelLiters,
        fuelUnitPrice: fuelUnitPrice,
        odometerKm: odometerKm,
        merchant: merchant,
        referenceNumber: referenceNumber,
        notes: notes,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
      );

      await reloadLocal();
      message = 'Expense saved locally.';
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
      await repository.refreshHistory(tenantId);
      await reloadLocal();

      if (!silent) {
        message = result.failed == 0
            ? 'Expense sync complete. ${result.synced} pending claims processed.'
            : 'Expense sync completed with ${result.failed} pending failures.';
      }
    } catch (_) {
      await reloadLocal();
      if (!silent) {
        message = 'Offline mode: expenses remain stored locally.';
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
      throw StateError('Location permission is required for expenses.');
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }
}
