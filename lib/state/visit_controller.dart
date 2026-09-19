import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../features/visits/visit_repository.dart';
import 'app_state.dart';

class VisitController extends ChangeNotifier {
  VisitController({required this.appState, required this.repository});

  final AppState appState;
  final VisitRepository repository;

  bool busy = false;
  String? message;
  String? loadedTenantId;
  int pending = 0;
  List<Map<String, dynamic>> visits = const [];

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
      visits = const [];
      pending = 0;
      notifyListeners();
      return;
    }

    if (loadedTenantId != tenantId) {
      loadedTenantId = tenantId;
      visits = const [];
    }

    visits = await repository.list(tenantId);
    pending = await repository.pendingCount(tenantId);
    notifyListeners();
  }

  Future<void> checkIn(Map<String, dynamic> customer) async {
    final tenantId = appState.session?.tenantId;
    if (tenantId == null || busy) return;

    busy = true;
    message = null;
    notifyListeners();

    try {
      final position = await _position();

      await repository.checkInLocal(
        tenantId: tenantId,
        customer: customer,
        at: DateTime.now().toUtc(),
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
      );

      await reloadLocal();
      message = 'Visit check-in saved locally.';
      await sync(silent: true);
    } catch (error) {
      message = error.toString();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> checkOut(
    Map<String, dynamic> visit, {
    required String outcome,
    String? notes,
  }) async {
    final tenantId = appState.session?.tenantId;
    if (tenantId == null || busy) return;

    busy = true;
    message = null;
    notifyListeners();

    try {
      final position = await _position();

      await repository.checkOutLocal(
        tenantId: tenantId,
        visit: visit,
        at: DateTime.now().toUtc(),
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        outcome: outcome,
        notes: notes,
      );

      await reloadLocal();
      message = 'Visit check-out saved locally.';
      await sync(silent: true);
    } catch (error) {
      message = error.toString();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> capturePhoto(Map<String, dynamic> visit) async {
    final tenantId = appState.session?.tenantId;
    if (tenantId == null || busy) return;

    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 82,
      maxWidth: 1920,
    );
    if (picked == null) return;

    busy = true;
    message = null;
    notifyListeners();

    try {
      final documents = await getApplicationDocumentsDirectory();
      final folder = Directory(p.join(documents.path, 'visit_photos'));
      await folder.create(recursive: true);

      final extension = p.extension(picked.path).isEmpty
          ? '.jpg'
          : p.extension(picked.path);
      final filename =
          DateTime.now().microsecondsSinceEpoch.toString() + extension;
      final saved = await File(picked.path).copy(p.join(folder.path, filename));

      Position? position;
      try {
        position = await _position();
      } catch (_) {
        position = null;
      }

      await repository.addPhotoLocal(
        tenantId: tenantId,
        visitOfflineUuid: visit['offline_uuid'].toString(),
        localPath: saved.path,
        capturedAt: DateTime.now().toUtc(),
        latitude: position?.latitude,
        longitude: position?.longitude,
        accuracy: position?.accuracy,
      );

      await reloadLocal();
      message = 'Photo saved locally.';
      await sync(silent: true);
    } catch (error) {
      message = error.toString();
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
      await reloadLocal();

      if (!silent) {
        message = result.failed == 0
            ? 'Visit sync complete. ${result.synced} visits processed.'
            : 'Visit sync completed with ${result.failed} pending failures.';
      }
    } catch (_) {
      await reloadLocal();
      if (!silent) {
        message = 'Offline mode: visit changes remain stored locally.';
      }
    } finally {
      if (!silent) {
        busy = false;
        notifyListeners();
      }
    }
  }

  bool get hasActiveVisit => visits.any((row) => row['status'] == 'active');

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
      throw StateError('Location permission is required for customer visits.');
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }
}
