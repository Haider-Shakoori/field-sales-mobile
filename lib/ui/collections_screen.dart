import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/collection_controller.dart';
import '../state/master_data_controller.dart';
import 'collection_create_screen.dart';
import 'collection_detail_screen.dart';

class CollectionsScreen extends StatelessWidget {
  const CollectionsScreen({super.key});

  Future<void> _create(BuildContext context) async {
    final customers = context.read<MasterDataController>().customers;

    if (customers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sync customers before collecting.')),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CollectionCreateScreen(customers: customers),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CollectionController>();

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => state.sync(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Customer balances',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (state.balances.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No cached receivable balances yet.'),
                ),
              )
            else
              ...state.balances.map(
                (balance) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.account_balance_wallet_outlined),
                    title: Text(
                      balance['customer_name']?.toString() ?? 'Customer',
                    ),
                    subtitle: Text(
                      'Pending: ' +
                          balance['pending_collections'].toString() +
                          ' ' +
                          balance['currency'].toString(),
                    ),
                    trailing: Text(
                      balance['outstanding_balance'].toString() +
                          ' ' +
                          balance['currency'].toString(),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 20),
            Text(
              'Recent collections',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (state.collections.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No collections recorded yet.'),
                ),
              )
            else
              ...state.collections.map(
                (collection) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.payments_outlined),
                    title: Text(
                      collection['receipt_number']?.toString() ??
                          'Offline receipt',
                    ),
                    subtitle: Text(
                      [
                        collection['customer_name'],
                        collection['payment_method'],
                        collection['status'],
                        if (collection['sync_status'] != 'synced')
                          'Sync: ' + collection['sync_status'].toString(),
                      ].where((value) => value != null).join(' · '),
                    ),
                    trailing: Text(
                      collection['amount'].toString() +
                          ' ' +
                          collection['currency'].toString(),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CollectionDetailScreen(
                          collection: collection,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 88),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: state.busy ? null : () => _create(context),
        icon: const Icon(Icons.add_card),
        label: const Text('Collect'),
      ),
    );
  }
}
