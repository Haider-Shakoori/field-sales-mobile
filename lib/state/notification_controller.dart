import 'dart:async';

import 'package:flutter/foundation.dart';

import '../features/notifications/notification_repository.dart';
import 'app_state.dart';

class NotificationController extends ChangeNotifier {
  NotificationController({required this.appState, required this.repository});

  final AppState appState;
  final NotificationRepository repository;
  List<MobileNotification> items = const [];
  bool loading = false;
  Timer? _timer;

  int get unreadCount => items.where((item) => item.unread).length;

  void start() {
    _timer?.cancel();
    if (!appState.signedIn) return;
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => refresh(silent: true));
    unawaited(refresh(silent: true));
  }

  Future<void> refresh({bool silent = false}) async {
    if (!appState.signedIn || loading) return;
    if (!silent) {
      loading = true;
      notifyListeners();
    }

    try {
      items = await repository.list();
    } catch (_) {
      // Notifications are helpful but must never block field work.
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> markRead(MobileNotification item) async {
    if (!item.unread) return;
    await repository.markRead(item.id);
    await refresh(silent: true);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    items = const [];
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
