import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timezone/data/latest_10y.dart' as tz;

import 'app.dart';
import 'core/api/api_client.dart';
import 'core/db/app_database.dart';
import 'core/db/local_first_transaction.dart';
import 'core/storage/secret_store.dart';
import 'features/attendance/attendance_repository.dart';
import 'features/auth/auth_repository.dart';
import 'features/customers/customer_repository.dart';
import 'features/gps/gps_repository.dart';
import 'features/gps/tracking_service.dart';
import 'features/master_data/master_data_repository.dart';
import 'features/master_data/master_data_source.dart';
import 'features/settings/settings_repository.dart';
import 'state/app_state.dart';
import 'state/attendance_controller.dart';
import 'state/master_data_controller.dart';

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

  final masterSource = ApiMasterDataSource(api);
  final masterData = MasterDataRepository(
    database: db,
    source: masterSource,
  );
  final localTransactions = LocalFirstTransaction(db);
  final customers = CustomerRepository(
    database: db,
    transactions: localTransactions,
    masterData: masterData,
    source: masterSource,
  );

  final appState = AppState(auth: auth, settings: settings);
  api.onAuthRevoked = appState.revokeLocal;

  final masterDataController = MasterDataController(
    appState: appState,
    masterData: masterData,
    customersRepository: customers,
  );

  final attendanceController = AttendanceController(
    appState: appState,
    attendance: attendance,
    gps: gps,
    tracking: tracking,
    settings: settings,
    db: db,
  );

  await appState.restore();
  await attendanceController.restore();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appState),
        ChangeNotifierProvider.value(value: attendanceController),
        ChangeNotifierProvider.value(value: masterDataController),
        Provider.value(value: masterData),
        Provider.value(value: customers),
      ],
      child: const FieldSalesApp(),
    ),
  );
}
