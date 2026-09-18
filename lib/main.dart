import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timezone/data/latest_10y.dart' as tz;
import 'app.dart';
import 'core/api/api_client.dart';
import 'core/db/app_database.dart';
import 'core/storage/secret_store.dart';
import 'features/auth/auth_repository.dart';
import 'features/settings/settings_repository.dart';
import 'features/attendance/attendance_repository.dart';
import 'features/gps/gps_repository.dart';
import 'features/gps/tracking_service.dart';
import 'state/app_state.dart';
import 'state/attendance_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  final db = AppDatabase();
  await db.open();
  final secrets = SecretStore();
  final api = ApiClient(secrets);
  final auth = AuthRepository(api: api, secrets: secrets);
  final settings = SettingsRepository(api: api, db: db);
  final attendance = AttendanceRepository(api: api, db: db);
  final gps = GpsRepository(api: api, db: db);
  final tracking = TrackingService(db: db, gpsRepository: gps);
  final appState = AppState(auth: auth, settings: settings);
  final controller = AttendanceController(appState: appState, attendance: attendance, gps: gps, tracking: tracking, settings: settings, db: db);
  await appState.restore();
  await controller.restore();
  runApp(MultiProvider(providers: [
    ChangeNotifierProvider.value(value: appState),
    ChangeNotifierProvider.value(value: controller),
  ], child: const FieldSalesApp()));
}
