import 'dart:async';

import '../l10n/l10n.dart';

import 'package:field_sales_mobile/l10n/localized_material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../state/appointment_controller.dart';
import '../state/attendance_controller.dart';
import '../state/call_activity_controller.dart';
import '../state/collection_controller.dart';
import '../state/expense_controller.dart';
import '../state/master_data_controller.dart';
import '../state/lead_controller.dart';
import '../state/order_controller.dart';
import '../state/notification_controller.dart';
import '../state/sync_controller.dart';
import '../state/target_controller.dart';
import '../state/team_controller.dart';
import '../state/visit_controller.dart';
import 'customers_screen.dart';
import 'fieldpulse_theme.dart';
import 'home_tab.dart';
import 'leadership_dashboard_screen.dart';
import 'more_screen.dart';
import 'orders_screen.dart';
import 'notifications_screen.dart';
import 'sync_refresh.dart';
import 'sync_screen.dart';
import 'visits_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  var _index = 0;

  static const _pages = [
    HomeTab(),
    CustomersScreen(),
    VisitsScreen(),
    OrdersScreen(),
    MoreScreen(),
  ];

  static const _titles = [
    'Field Sales',
    'Customers',
    'Visits',
    'Orders',
    'More',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_initializeData());
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshPresenceOnResume());
    }
  }

  Future<void> _refreshPresenceOnResume() async {
    if (!mounted) return;

    final app = context.read<AppState>();
    if (app.isSalesman) {
      await context.read<AttendanceController>().refreshLivePresence();
      if (!mounted) return;
      await context.read<SyncController>().run(triggerSource: 'resume');
    } else {
      await app.heartbeatNow();
    }
  }

  Future<void> _initializeData() async {
    if (context.read<AppState>().isLeadership) {
      await context.read<TeamController>().refresh(silent: true);
      return;
    }

    await Future.wait([
      context.read<MasterDataController>().reloadLocal(),
      context.read<LeadController>().reloadLocal(),
      context.read<AppointmentController>().reloadLocal(),
      context.read<VisitController>().reloadLocal(),
      context.read<CallActivityController>().reloadLocal(),
      context.read<OrderController>().reloadLocal(),
      context.read<CollectionController>().reloadLocal(),
      context.read<ExpenseController>().reloadLocal(),
      context.read<TargetController>().reloadLocal(),
    ]);

    if (!mounted) return;

    await context.read<AttendanceController>().refreshLivePresence();

    if (!mounted) return;

    await context.read<SyncController>().run(triggerSource: 'startup');

    if (!mounted) return;

    await Future.wait([
      context.read<MasterDataController>().reloadLocal(),
      context.read<LeadController>().reloadLocal(),
      context.read<AppointmentController>().reloadLocal(),
      context.read<VisitController>().reloadLocal(),
      context.read<CallActivityController>().reloadLocal(),
      context.read<OrderController>().reloadLocal(),
      context.read<CollectionController>().reloadLocal(),
      context.read<ExpenseController>().reloadLocal(),
      context.read<TargetController>().reloadLocal(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (context.watch<AppState>().isLeadership) {
      return const LeadershipDashboardScreen();
    }

    final master = context.watch<MasterDataController>();
    final appointments = context.watch<AppointmentController>();
    final leads = context.watch<LeadController>();
    final visits = context.watch<VisitController>();
    final calls = context.watch<CallActivityController>();
    final orders = context.watch<OrderController>();
    final collections = context.watch<CollectionController>();
    final expenses = context.watch<ExpenseController>();
    final sync = context.watch<SyncController>();
    final pending =
        master.pending +
        leads.pending +
        appointments.pending +
        visits.pending +
        calls.pending +
        orders.pending +
        collections.pending +
        expenses.pending +
        sync.infrastructurePending;

    return Scaffold(
      extendBody: false,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                gradient: FieldPulseDecor.accentGradient,
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(
                Icons.route_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 11),
            Text(_titles[_index]),
          ],
        ),
        actions: [
          Consumer<NotificationController>(
            builder: (context, notifications, _) => IconButton(
              tooltip: L10n.text('Notifications'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: const Text('Notifications')),
                    body: const NotificationsScreen(),
                  ),
                ),
              ),
              icon: Badge(
                isLabelVisible: notifications.unreadCount > 0,
                label: Text('${notifications.unreadCount}'),
                child: const Icon(Icons.notifications_outlined),
              ),
            ),
          ),
          if (pending > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Badge(
                label: Text('$pending'),
                child: IconButton(
                  tooltip: sync.blockedCount > 0
                      ? L10n.text('Sync issues need attention')
                      : L10n.text('Pending sync'),
                  onPressed: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => const SyncScreen())),
                  icon: const Icon(Icons.cloud_upload_outlined),
                ),
              ),
            ),
          IconButton(
            tooltip: L10n.text('Sign out'),
            onPressed: () => context.read<AttendanceController>().logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: FieldPulseTheme.border),
            boxShadow: FieldPulseDecor.softShadow,
          ),
          child: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (value) {
              setState(() => _index = value);
              unawaited(syncAndReload(context, triggerSource: 'tab'));
            },
            destinations: [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: L10n.text('Home'),
              ),
              NavigationDestination(
                icon: Icon(Icons.storefront_outlined),
                selectedIcon: Icon(Icons.storefront),
                label: L10n.text('Customers'),
              ),
              NavigationDestination(
                icon: Icon(Icons.location_on_outlined),
                selectedIcon: Icon(Icons.location_on),
                label: L10n.text('Visits'),
              ),
              NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long),
                label: L10n.text('Orders'),
              ),
              NavigationDestination(
                icon: Icon(Icons.more_horiz),
                selectedIcon: Icon(Icons.more),
                label: L10n.text('More'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
