import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/master_data_controller.dart';

class ProductsScreen extends StatelessWidget {
  const ProductsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<MasterDataController>();
    final rows = [...state.products]
      ..sort(
        (a, b) => (a['name'] ?? '')
            .toString()
            .compareTo((b['name'] ?? '').toString()),
      );

    return RefreshIndicator(
      onRefresh: () => state.sync(),
      child: rows.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 180),
                Icon(Icons.inventory_2_outlined, size: 48),
                SizedBox(height: 12),
                Center(
                  child: Text('No products cached yet. Pull down to sync.'),
                ),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, index) {
                final product = rows[index];
                final price = product['base_price'];
                final currency = product['currency'] ?? '';

                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.inventory_2),
                    title: Text(product['name']?.toString() ?? 'Product'),
                    subtitle: Text(
                      '${product['sku'] ?? ''} · ${product['unit'] ?? ''}',
                    ),
                    trailing: Text(
                      price == null ? '' : '$price $currency',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
