import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/appointment_controller.dart';
import '../state/attendance_controller.dart';
import '../state/call_activity_controller.dart';
import '../state/collection_controller.dart';
import '../state/expense_controller.dart';
import '../state/master_data_controller.dart';
import '../state/lead_controller.dart';
import '../state/order_controller.dart';
import '../state/sync_controller.dart';
import '../state/target_controller.dart';
import '../state/visit_controller.dart';
import 'customers_screen.dart';
import 'home_tab.dart';
import 'more_screen.dart';
import 'orders_screen.dart';
import 'sync_refresh.dart';
import 'sync_screen.dart';
import 'visits_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_initializeData());
      }
    });
  }

  Future<void> _initializeData() async {
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
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          if (pending > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Badge(
                label: Text('$pending'),
                child: IconButton(
                  tooltip: sync.blockedCount > 0
                      ? 'Sync issues need attention'
                      : 'Pending sync',
                  onPressed: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => const SyncScreen())),
                  icon: const Icon(Icons.cloud_upload_outlined),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => context.read<AttendanceController>().logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) {
          setState(() => _index = value);
          unawaited(syncAndReload(context, triggerSource: 'tab'));
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront),
            label: 'Customers',
          ),
          NavigationDestination(
            icon: Icon(Icons.location_on_outlined),
            selectedIcon: Icon(Icons.location_on),
            label: 'Visits',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Orders',
          ),
          NavigationDestination(
            icon: Icon(Icons.more_horiz),
            selectedIcon: Icon(Icons.more),
            label: 'More',
          ),
        ],
      ),
    );
  }
}