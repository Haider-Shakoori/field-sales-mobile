import 'package:flutter/foundation.dart';

import '../features/appointments/appointment_repository.dart';
import 'app_state.dart';

class AppointmentController extends ChangeNotifier {
  AppointmentController({required this.appState, required this.repository});

  final AppState appState;
  final AppointmentRepository repository;

  bool busy = false;
  String? message;
  String? loadedTenantId;
  int pending = 0;
  List<Map<String, dynamic>> appointments = const [];

  Future<void> reloadLocal() async {
    final tenantId = appState.session?.tenantId;

    if (tenantId == null) {
      loadedTenantId = null;
      pending = 0;
      appointments = const [];
      notifyListeners();
      return;
    }

    if (loadedTenantId != tenantId) {
      loadedTenantId = tenantId;
      appointments = const [];
    }

    appointments = await repository.list(tenantId);
    pending = await repository.pendingCount(tenantId);
    notifyListeners();
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
      await repository.refresh(tenantId);
      await reloadLocal();

      if (!silent) {
        message = result.failed == 0
            ? 'Calendar sync complete.'
            : 'Calendar sync completed with ' +
                  result.failed.toString() +
                  ' pending failure(s).';
      }
    } catch (_) {
      await reloadLocal();
      if (!silent) {
        message = 'Offline mode: cached appointments remain available.';
      }
    } finally {
      if (!silent) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> create({
    Map<String, dynamic>? customer,
    required String title,
    required String type,
    required DateTime startsAt,
    DateTime? endsAt,
    int? reminderMinutesBefore,
    String? location,
    String? notes,
  }) async {
    final tenantId = appState.session?.tenantId;
    if (tenantId == null || busy) return;

    busy = true;
    message = null;
    notifyListeners();

    try {
      await repository.createLocal(
        tenantId: tenantId,
        customer: customer,
        title: title,
        type: type,
        startsAt: startsAt,
        endsAt: endsAt,
        reminderMinutesBefore: reminderMinutesBefore,
        location: location,
        notes: notes,
      );
      await reloadLocal();
      message = 'Appointment saved locally.';
      await sync(silent: true);
    } catch (error) {
      message = error.toString();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> updateStatus(
    Map<String, dynamic> appointment,
    String status,
  ) async {
    final tenantId = appState.session?.tenantId;
    final uuid = appointment['offline_uuid']?.toString();

    if (tenantId == null || uuid == null || busy) return;

    busy = true;
    message = null;
    notifyListeners();

    try {
      await repository.updateStatusLocal(
        tenantId: tenantId,
        offlineUuid: uuid,
        status: status,
      );
      await reloadLocal();
      message = 'Appointment updated locally.';
      await sync(silent: true);
    } catch (error) {
      message = error.toString();
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
