import 'package:flutter/foundation.dart';

import '../features/team/team_repository.dart';
import 'app_state.dart';

class TeamController extends ChangeNotifier {
  TeamController({required this.appState, required this.repository});

  final AppState appState;
  final TeamRepository repository;

  bool busy = false;
  String? message;
  Map<String, dynamic>? overview;

  List<Map<String, dynamic>> get locations {
    final rows = overview?['locations'];
    if (rows is! List) return const [];

    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  List<Map<String, dynamic>> get hierarchy {
    final rows = overview?['hierarchy'];
    if (rows is! List) return const [];

    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  List<Map<String, dynamic>> get recentActivity {
    final rows = overview?['recent_activity'];
    if (rows is! List) return const [];

    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Map<String, dynamic> get summary {
    final value = overview?['summary'];
    return value is Map
        ? Map<String, dynamic>.from(value)
        : const <String, dynamic>{};
  }

  Future<void> refresh({bool silent = false}) async {
    if (!appState.isLeadership || busy) return;

    busy = true;
    if (!silent) message = null;
    notifyListeners();

    try {
      overview = await repository.overview();
    } catch (error) {
      if (!silent) {
        message = error.toString();
      }
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void clear() {
    overview = null;
    message = null;
    notifyListeners();
  }
}
