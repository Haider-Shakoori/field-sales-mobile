import 'package:flutter/foundation.dart';

import '../features/targets/target_repository.dart';
import 'app_state.dart';

class TargetController extends ChangeNotifier {
  TargetController({required this.appState, required this.repository});

  final AppState appState;
  final TargetRepository repository;

  bool busy = false;
  String? message;
  List<Map<String, dynamic>> currentTargets = const [];
  List<Map<String, dynamic>> history = const [];

  Future<void> initialize() async {
    await reloadLocal();
    if (appState.signedIn) {
      await sync(silent: true);
    }
  }

  Future<void> reloadLocal() async {
    final tenantId = appState.session?.tenantId;
    if (tenantId == null) {
      currentTargets = const [];
      history = const [];
      notifyListeners();
      return;
    }

    currentTargets = await repository.current(tenantId);
    history = await repository.history(tenantId);
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
      await repository.refresh(tenantId);
      await reloadLocal();
      if (!silent) message = 'Targets refreshed.';
    } catch (_) {
      await reloadLocal();
      if (!silent) message = 'Offline mode: cached targets remain available.';
    } finally {
      if (!silent) {
        busy = false;
        notifyListeners();
      }
    }
  }
}
