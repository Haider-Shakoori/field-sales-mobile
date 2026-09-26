import 'package:flutter/foundation.dart';

import '../features/management/management_repository.dart';
import 'app_state.dart';

class ManagementController extends ChangeNotifier {
  ManagementController({
    required this.appState,
    required this.repository,
  });

  final AppState appState;
  final ManagementRepository repository;

  bool busy = false;
  String? message;
  Map<String, dynamic>? overview;

  Future<void> refresh({bool silent = false}) async {
    if (!appState.signedIn || appState.session?.isManagement != true || busy) {
      return;
    }

    busy = true;
    if (!silent) message = null;
    notifyListeners();

    try {
      overview = await repository.overview();
      message = null;
    } catch (_) {
      if (!silent) {
        message =
            'Team data could not be refreshed. Check connectivity and try again.';
      }
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void clear() {
    overview = null;
    message = null;
    busy = false;
    notifyListeners();
  }
}
