import 'package:field_sales_mobile/core/api/api_client.dart';
import 'package:field_sales_mobile/l10n/locale_controller.dart';
import 'package:field_sales_mobile/core/db/app_database.dart';
import 'package:field_sales_mobile/core/db/local_first_transaction.dart';
import 'package:field_sales_mobile/core/storage/secret_store.dart';
import 'package:field_sales_mobile/core/sync/sync_coordinator.dart';
import 'package:field_sales_mobile/core/sync/sync_retry_store.dart';
import 'package:field_sales_mobile/features/appointments/appointment_repository.dart';
import 'package:field_sales_mobile/features/attendance/attendance_repository.dart';
import 'package:field_sales_mobile/features/auth/auth_repository.dart';
import 'package:field_sales_mobile/features/calls/call_activity_repository.dart';
import 'package:field_sales_mobile/features/collections/collection_repository.dart';
import 'package:field_sales_mobile/features/customers/customer_repository.dart';
import 'package:field_sales_mobile/features/expenses/expense_repository.dart';
import 'package:field_sales_mobile/features/financial_documents/customer_statement_repository.dart';
import 'package:field_sales_mobile/features/followups/follow_up_repository.dart';
import 'package:field_sales_mobile/features/gamification/gamification_repository.dart';
import 'package:field_sales_mobile/features/gps/gps_repository.dart';
import 'package:field_sales_mobile/features/gps/tracking_service.dart';
import 'package:field_sales_mobile/features/leads/lead_repository.dart';
import 'package:field_sales_mobile/features/master_data/master_data_repository.dart';
import 'package:field_sales_mobile/features/master_data/master_data_source.dart';
import 'package:field_sales_mobile/features/mileage/mileage_repository.dart';
import 'package:field_sales_mobile/features/notifications/notification_repository.dart';
import 'package:field_sales_mobile/features/orders/order_repository.dart';
import 'package:field_sales_mobile/features/routes/daily_route_plan_repository.dart';
import 'package:field_sales_mobile/features/settings/attendance_tracking_settings.dart';
import 'package:field_sales_mobile/features/settings/settings_repository.dart';
import 'package:field_sales_mobile/features/stock/stock_repository.dart';
import 'package:field_sales_mobile/features/targets/target_repository.dart';
import 'package:field_sales_mobile/features/team/team_repository.dart';
import 'package:field_sales_mobile/features/visits/visit_repository.dart';
import 'package:field_sales_mobile/state/app_state.dart';
import 'package:field_sales_mobile/state/appointment_controller.dart';
import 'package:field_sales_mobile/state/attendance_controller.dart';
import 'package:field_sales_mobile/state/call_activity_controller.dart';
import 'package:field_sales_mobile/state/collection_controller.dart';
import 'package:field_sales_mobile/state/expense_controller.dart';
import 'package:field_sales_mobile/state/follow_up_controller.dart';
import 'package:field_sales_mobile/state/lead_controller.dart';
import 'package:field_sales_mobile/state/master_data_controller.dart';
import 'package:field_sales_mobile/state/notification_controller.dart';
import 'package:field_sales_mobile/state/order_controller.dart';
import 'package:field_sales_mobile/state/sync_controller.dart';
import 'package:field_sales_mobile/state/target_controller.dart';
import 'package:field_sales_mobile/state/team_controller.dart';
import 'package:field_sales_mobile/state/visit_controller.dart';
import 'package:field_sales_mobile/ui/customer_create_screen.dart';
import 'package:field_sales_mobile/ui/customers_screen.dart';
import 'package:field_sales_mobile/ui/home_tab.dart';
import 'package:field_sales_mobile/ui/leadership_dashboard_screen.dart';
import 'package:field_sales_mobile/ui/leads_screen.dart';
import 'package:field_sales_mobile/ui/more_screen.dart';
import 'package:field_sales_mobile/ui/orders_screen.dart';
import 'package:field_sales_mobile/ui/visits_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeApiClient extends ApiClient {
  FakeApiClient() : super(SecretStore());

  @override
  Future<dynamic> get(String p, {Map<String, dynamic>? query}) async {
    switch (p) {
      case 'team/overview':
        return <String, dynamic>{
          'summary': <String, dynamic>{},
          'locations': <dynamic>[],
          'hierarchy': <dynamic>[],
          'recent_activity': <dynamic>[],
        };
      case 'notifications':
        return <dynamic>[];
      case 'gamification':
        return <String, dynamic>{'enabled': false};
      case 'mileage/history':
        return <dynamic>[];
      case 'stock/me':
        return <String, dynamic>{'enabled': false, 'stock': <dynamic>[]};
      case 'returns/history':
        return <String, dynamic>{'returns': <dynamic>[]};
      default:
        return <String, dynamic>{};
    }
  }

  @override
  Future<ApiEnvelope> getEnvelope(
    String p, {
    Map<String, dynamic>? query,
  }) async {
    if (p == 'referrals/me') {
      return const ApiEnvelope(
        data: <String, dynamic>{
          'salesman': <String, dynamic>{},
          'summary': <String, dynamic>{},
          'customers': <dynamic>[],
        },
        meta: <String, dynamic>{
          'pagination': <String, dynamic>{'current_page': 1, 'last_page': 1},
        },
      );
    }

    return const ApiEnvelope(data: <dynamic>[], meta: <String, dynamic>{});
  }

  @override
  Future<dynamic> post(
    String p, {
    Object? data,
    Map<String, String>? headers,
  }) async => <String, dynamic>{};

  @override
  Future<dynamic> patch(
    String p, {
    Object? data,
    Map<String, String>? headers,
  }) async => <String, dynamic>{};

  @override
  Future<dynamic> put(
    String p, {
    Object? data,
    Map<String, String>? headers,
  }) async => <String, dynamic>{};
}

late AppDatabase db;
late FakeApiClient api;
late AppState appState;
late AppLocaleController localeController;
late MasterDataRepository masterData;
late AppointmentRepository appointments;
late AttendanceRepository attendance;
late GpsRepository gps;
late TrackingService tracking;
late VisitRepository visits;
late CallActivityRepository calls;
late CollectionRepository collections;
late ExpenseRepository expenses;
late FollowUpRepository followUps;
late TargetRepository targets;
late TeamRepository team;
late DailyRoutePlanRepository smartRoute;
late StockRepository stock;
late CustomerStatementRepository statements;
late MileageRepository mileage;
late LeadRepository leads;
late NotificationRepository notifications;
late GamificationRepository gamification;
late OrderRepository orders;
late CustomerRepository customers;
late SyncRetryStore retryStore;
late SyncCoordinator syncCoordinator;
late MasterDataController masterDataController;
late AppointmentController appointmentController;
late AttendanceController attendanceController;
late CallActivityController callController;
late CollectionController collectionController;
late ExpenseController expenseController;
late FollowUpController followUpController;
late LeadController leadController;
late NotificationController notificationController;
late OrderController orderController;
late SyncController syncController;
late TargetController targetController;
late TeamController teamController;
late VisitController visitController;

void useRole(String role) {
  appState
    ..session = AuthSession(
      userId: 'smoke-user',
      tenantId: 'smoke-tenant',
      deviceId: 'smoke-device',
      name: 'Smoke User',
      role: role,
      permissions: const <String>[],
    )
    ..restored = true
    ..policy = AttendanceTrackingSettings.defaults(tenantId: 'smoke-tenant')
    ..gamificationEnabled = true;
}

Widget wrap(Widget child) => MultiProvider(
  providers: [
    ChangeNotifierProvider.value(value: appState),
    ChangeNotifierProvider.value(value: localeController),
    ChangeNotifierProvider.value(value: attendanceController),
    ChangeNotifierProvider.value(value: appointmentController),
    ChangeNotifierProvider.value(value: leadController),
    ChangeNotifierProvider.value(value: masterDataController),
    ChangeNotifierProvider.value(value: visitController),
    ChangeNotifierProvider.value(value: callController),
    ChangeNotifierProvider.value(value: orderController),
    ChangeNotifierProvider.value(value: collectionController),
    ChangeNotifierProvider.value(value: expenseController),
    ChangeNotifierProvider.value(value: followUpController),
    ChangeNotifierProvider.value(value: targetController),
    ChangeNotifierProvider.value(value: teamController),
    ChangeNotifierProvider.value(value: syncController),
    ChangeNotifierProvider.value(value: notificationController),
    Provider.value(value: masterData),
    Provider.value(value: appointments),
    Provider.value(value: leads),
    Provider.value(value: customers),
    Provider.value(value: visits),
    Provider.value(value: calls),
    Provider.value(value: orders),
    Provider.value(value: smartRoute),
    Provider.value(value: stock),
    Provider.value(value: statements),
    Provider.value(value: collections),
    Provider.value(value: expenses),
    Provider.value(value: followUps),
    Provider.value(value: targets),
    Provider.value(value: team),
    Provider.value(value: mileage),
    Provider.value(value: gamification),
    Provider.value(value: retryStore),
    Provider.value(value: syncCoordinator),
  ],
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true),
    home: child,
  ),
);
Future<void> setUpHarness() async {
  await deleteDatabase('${await getDatabasesPath()}/field_sales.db');
  db = AppDatabase();
  await db.open();
  api = FakeApiClient();

  final settings = SettingsRepository(api: api, db: db);
  final auth = AuthRepository(api: api, secrets: SecretStore());
  appState = AppState(auth: auth, settings: settings);
  localeController = AppLocaleController();

  appointments = AppointmentRepository(api: api, db: db);
  attendance = AttendanceRepository(api: api, db: db);
  gps = GpsRepository(api: api, db: db);
  tracking = TrackingService(db: db, gpsRepository: gps);
  visits = VisitRepository(api: api, db: db);
  calls = CallActivityRepository(api: api, db: db);
  collections = CollectionRepository(api: api, db: db);
  expenses = ExpenseRepository(api: api, db: db);
  followUps = FollowUpRepository(api: api, db: db);
  targets = TargetRepository(api: api, db: db);
  team = TeamRepository(api);
  smartRoute = DailyRoutePlanRepository(api: api, db: db);
  stock = StockRepository(api: api, db: db);
  statements = CustomerStatementRepository(api: api, db: db);
  mileage = MileageRepository(api: api, db: db);
  leads = LeadRepository(api: api, db: db);
  notifications = NotificationRepository(api);
  gamification = GamificationRepository(api);

  final source = ApiMasterDataSource(api);
  masterData = MasterDataRepository(database: db, source: source);
  orders = OrderRepository(
    api: api,
    db: db,
    masterData: masterData,
    stock: stock,
  );
  customers = CustomerRepository(
    database: db,
    transactions: LocalFirstTransaction(db),
    masterData: masterData,
    source: source,
  );
  retryStore = SyncRetryStore(db);
  syncCoordinator = SyncCoordinator(
    db: db,
    retryStore: retryStore,
    customers: customers,
    masterData: masterData,
    leads: leads,
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
    followUps: followUps,
  );

  masterDataController = MasterDataController(
    appState: appState,
    masterData: masterData,
    customersRepository: customers,
  );
  appointmentController = AppointmentController(
    appState: appState,
    repository: appointments,
  );
  leadController = LeadController(appState: appState, repository: leads);
  callController = CallActivityController(
    appState: appState,
    repository: calls,
  );
  collectionController = CollectionController(
    appState: appState,
    repository: collections,
  );
  expenseController = ExpenseController(
    appState: appState,
    repository: expenses,
  );
  followUpController = FollowUpController(
    appState: appState,
    repository: followUps,
  );
  targetController = TargetController(appState: appState, repository: targets);
  teamController = TeamController(appState: appState, repository: team);
  orderController = OrderController(appState: appState, repository: orders);
  visitController = VisitController(appState: appState, repository: visits);
  attendanceController = AttendanceController(
    appState: appState,
    attendance: attendance,
    gps: gps,
    tracking: tracking,
    settings: settings,
    db: db,
  );
  notificationController = NotificationController(
    appState: appState,
    repository: notifications,
  );
  syncController = SyncController(
    appState: appState,
    db: db,
    coordinator: syncCoordinator,
    retryStore: retryStore,
  );
}

Future<void> tearDownHarness() async {
  notificationController.dispose();
  attendanceController.dispose();
  appointmentController.dispose();
  leadController.dispose();
  masterDataController.dispose();
  visitController.dispose();
  callController.dispose();
  orderController.dispose();
  collectionController.dispose();
  expenseController.dispose();
  followUpController.dispose();
  targetController.dispose();
  teamController.dispose();
  syncController.dispose();
  localeController.dispose();
  appState.dispose();
  await db.db.close();
  await deleteDatabase('${await getDatabasesPath()}/field_sales.db');
}

Future<void> settle(WidgetTester tester, {String? reason}) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 750));
  expect(tester.takeException(), isNull, reason: reason);
}

void configurePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(setUpHarness);
  tearDown(tearDownHarness);

  testWidgets('salesman primary screens render at phone size', (tester) async {
    configurePhoneViewport(tester);
    useRole('salesman');

    final screens = <String, Widget>{
      'Home': const HomeTab(),
      'Customers': const CustomersScreen(),
      'Visits': const VisitsScreen(),
      'Orders': const OrdersScreen(),
      'More': const MoreScreen(),
    };

    for (final entry in screens.entries) {
      await tester.pumpWidget(wrap(Scaffold(body: entry.value)));
      await settle(tester, reason: 'Primary screen overflow: ${entry.key}');
    }
  });
  testWidgets('salesman More menu opens every destination', (tester) async {
    configurePhoneViewport(tester);
    useRole('salesman');

    const labels = <String>[
      'My Account',
      'Notifications',
      'Recognition',
      'Leads & Pipeline',
      'Calendar',
      'Follow-ups',
      'Collections',
      'Expenses',
      'Fuel Management',
      'Mileage',
      'Targets',
      'Smart Route',
      'Routes',
      'Stock & Returns',
      'Products',
      'Sync',
    ];

    for (final label in labels) {
      await tester.pumpWidget(
        KeyedSubtree(
          key: ValueKey<String>('more-$label'),
          child: wrap(const Scaffold(body: MoreScreen())),
        ),
      );
      await settle(tester);

      final target = find.text(label);
      for (
        var attempt = 0;
        attempt < 12 && target.evaluate().isEmpty;
        attempt++
      ) {
        final list = find.byType(ListView);
        expect(
          list,
          findsWidgets,
          reason: 'More list missing while finding $label',
        );
        await tester.drag(list.first, const Offset(0, -220));
        await tester.pump(const Duration(milliseconds: 120));
      }
      expect(target, findsWidgets, reason: 'Missing More destination: $label');
      await tester.ensureVisible(target.first);
      await tester.pump(const Duration(milliseconds: 120));
      await tester.tap(target.first);
      await settle(tester);

      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text(label)),
        findsOneWidget,
        reason: 'Destination did not open cleanly: $label',
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('customer action row including follow-ups fits phone width', (
    tester,
  ) async {
    configurePhoneViewport(tester);
    useRole('salesman');

    await masterData.cacheServerRow(
      table: 'customers',
      tenantId: 'smoke-tenant',
      row: const {
        'id': 'customer-smoke-1',
        'code': 'CUS-SMOKE',
        'name': 'Smoke Customer',
        'phone': '0700000000',
        'address': 'Kabul',
        'is_active': true,
      },
    );
    await masterDataController.reloadLocal();

    await tester.pumpWidget(wrap(const Scaffold(body: CustomersScreen())));
    await settle(
      tester,
      reason: 'Customer quick actions overflowed the phone viewport',
    );

    expect(find.byTooltip('Follow-ups'), findsOneWidget);
    expect(find.byTooltip('Call history'), findsOneWidget);
    expect(find.byTooltip('Statement'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('customer form exposes web-parity fields', (tester) async {
    configurePhoneViewport(tester);
    useRole('salesman');

    await tester.pumpWidget(wrap(const CustomerCreateScreen()));
    await settle(tester, reason: 'Customer parity form failed to render');

    for (final label in const [
      'Contact person',
      'Phone',
      'Alternate phone',
      'Email',
      'Address',
      'Price list',
      'Geofence radius (meters)',
    ]) {
      expect(
        find.text(label),
        findsOneWidget,
        reason: 'Missing customer field: $label',
      );
    }
  });

  testWidgets('lead create sheet exposes web-parity fields', (tester) async {
    configurePhoneViewport(tester);
    useRole('salesman');

    await tester.pumpWidget(wrap(const LeadsScreen()));
    await settle(tester);
    await tester.tap(find.text('New lead'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.takeException(), isNull);

    for (final label in const [
      'Business or prospect name',
      'Contact person',
      'Phone',
      'Email',
      'Address',
      'Source',
      'Priority',
      'Estimated value',
      'Currency',
      'Expected close date',
      'Notes',
    ]) {
      expect(
        find.text(label),
        findsOneWidget,
        reason: 'Missing lead field: $label',
      );
    }
  });

  testWidgets('supervisor leadership dashboard renders', (tester) async {
    configurePhoneViewport(tester);
    useRole('supervisor');

    await tester.pumpWidget(wrap(const LeadershipDashboardScreen()));
    await settle(tester);

    expect(find.text('Supervisor · FieldPulse'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sales manager leadership dashboard renders', (tester) async {
    configurePhoneViewport(tester);
    useRole('sales_manager');

    await tester.pumpWidget(wrap(const LeadershipDashboardScreen()));
    await settle(tester);

    expect(find.text('Sales Manager · FieldPulse'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
