import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/order_controller.dart';

class InvoiceScreen extends StatelessWidget {
  const InvoiceScreen({
    required this.order,
    super.key,
  });

  final Map<String, dynamic> order;

  @override
  Widget build(BuildContext context) {
    if (order['status'] != 'approved') {
      return const Scaffold(
        body: Center(
          child: Text('An invoice is available only for approved orders.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Invoice ${order['order_number'] ?? ''}'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: context.read<OrderController>().items(order),
        builder: (context, snapshot) {
          final items = snapshot.data ?? const <Map<String, dynamic>>[];

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'INVOICE',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(order['order_number']?.toString() ?? ''),
              const Divider(height: 32),
              Text(
                order['customer_name']?.toString() ?? 'Customer',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              _row('Date', order['ordered_at']),
              _row('Payment', order['payment_type']),
              if (order['due_date'] != null)
                _row('Due date', order['due_date']),
              _row('Currency', order['currency']),
              const SizedBox(height: 20),
              Text('Items', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...items.map(
                (item) => Card(
                  child: ListTile(
                    title: Text(item['product_name']?.toString() ?? 'Product'),
                    subtitle: Text(
                      '${item['product_sku'] ?? ''} · '
                      '${item['quantity']} ${item['unit']} × '
                      '${item['unit_price']}',
                    ),
                    trailing: Text(
                      '${item['line_total']} ${order['currency'] ?? ''}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
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
                      _row(
                        'Subtotal',
                        '${order['subtotal'] ?? 0} ${order['currency'] ?? ''}',
                      ),
                      _row(
                        'Discount',
                        '${order['discount_total'] ?? 0} '
                        '${order['currency'] ?? ''}',
                      ),
                      const Divider(),
                      _row(
                        'Total',
                        '${order['grand_total'] ?? 0} '
                        '${order['currency'] ?? ''}',
                        bold: true,
                      ),
                    ],
                  ),
                ),
              ),
              if (order['notes'] != null) ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Notes: ${order['notes']}'),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                'Approved FieldPulse order · available offline on this device.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  Widget _row(String label, dynamic value, {bool bold = false}) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value?.toString() ?? '—',
              textAlign: TextAlign.end,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}
