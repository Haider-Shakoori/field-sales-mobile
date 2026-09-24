import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timezone/data/latest_10y.dart' as tz;

import 'app.dart';
import 'core/api/api_client.dart';
import 'core/config.dart';
import 'core/db/app_database.dart';
import 'core/db/local_first_transaction.dart';
import 'core/storage/secret_store.dart';
import 'core/sync/connectivity_gate.dart';
import 'core/sync/sync_coordinator.dart';
import 'core/sync/sync_retry_store.dart';
import 'features/appointments/appointment_repository.dart';
import 'features/attendance/attendance_repository.dart';
import 'features/auth/auth_repository.dart';
import 'features/customers/customer_repository.dart';
import 'features/calls/call_activity_repository.dart';
import 'features/collections/collection_repository.dart';
import 'features/expenses/expense_repository.dart';
import 'features/financial_documents/customer_statement_repository.dart';
import 'features/gps/gps_repository.dart';
import 'features/gps/tracking_service.dart';
import 'features/maps/offline_map_cache.dart';
import 'features/mileage/mileage_repository.dart';
import 'features/master_data/master_data_repository.dart';
import 'features/master_data/master_data_source.dart';
import 'features/orders/order_repository.dart';
import 'features/routes/daily_route_plan_repository.dart';
import 'features/settings/settings_repository.dart';
import 'features/stock/stock_repository.dart';
import 'features/targets/target_repository.dart';
import 'features/visits/visit_repository.dart';
import 'state/app_state.dart';
import 'state/appointment_controller.dart';
import 'state/call_activity_controller.dart';
import 'state/collection_controller.dart';
import 'state/expense_controller.dart';
import 'state/attendance_controller.dart';
import 'state/master_data_controller.dart';
import 'state/order_controller.dart';
import 'state/sync_controller.dart';
import 'state/target_controller.dart';
import 'state/visit_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.validateForStartup();
  tz.initializeTimeZones();
  await OfflineMapCache.initialize();

  final db = AppDatabase();
  await db.open();

  final secrets = SecretStore();
  final api = ApiClient(secrets);
  final auth = AuthRepository(api: api, secrets: secrets);
  final settings = SettingsRepository(api: api, db: db);
  final appointments = AppointmentRepository(api: api, db: db);
  final attendance = AttendanceRepository(api: api, db: db);
  final gps = GpsRepository(api: api, db: db);
  final tracking = TrackingService(db: db, gpsRepository: gps);
  final visits = VisitRepository(api: api, db: db);
  final calls = CallActivityRepository(api: api, db: db);
  final collections = CollectionRepository(api: api, db: db);
  final expenses = ExpenseRepository(api: api, db: db);
  final targets = TargetRepository(api: api, db: db);
  final smartRoute = DailyRoutePlanRepository(api: api, db: db);
  final stock = StockRepository(api: api, db: db);
  final statements = CustomerStatementRepository(api: api, db: db);
  final mileage = MileageRepository(api: api, db: db);

  final masterSource = ApiMasterDataSource(api);
  final masterData = MasterDataRepository(database: db, source: masterSource);
  final orders = OrderRepository(
    api: api,
    db: db,
    masterData: masterData,
    stock: stock,
  );
  final localTransactions = LocalFirstTransaction(db);
  final retryStore = SyncRetryStore(db);
  final customers = CustomerRepository(
    database: db,
    transactions: localTransactions,
    masterData: masterData,
    source: masterSource,
  );

  final appState = AppState(auth: auth, settings: settings);
  api.onAuthRevoked = appState.revokeLocal;

  final syncCoordinator = SyncCoordinator(
    db: db,
    retryStore: retryStore,
    customers: customers,
    masterData: masterData,
    appointments: appointments,
    attendance: attendance,
    gps: gps,
    visits: visits,
    calls: calls,
    orders: orders,
    stock: stock,
    collections: collections,
    expenses: expenses,
    targets: targets,
  );

  final masterDataController = MasterDataController(
    appState: appState,
    masterData: masterData,
    customersRepository: customers,
  );

  final appointmentController = AppointmentController(
    appState: appState,
    repository: appointments,
  );

  final callActivityController = CallActivityController(
    appState: appState,
    repository: calls,
  );

  final collectionController = CollectionController(
    appState: appState,
    repository: collections,
  );

  final expenseController = ExpenseController(
    appState: appState,
    repository: expenses,
  );

  final targetController = TargetController(
    appState: appState,
    repository: targets,
  );

  final orderController = OrderController(
    appState: appState,
    repository: orders,
  );

  final visitController = VisitController(
    appState: appState,
    repository: visits,
  );

  final attendanceController = AttendanceController(
    appState: appState,
    attendance: attendance,
    gps: gps,
    tracking: tracking,
    settings: settings,
    db: db,
  );

  final syncController = SyncController(
    appState: appState,
    db: db,
    coordinator: syncCoordinator,
    retryStore: retryStore,
  );

  await appState.restore();
  await attendanceController.restore();
  await syncController.initialize();

  var wasOnline = true;
  ConnectivityGate.instance.statusChanges.listen((online) {
    if (online && !wasOnline) {
      unawaited(syncController.run(triggerSource: 'connectivity'));
    }
    wasOnline = online;
  });

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appState),
        ChangeNotifierProvider.value(value: attendanceController),
        ChangeNotifierProvider.value(value: appointmentController),
        ChangeNotifierProvider.value(value: masterDataController),
        ChangeNotifierProvider.value(value: visitController),
        ChangeNotifierProvider.value(value: callActivityController),
        ChangeNotifierProvider.value(value: orderController),
        ChangeNotifierProvider.value(value: collectionController),
        ChangeNotifierProvider.value(value: expenseController),
        ChangeNotifierProvider.value(value: targetController),
        ChangeNotifierProvider.value(value: syncController),
        Provider.value(value: masterData),
        Provider.value(value: appointments),
        Provider.value(value: customers),
        Provider.value(value: visits),
        Provider.value(value: calls),
        Provider.value(value: orders),
        Provider.value(value: smartRoute),
        Provider.value(value: stock),
        Provider.value(value: statements),
        Provider.value(value: collections),
        Provider.value(value: expenses),
        Provider.value(value: targets),
        Provider.value(value: mileage),
        Provider.value(value: retryStore),
        Provider.value(value: syncCoordinator),
      ],
      child: const FieldSalesApp(),
    ),
  );
}
