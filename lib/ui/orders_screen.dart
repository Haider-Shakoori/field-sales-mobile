import 'package:field_sales_mobile/l10n/localized_material.dart';
import 'package:provider/provider.dart';

import '../state/master_data_controller.dart';
import '../state/order_controller.dart';
import 'fieldpulse_theme.dart';
import 'order_create_screen.dart';
import 'order_detail_screen.dart';
import 'sync_refresh.dart';
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
                  final syncColor = synced
                      ? FieldPulseTheme.success
                      : FieldPulseTheme.warning;
                  final customer =
                      order['customer_name']?.toString().trim() ?? '';
                  final status = order['status']?.toString().trim() ?? '';
                  final payment =
                      order['payment_type']?.toString().trim() ?? '';

                  return FieldPulseGlassCard(
                    padding: const EdgeInsets.all(16),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => OrderDetailScreen(order: order),
                      ),
                    ),
                    tint: syncColor,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const FieldPulseIconBadge(
                              icon: Icons.receipt_long_outlined,
                              size: 44,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    order['order_number']?.toString() ??
                                        'Offline order',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  if (customer.isNotEmpty) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      customer,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              "${order['grand_total'] ?? 0} ${order['currency'] ?? ''}",
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                        const SizedBox(height: 13),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FieldPulseStatusPill(
                              label: synced ? 'Synced' : 'Pending sync',
                              color: syncColor,
                              icon: synced
                                  ? Icons.cloud_done_outlined
                                  : Icons.cloud_upload_outlined,
                            ),
                            if (status.isNotEmpty)
                              FieldPulseStatusPill(
                                label: status,
                                color: FieldPulseTheme.blue,
                              ),
                            if (payment.isNotEmpty)
                              FieldPulseStatusPill(
                                label: payment,
                                color: FieldPulseTheme.muted,
                              ),
                          ],
                        ),
                      ],
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
