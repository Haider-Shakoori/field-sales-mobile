import 'package:field_sales_mobile/l10n/localized_material.dart';
import 'package:provider/provider.dart';

import '../state/master_data_controller.dart';
import '../state/order_controller.dart';
import 'order_create_screen.dart';
import 'order_detail_screen.dart';
import 'sync_refresh.dart';
import 'fieldpulse_theme.dart';
import 'widgets/fieldpulse_ui.dart';

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
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<OrderController>();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: () => syncAndReload(context, triggerSource: 'pull:orders'),
        child: state.orders.isEmpty
            ? ListView(
                padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
                children: const [
                  SizedBox(height: 80),
                  FieldPulseEmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'No orders yet',
                    message:
                        'Orders are stored locally first and sync when online.',
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                itemCount: state.orders.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, index) {
                  final order = state.orders[index];
                  final synced = order['sync_status'] == 'synced';

                  return FieldPulseGlassCard(
                    padding: EdgeInsets.zero,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => OrderDetailScreen(order: order),
                      ),
                    ),
                    child: ListTile(
                      leading: const FieldPulseIconBadge(
                        icon: Icons.receipt_long_outlined,
                        size: 42,
                      ),
                      title: Text(
                        order['order_number']?.toString() ?? 'Offline order',
                      ),
                      subtitle: Text(
                        [
                          order['customer_name'],
                          order['payment_type'],
                          order['status'],
                          if (!synced) "Sync: ${order['sync_status']}",
                        ].where((value) => value != null).join(' · '),
                      ),
                      trailing: Text(
                        "${order['grand_total'] ?? 0} ${order['currency'] ?? ''}",
                        style: const TextStyle(fontWeight: FontWeight.w600),
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
