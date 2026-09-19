import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/order_controller.dart';

class OrderDetailScreen extends StatelessWidget {
  const OrderDetailScreen({required this.order, super.key});

  final Map<String, dynamic> order;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(order['order_number']?.toString() ?? 'Offline order'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: context.read<OrderController>().items(order),
        builder: (context, snapshot) {
          final items = snapshot.data ?? const <Map<String, dynamic>>[];

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order['customer_name']?.toString() ?? 'Customer',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Status: ' + (order['status'] ?? 'pending').toString(),
                      ),
                      Text(
                        'Payment: ' + (order['payment_type'] ?? '—').toString(),
                      ),
                      Text(
                        'Ordered: ' + (order['ordered_at'] ?? '—').toString(),
                      ),
                      if (order['visit_uuid'] != null)
                        Text('Visit: ' + order['visit_uuid'].toString()),
                      if (order['notes'] != null)
                        Text('Notes: ' + order['notes'].toString()),
                      if (order['status_note'] != null)
                        Text('Status note: ' + order['status_note'].toString()),
                      if (order['sync_status'] != 'synced')
                        Text(
                          'Sync: ' + order['sync_status'].toString(),
                          style: TextStyle(color: Colors.orange.shade700),
                        ),
                      if (order['last_error'] != null)
                        Text(
                          order['last_error'].toString(),
                          style: const TextStyle(color: Colors.red),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text('Items', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...items.map(
                (item) => Card(
                  child: ListTile(
                    title: Text(item['product_name']?.toString() ?? 'Product'),
                    subtitle: Text(
                      item['quantity'].toString() +
                          ' ' +
                          item['unit'].toString() +
                          ' × ' +
                          item['unit_price'].toString() +
                          ' · Discount ' +
                          item['discount_percent'].toString() +
                          '%',
                    ),
                    trailing: Text(
                      item['line_total'].toString() +
                          ' ' +
                          (order['currency'] ?? '').toString(),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _moneyRow(
                        'Subtotal',
                        order['subtotal'],
                        order['currency'],
                      ),
                      _moneyRow(
                        'Discount',
                        order['discount_total'],
                        order['currency'],
                      ),
                      const Divider(),
                      _moneyRow(
                        'Total',
                        order['grand_total'],
                        order['currency'],
                        bold: true,
                      ),
                      if (order['pricing_adjusted'] == 1) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Server pricing changed the offline estimate.',
                          style: TextStyle(color: Colors.orange.shade700),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _moneyRow(
    String label,
    dynamic value,
    dynamic currency, {
    bool bold = false,
  }) {
    final style = TextStyle(fontWeight: bold ? FontWeight.bold : null);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(
            (value ?? 0).toString() + ' ' + (currency ?? '').toString(),
            style: style,
          ),
        ],
      ),
    );
  }
}
