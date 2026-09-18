import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/sync/sync_controller.dart';
import '../../l10n/app_l10n.dart';
import '../../state/app_state.dart';
import '../../state/master_data_controller.dart';
import '../attendance/attendance_card.dart';
import '../attendance/attendance_controller.dart';
import 'master_data_screens.dart';
import 'sync_status_indicator.dart';

/// Authenticated shell: bottom navigation across Dashboard, Routes, Customers,
/// Products and Profile, with the sync status bar. Shell screens read the
/// SQLite master-data cache (see [CustomersScreen], [RoutesScreen],
/// [ProductsScreen]); the Dashboard offers quick navigation.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MasterDataController>().refresh();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      // Automatic attendance re-evaluates when the app returns to foreground.
      context.read<AttendanceController>().onAppResumed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _DashboardScreen(onOpenTab: (i) => setState(() => _index = i)),
      const RoutesScreen(),
      const CustomersScreen(),
      const ProductsScreen(),
      const _ProfileScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SyncStatusIndicator(),
          NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.dashboard_outlined),
                selectedIcon: const Icon(Icons.dashboard),
                label: _tabLabel(context, 0),
              ),
              NavigationDestination(
                icon: const Icon(Icons.alt_route),
                label: _tabLabel(context, 1),
              ),
              NavigationDestination(
                icon: const Icon(Icons.people_outline),
                label: _tabLabel(context, 2),
              ),
              NavigationDestination(
                icon: const Icon(Icons.inventory_2_outlined),
                label: _tabLabel(context, 3),
              ),
              NavigationDestination(
                icon: const Icon(Icons.person_outline),
                label: _tabLabel(context, 4),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _tabLabel(BuildContext context, int index) {
    final l10n = AppL10n.of(context);
    return switch (index) {
      0 => l10n.dashboard,
      1 => l10n.routes,
      2 => l10n.customers,
      3 => l10n.products,
      _ => l10n.profile,
    };
  }
}

class _DashboardScreen extends StatelessWidget {
  const _DashboardScreen({required this.onOpenTab});

  final ValueChanged<int> onOpenTab;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final appState = context.watch<AppState>();
    final sync = context.watch<SyncController>();
    final masterData = context.watch<MasterDataController>();
    final name = appState.session?.user.name ?? '';
    final counts = masterData.counts;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.appTitle)),
      body: RefreshIndicator(
        onRefresh: () => masterData.refresh(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            const AttendanceCard(),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.welcome,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      name.isEmpty ? '…' : name,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.itemsCount(counts['products'] ?? 0),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _Stat(
              icon: Icons.people_outline,
              label: l10n.customers,
              value: (counts['customers'] ?? 0).toString(),
              onTap: () => onOpenTab(2),
            ),
            const SizedBox(height: 8),
            _Stat(
              icon: Icons.alt_route,
              label: l10n.routes,
              value: (counts['routes'] ?? 0).toString(),
              onTap: () => onOpenTab(1),
            ),
            const SizedBox(height: 8),
            _Stat(
              icon: Icons.collections_bookmark_outlined,
              label: l10n.priceListsLabel,
              value: (counts['price_lists'] ?? 0).toString(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ProductsScreen()),
              ),
            ),
            const SizedBox(height: 16),
            _Stat(
              icon: Icons.cloud_outlined,
              label: l10n.syncing,
              value: sync.syncing ? '…' : '—',
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: masterData.loading ? null : () => masterData.refresh(),
              icon: const Icon(Icons.refresh),
              label: Text(l10n.refresh),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileScreen extends StatelessWidget {
  const _ProfileScreen();

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final appState = context.read<AppState>();
    final user = appState.session?.user;
    final tenant = appState.session?.tenant;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.profile)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: const Icon(Icons.person),
          ),
          const SizedBox(height: 12),
          Text(
            user?.name ?? '—',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(
            user?.email ?? '—',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (tenant != null && tenant.name.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              tenant.name,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => appState.signOut(),
            icon: const Icon(Icons.logout),
            label: Text(l10n.signOut),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
        trailing: Text(value),
        onTap: onTap,
      ),
    );
  }
}
