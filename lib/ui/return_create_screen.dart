import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/inventory/inventory_repository.dart';
import '../state/inventory_controller.dart';
import '../state/master_data_controller.dart';
import '../state/order_controller.dart';

class ReturnCreateScreen extends StatefulWidget {
  const ReturnCreateScreen({
    this.initialCustomerId,
    this.visitUuid,
    super.key,
  });

  final String? initialCustomerId;
  final String? visitUuid;

  @override
  State<ReturnCreateScreen> createState() => _ReturnCreateScreenState();
}

class _ReturnCreateScreenState extends State<ReturnCreateScreen> {
  final _reason = TextEditingController();
  final _notes = TextEditingController();
  final _lines = <_ReturnRow>[];

  String? _customerId;
  String? _orderUuid;
  List<String>? _orderProductIds;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _customerId = widget.initialCustomerId;
  }

  @override
  void dispose() {
    _reason.dispose();
    _notes.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic>? _customer(List<Map<String, dynamic>> customers) {
    for (final customer in customers) {
      if (customer['id']?.toString() == _customerId) return customer;
    }
    return null;
  }

  List<Map<String, dynamic>> _eligibleOrders(OrderController orders) {
    return orders.orders
        .where(
          (order) =>
              order['customer_uuid']?.toString() == _customerId &&
              order['status']?.toString() == 'approved' &&
              order['sync_status']?.toString() == 'synced',
        )
        .toList();
  }

  Map<String, dynamic>? _selectedOrder(OrderController orders) {
    for (final order in orders.orders) {
      if (order['offline_uuid']?.toString() == _orderUuid) return order;
    }
    return null;
  }

  Future<void> _selectOrder(
    String? value,
    OrderController orders,
  ) async {
    setState(() {
      _orderUuid = value;
      _orderProductIds = null;
      for (final line in _lines) {
        line.dispose();
      }
      _lines.clear();
    });

    if (value == null) return;

    final order = _selectedOrder(orders);
    if (order == null) return;

    final items = await orders.items(order);
    if (!mounted) return;

    setState(() {
      _orderProductIds = items
          .map((item) => item['product_uuid']?.toString() ?? '')
          .where((value) => value.isNotEmpty)
          .toList();
    });
  }

  Future<void> _addProduct(List<Map<String, dynamic>> products) async {
    final eligible = _orderProductIds == null
        ? products
        : products
              .where(
                (product) =>
                    _orderProductIds!.contains(product['id']?.toString()),
              )
              .toList();

    if (eligible.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No returnable products are available.')),
      );
      return;
    }

    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          itemCount: eligible.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, index) {
            final product = eligible[index];
            return ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: Text(product['name']?.toString() ?? 'Product'),
              subtitle: Text(
                '${product['sku'] ?? ''} · ${product['unit'] ?? ''}',
              ),
              onTap: () => Navigator.pop(sheetContext, product),
            );
          },
        ),
      ),
    );

    if (selected != null && mounted) {
      setState(() => _lines.add(_ReturnRow(selected)));
    }
  }

  List<ReturnDraftLine> _draftLines() {
    final seen = <String>{};

    return _lines.map((row) {
      final quantity = double.tryParse(row.quantity.text.trim());

      if (quantity == null || quantity <= 0) {
        throw StateError(
          'Enter a valid quantity for ${row.product['name'] ?? 'product'}.',
        );
      }

      final key = '${row.product['id']}|${row.condition}';
      if (!seen.add(key)) {
        throw StateError(
          'The same product and condition can appear only once.',
        );
      }

      return ReturnDraftLine(
        product: row.product,
        quantity: quantity,
        condition: row.condition,
        reason: row.reason.text.trim().isEmpty
            ? null
            : row.reason.text.trim(),
      );
    }).toList();
  }

  Future<void> _save() async {
    final master = context.read<MasterDataController>();
    final orders = context.read<OrderController>();
    final customer = _customer(master.customers);

    if (customer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a customer.')),
      );
      return;
    }

    if (_reason.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a return reason.')),
      );
      return;
    }

    if (_lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one returned product.')),
      );
      return;
    }

    late final List<ReturnDraftLine> lines;
    try {
      lines = _draftLines();
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
      return;
    }

    setState(() => _saving = true);

    final inventory = context.read<InventoryController>();
    await inventory.createReturn(
      customer: customer,
      reason: _reason.text,
      lines: lines,
      visitUuid: widget.visitUuid,
      order: _selectedOrder(orders),
      notes: _notes.text,
    );

    if (!mounted) return;
    setState(() => _saving = false);

    if (inventory.message == 'Return saved locally.') {
      Navigator.pop(context, true);
    } else if (inventory.message != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(inventory.message!)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final master = context.watch<MasterDataController>();
    final orders = context.watch<OrderController>();
    final eligibleOrders = _eligibleOrders(orders);

    return Scaffold(
      appBar: AppBar(title: const Text('New return')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _customerId,
            decoration: const InputDecoration(labelText: 'Customer'),
            items: master.customers
                .map(
                  (customer) => DropdownMenuItem(
                    value: customer['id'].toString(),
                    child: Text(customer['name']?.toString() ?? 'Customer'),
                  ),
                )
                .toList(),
            onChanged: widget.initialCustomerId == null
                ? (value) {
                    setState(() {
                      _customerId = value;
                      _orderUuid = null;
                      _orderProductIds = null;
                      for (final line in _lines) {
                        line.dispose();
                      }
                      _lines.clear();
                    });
                  }
                : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _orderUuid,
            decoration: const InputDecoration(
              labelText: 'Approved order (optional)',
            ),
            items: eligibleOrders
                .map(
                  (order) => DropdownMenuItem(
                    value: order['offline_uuid'].toString(),
                    child: Text(
                      order['order_number']?.toString().isNotEmpty == true
                          ? order['order_number'].toString()
                          : 'Order · ${order['ordered_at']}',
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) => _selectOrder(value, orders),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            decoration: const InputDecoration(labelText: 'Return reason'),
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
                  'Returned products',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              OutlinedButton.icon(
                onPressed: _saving
                    ? null
                    : () => _addProduct(master.products),
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
                child: Text('No returned products added yet.'),
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
                    const SizedBox(height: 8),
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
                          child: DropdownButtonFormField<String>(
                            initialValue: line.condition,
                            decoration: const InputDecoration(
                              labelText: 'Condition',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'sellable',
                                child: Text('Sellable'),
                              ),
                              DropdownMenuItem(
                                value: 'damaged',
                                child: Text('Damaged'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => line.condition = value);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: line.reason,
                      decoration: const InputDecoration(
                        labelText: 'Item reason (optional)',
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Saving…' : 'Save return'),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}

class _ReturnRow {
  _ReturnRow(this.product);

  final Map<String, dynamic> product;
  final quantity = TextEditingController(text: '1');
  final reason = TextEditingController();
  String condition = 'sellable';

  void dispose() {
    quantity.dispose();
    reason.dispose();
  }
}
