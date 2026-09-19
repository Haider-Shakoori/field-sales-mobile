import 'package:flutter/material.dart';

import 'collections_screen.dart';
import 'collections_screen.dart';
import 'products_screen.dart';
import 'routes_screen.dart';
import 'sync_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  void _open(BuildContext context, String title, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: screen,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.payments_outlined),
            title: const Text('Collections'),
            subtitle: const Text('Customer balances, receipts and payments'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () =>
                _open(context, 'Collections', const CollectionsScreen()),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.route_outlined),
            title: const Text('Routes'),
            subtitle: const Text('Assigned routes and customer sequence'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(context, 'Routes', const RoutesScreen()),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: const Text('Products'),
            subtitle: const Text('Cached product catalog and pricing'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(context, 'Products', const ProductsScreen()),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.sync_outlined),
            title: const Text('Sync'),
            subtitle: const Text('Review and upload pending offline work'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(context, 'Sync', const SyncScreen()),
          ),
        ),
      ],
    );
  }
}
