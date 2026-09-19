import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/master_data_controller.dart';
import '../state/order_controller.dart';
import '../state/visit_controller.dart';
import 'order_create_screen.dart';
import 'order_detail_screen.dart';

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  Future<void> _create(BuildContext context) async {
    final master = context.read<MasterDataController>();

    if (master.customers.isEmpty || master.products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sync customers and products before creating an order.',
          ),
        ),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OrderCreateScreen(
          customers: master.customers,
          products: master.products,
          visits: context.read<VisitController>().visits,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<OrderController>();

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => state.sync(),
        child: state.orders.isEmpty
            ? ListView(
                padding: const EdgeInsets.all(20),
                children: const [
                  SizedBox(height: 150),
                  Icon(Icons.receipt_long_outlined, size: 52),
                  SizedBox(height: 12),
                  Center(child: Text('No orders recorded yet.')),
                  SizedBox(height: 6),
                  Center(
                    child: Text(
                      'Orders are stored locally first and sync when online.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: state.orders.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, index) {
                  final order = state.orders[index];
                  final synced = order['sync_status'] == 'synced';

                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: Text(
                        order['order_number']?.toString() ?? 'Offline order',
                      ),
                      subtitle: Text(
                        [
                          order['customer_name'],
                          order['payment_type'],
                          order['status'],
                          if (!synced)
                            'Sync: ' + order['sync_status'].toString(),
                        ].where((value) => value != null).join(' · '),
                      ),
                      trailing: Text(
                        (order['grand_total'] ?? 0).toString() +
                            ' ' +
                            (order['currency'] ?? '').toString(),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => OrderDetailScreen(order: order),
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: state.busy ? null : () => _create(context),
        icon: const Icon(Icons.add_shopping_cart),
        label: const Text('Order'),
      ),
    );
  }
}
