import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/orders/order_repository.dart';
import '../state/order_controller.dart';

class OrderCreateScreen extends StatefulWidget {
  const OrderCreateScreen({
    required this.customers,
    required this.products,
    this.initialCustomerId,
    this.visitUuid,
    this.initialLines = const [],
    super.key,
  });

  final List<Map<String, dynamic>> customers;
  final List<Map<String, dynamic>> products;
  final String? initialCustomerId;
  final String? visitUuid;
  final List<OrderDraftLine> initialLines;

  @override
  State<OrderCreateScreen> createState() => _OrderCreateScreenState();
}

class _OrderCreateScreenState extends State<OrderCreateScreen> {
  final _notes = TextEditingController();
  final _lines = <_DraftRow>[];

  String? _customerId;
  String _paymentType = 'cash';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _customerId = widget.initialCustomerId;
    _lines.addAll(
      widget.initialLines.map(
        (line) => _DraftRow(
          line.product,
          quantity: line.quantity,
          discountPercent: line.discountPercent,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _notes.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic>? get _customer {
    for (final row in widget.customers) {
      if (row['id']?.toString() == _customerId) return row;
    }
    return null;
  }

  Future<void> _addProduct() async {
    final existing = _lines
        .map((line) => line.product['id']?.toString())
        .toSet();

    final available = widget.products
        .where((product) => !existing.contains(product['id']?.toString()))
        .toList();

    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All available products are already added.'),
        ),
      );
      return;
    }

    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          itemCount: available.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, index) {
            final product = available[index];
            return ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: Text(product['name']?.toString() ?? 'Product'),
              subtitle: Text(
                "${product['sku'] ?? ''} · ${product['unit'] ?? ''}",
              ),
              trailing: Text(
                "${product['base_price'] ?? 0} ${product['currency'] ?? ''}",
              ),
              onTap: () => Navigator.pop(sheetContext, product),
            );
          },
        ),
      ),
    );

    if (selected != null && mounted) {
      setState(() => _lines.add(_DraftRow(selected)));
    }
  }

  List<OrderDraftLine> _draftLines() {
    return _lines.map((row) {
      final quantity = double.tryParse(row.quantity.text.trim());
      final discount = double.tryParse(row.discount.text.trim()) ?? 0;

      if (quantity == null || quantity <= 0) {
        throw StateError(
          "Enter a valid quantity for ${row.product['name'] ?? 'product'}.",
        );
      }

      if (discount < 0 || discount > 100) {
        throw StateError('Discount must be between 0 and 100.');
      }

      return OrderDraftLine(
        product: row.product,
        quantity: quantity,
        discountPercent: discount,
      );
    }).toList();
  }

  Future<void> _reviewAndSave() async {
    final customer = _customer;
    if (customer == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Select a customer.')));
      return;
    }

    if (_lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one product.')),
      );
      return;
    }

    late final List<OrderDraftLine> draftLines;
    late final OrderPreview preview;

    try {
      draftLines = _draftLines();
      preview = await context.read<OrderController>().preview(
        customer: customer,
        lines: draftLines,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
      return;
    }

    if (!mounted) return;

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Review order'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Customer: ${customer['name']}"),
                  Text('Payment: $_paymentType'),
                  if (widget.visitUuid != null)
                    const Text('Linked to customer visit'),
                  const Divider(height: 24),
                  ...preview.lines.map(
                    (line) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              "${line.product['name']} × ${line.quantity}",
                            ),
                          ),
                          Text(line.lineTotal.toString()),
                        ],
                      ),
                    ),
                  ),
                  const Divider(),
                  _reviewRow('Subtotal', preview.subtotal, preview.currency),
                  _reviewRow(
                    'Discount',
                    preview.discountTotal,
                    preview.currency,
                  ),
                  _reviewRow(
                    'Offline estimate',
                    preview.grandTotal,
                    preview.currency,
                    bold: true,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Final pricing is revalidated by the server when this order synchronizes.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Edit'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Save order'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed || !mounted) return;

    setState(() => _saving = true);
    final controller = context.read<OrderController>();

    await controller.create(
      customer: customer,
      paymentType: _paymentType,
      lines: draftLines,
      visitUuid: widget.visitUuid,
      notes: _notes.text,
    );

    if (!mounted) return;
    setState(() => _saving = false);

    if (controller.message == 'Order saved locally.') {
      Navigator.pop(context);
    } else if (controller.message != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(controller.message!)));
    }
  }

  Widget _reviewRow(
    String label,
    double value,
    String currency, {
    bool bold = false,
  }) {
    final style = TextStyle(fontWeight: bold ? FontWeight.bold : null);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text('${value.toStringAsFixed(2)} $currency', style: style),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New order')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _customerId,
            decoration: const InputDecoration(labelText: 'Customer'),
            items: widget.customers
                .map(
                  (customer) => DropdownMenuItem(
                    value: customer['id'].toString(),
                    child: Text(customer['name']?.toString() ?? 'Customer'),
                  ),
                )
                .toList(),
            onChanged: widget.initialCustomerId == null
                ? (value) => setState(() => _customerId = value)
                : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _paymentType,
            decoration: const InputDecoration(labelText: 'Payment type'),
            items: const [
              DropdownMenuItem(value: 'cash', child: Text('Cash')),
              DropdownMenuItem(value: 'credit', child: Text('Credit')),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _paymentType = value);
              }
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Products',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              OutlinedButton.icon(
                onPressed: _saving ? null : _addProduct,
                icon: const Icon(Icons.add),
                label: const Text('Add product'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_lines.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('No products added yet.'),
              ),
            ),
          ..._lines.asMap().entries.map((entry) {
            final index = entry.key;
            final line = entry.value;

            return Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            line.product['name']?.toString() ?? 'Product',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove',
                          onPressed: _saving
                              ? null
                              : () {
                                  setState(() {
                                    final removed = _lines.removeAt(index);
                                    removed.dispose();
                                  });
                                },
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: line.quantity,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Quantity',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: line.discount,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Discount %',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _reviewAndSave,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_circle_outline),
            label: Text(_saving ? 'Saving…' : 'Review & save'),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _DraftRow {
  _DraftRow(this.product, {double quantity = 1, double discountPercent = 0})
    : quantity = TextEditingController(text: _formatNumber(quantity)),
      discount = TextEditingController(text: _formatNumber(discountPercent));

  final Map<String, dynamic> product;
  final TextEditingController quantity;
  final TextEditingController discount;

  static String _formatNumber(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value
        .toStringAsFixed(4)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  void dispose() {
    quantity.dispose();
    discount.dispose();
  }
}
