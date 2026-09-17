import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/master_data.dart';
import '../../l10n/app_l10n.dart';
import '../../state/master_data_controller.dart';

/// Freestanding master-data detail/refresh helper.

class DataRefreshBar extends StatelessWidget {
  const DataRefreshBar({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<MasterDataController>();
    final l10n = AppL10n.of(context);
    final last = controller.lastRefreshed;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              last == null
                  ? l10n.pullToRefresh
                  : '${l10n.lastUpdated}: ${_time(last)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          IconButton(
            icon: controller.loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: controller.loading
                ? null
                : () => context.read<MasterDataController>().refresh(),
            tooltip: l10n.refresh,
          ),
        ],
      ),
    );
  }

  String _time(DateTime value) {
    final h = value.hour.toString().padLeft(2, '0');
    final m = value.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class EmptyDataView extends StatelessWidget {
  const EmptyDataView({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 8),
          Text(
            message ?? l10n.noData,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

/// Customers list read entirely from the SQLite cache.
class CustomersScreen extends StatelessWidget {
  const CustomersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<MasterDataController>();
    final l10n = AppL10n.of(context);
    final error = controller.error;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.customers)),
      body: FutureBuilder<List<CustomerDto>>(
        future: controller.repository.localCustomers(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final customers = snapshot.data ?? const <CustomerDto>[];
          return Column(
            children: [
              const DataRefreshBar(),
              if (error != null) _ErrorBanner(error: error),
              Expanded(
                child: customers.isEmpty
                    ? const EmptyDataView()
                    : RefreshIndicator(
                        onRefresh: () => controller.refresh(),
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: customers.length,
                          itemBuilder: (context, index) {
                            final c = customers[index];
                            return ListTile(
                              leading: const Icon(Icons.storefront_outlined),
                              title: Text(c.name ?? '—'),
                              subtitle: Text(
                                [
                                  if (c.phone != null) c.phone!,
                                  if (c.address != null) c.address!,
                                ].join(' · '),
                              ),
                              trailing:
                                  c.creditLimit != null && c.creditLimit! > 0
                                  ? Text(
                                      c.creditLimit!.toStringAsFixed(0),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium,
                                    )
                                  : null,
                              isThreeLine: c.phone != null || c.address != null,
                            );
                          },
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return Material(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(
              Icons.cloud_off,
              size: 18,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.error,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Routes list read from the SQLite cache; tapping shows the route's
/// customers (also from cache).
class RoutesScreen extends StatelessWidget {
  const RoutesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<MasterDataController>();
    final l10n = AppL10n.of(context);
    final error = controller.error;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.routes)),
      body: FutureBuilder<List<RouteDto>>(
        future: controller.repository.localRoutes(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final routes = snapshot.data ?? const <RouteDto>[];
          return Column(
            children: [
              const DataRefreshBar(),
              if (error != null) _ErrorBanner(error: error),
              Expanded(
                child: routes.isEmpty
                    ? const EmptyDataView()
                    : RefreshIndicator(
                        onRefresh: () => controller.refresh(),
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: routes.length,
                          itemBuilder: (context, index) {
                            final r = routes[index];
                            return ListTile(
                              leading: const Icon(Icons.alt_route),
                              title: Text(r.name ?? '—'),
                              subtitle: Text(
                                r.territoryName ?? r.weekdayName ?? '',
                              ),
                              trailing: Text(
                                '${r.customerCount ?? 0}',
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      _RouteCustomersScreen(routeId: r.id),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RouteCustomersScreen extends StatelessWidget {
  const _RouteCustomersScreen({required this.routeId});

  final int routeId;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<MasterDataController>();
    final l10n = AppL10n.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.customers)),
      body: FutureBuilder<List<RouteCustomerDto>>(
        future: controller.repository.localRouteCustomers(routeId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final customers = snapshot.data ?? const <RouteCustomerDto>[];
          if (customers.isEmpty) {
            return const EmptyDataView();
          }
          return ListView.builder(
            itemCount: customers.length,
            itemBuilder: (context, index) {
              final c = customers[index];
              final order = c.visitOrder ?? (index + 1);
              return ListTile(
                leading: CircleAvatar(
                  radius: 14,
                  child: Text('$order', style: const TextStyle(fontSize: 12)),
                ),
                title: Text(c.name ?? '—'),
                subtitle: c.code == null ? null : Text(c.code!),
              );
            },
          );
        },
      ),
    );
  }
}

/// Products list read from the SQLite cache.
class ProductsScreen extends StatelessWidget {
  const ProductsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<MasterDataController>();
    final l10n = AppL10n.of(context);
    final error = controller.error;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.products)),
      body: FutureBuilder<List<ProductDto>>(
        future: controller.repository.localProducts(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final products = snapshot.data ?? const <ProductDto>[];
          return Column(
            children: [
              const DataRefreshBar(),
              if (error != null) _ErrorBanner(error: error),
              Expanded(
                child: products.isEmpty
                    ? const EmptyDataView()
                    : RefreshIndicator(
                        onRefresh: () => controller.refresh(),
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: products.length,
                          itemBuilder: (context, index) {
                            final p = products[index];
                            return ListTile(
                              leading: const Icon(Icons.inventory_2_outlined),
                              title: Text(p.name ?? '—'),
                              subtitle: p.sku == null ? null : Text(p.sku!),
                              trailing: p.price == null
                                  ? null
                                  : Text(
                                      p.price!.toStringAsFixed(2),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium,
                                    ),
                              isThreeLine: false,
                            );
                          },
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
