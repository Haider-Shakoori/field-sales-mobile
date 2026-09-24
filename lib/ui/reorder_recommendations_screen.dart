import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/orders/order_repository.dart';
import '../state/order_controller.dart';
import 'order_create_screen.dart';

class ReorderRecommendationsScreen extends StatefulWidget {
  const ReorderRecommendationsScreen({
    required this.customer,
    required this.products,
    super.key,
  });

  final Map<String, dynamic> customer;
  final List<Map<String, dynamic>> products;

  @override
  State<ReorderRecommendationsScreen> createState() =>
      _ReorderRecommendationsScreenState();
}

class _ReorderRecommendationsScreenState
    extends State<ReorderRecommendationsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await context
          .read<OrderController>()
          .reorderRecommendations(widget.customer);
      if (!mounted) return;
      setState(() => _rows = rows);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _buildOrder() {
    final products = {
      for (final product in widget.products)
        if (product['id'] != null) product['id'].toString(): product,
    };
    final lines = <OrderDraftLine>[];

    for (final row in _rows) {
      final quantity = _number(row['suggested_quantity']);
      final product = products[row['product_id']?.toString()];
      if (product == null || quantity <= 0) continue;
      lines.add(
        OrderDraftLine(
          product: product,
          quantity: quantity,
          discountPercent: 0,
        ),
      );
    }

    if (lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No suggested quantity is currently available to order.'),
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OrderCreateScreen(
          customers: [widget.customer],
          products: widget.products,
          initialCustomerId: widget.customer['id']?.toString(),
          initialLines: lines,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reorder recommendations')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.customer['name']?.toString() ?? 'Customer',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Suggestions use approved purchase cadence and recent average quantities. '
                      'One-off purchases are not treated as recurring demand.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_error!),
                ),
              )
            else if (_rows.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No repeat-purchase recommendation is due yet. At least two approved purchases of a product are required.',
                  ),
                ),
              )
            else ...[
              ..._rows.map((row) {
                final due = (row['days_until_due'] as num?)?.toInt() ?? 0;
                final stockLimited = row['stock_limited'] == true;
                final suggested = _number(row['suggested_quantity']);
                final unit = row['unit']?.toString() ?? '';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  row['name']?.toString() ?? 'Product',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Chip(
                                label: Text(
                                  due < 0
                                      ? '${-due}d overdue'
                                      : (due == 0 ? 'Due today' : 'Due in ${due}d'),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '${row['sku'] ?? ''} · ${row['purchase_count']} approved orders · ${row['confidence']} confidence',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _Metric(
                                  label: 'Suggested',
                                  value: '${_compact(suggested)} $unit',
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _Metric(
                                  label: 'Typical cycle',
                                  value: '${row['typical_interval_days']} days',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            row['reason']?.toString() ?? '',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (row['stock_enabled'] == true) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Available stock: ${_compact(_number(row['available_stock']))} $unit${stockLimited ? ' · stock limited' : ''}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: stockLimited
                                    ? FontWeight.w700
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _buildOrder,
                icon: const Icon(Icons.shopping_cart_checkout_outlined),
                label: const Text('Build suggested order'),
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  static double _number(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

  static String _compact(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(2);
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );
}