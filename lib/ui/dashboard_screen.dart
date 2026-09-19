import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/attendance_controller.dart';
import '../state/master_data_controller.dart';
import '../state/visit_controller.dart';
import 'customers_screen.dart';
import 'home_tab.dart';
import 'products_screen.dart';
import 'routes_screen.dart';
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
    RoutesScreen(),
    ProductsScreen(),
    SyncScreen(),
  ];

  static const _titles = [
    'Field Sales',
    'Customers',
    'Visits',
    'Routes',
    'Products',
    'Sync',
  ];

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<MasterDataController>().initialize();
        context.read<VisitController>().initialize();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final master = context.watch<MasterDataController>();
    final visits = context.watch<VisitController>();
    final pending = master.pending + visits.pending;

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
                  tooltip: 'Pending sync',
                  onPressed: () => setState(() => _index = 5),
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
        onDestinationSelected: (value) => setState(() => _index = value),
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
            icon: Icon(Icons.route_outlined),
            selectedIcon: Icon(Icons.route),
            label: 'Routes',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Products',
          ),
          NavigationDestination(
            icon: Icon(Icons.sync_outlined),
            selectedIcon: Icon(Icons.sync),
            label: 'Sync',
          ),
        ],
      ),
    );
  }
}
