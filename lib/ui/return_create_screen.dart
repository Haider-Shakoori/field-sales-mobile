import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/stock/stock_return_repository.dart';
import '../state/app_state.dart';
import '../state/master_data_controller.dart';
import 'sync_refresh.dart';

class ReturnCreateScreen extends StatefulWidget {
  const ReturnCreateScreen({this.initialCustomerId, this.visitUuid, super.key});

  final String? initialCustomerId;
  final String? visitUuid;

  @override
  State<ReturnCreateScreen> createState() => _ReturnCreateScreenState();
}

class _ReturnCreateScreenState extends State<ReturnCreateScreen> {
  String? _customerId;
  final _notes = TextEditingController();
  final List<_ReturnLineDraft> _lines = [];
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _customerId = widget.initialCustomerId;
  }

  @override
  void dispose() {
    _notes.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  void _addLine(List<Map<String, dynamic>> products) {
    if (products.isEmpty) return;

    setState(() {
      _lines.add(_ReturnLineDraft(productId: products.first['id'].toString()));
    });
  }

  Future<void> _save(
    List<Map<String, dynamic>> customers,
    List<Map<String, dynamic>> products,
  ) async {
    if (_saving) return;

    final tenantId = context.read<AppState>().session?.tenantId;
    if (tenantId == null || _customerId == null) {
      setState(() => _error = 'Select a customer.');
      return;
    }

    Map<String, dynamic>? customer;
    for (final row in customers) {
      if (row['id']?.toString() == _customerId) {
        customer = row;
        break;
      }
    }

    if (customer == null) {
      setState(() => _error = 'Selected customer is not available offline.');
      return;
    }

    if (_lines.isEmpty) {
      setState(() => _error = 'Add at least one returned product.');
      return;
    }

    final result = <ReturnDraftLine>[];

    for (final line in _lines) {
      Map<String, dynamic>? product;
      for (final row in products) {
        if (row['id']?.toString() == line.productId) {
          product = row;
          break;
        }
      }

      final quantity = double.tryParse(line.quantity.text.trim());

      if (product == null || quantity == null || quantity <= 0) {
        setState(
          () =>
              _error = 'Every return line needs a valid product and quantity.',
        );
        return;
      }

      result.add(
        ReturnDraftLine(
          product: product,
          quantity: quantity,
          condition: line.condition,
          reason: line.reason.text,
        ),
      );
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await context.read<StockReturnRepository>().createOffline(
        tenantId: tenantId,
        customer: customer,
        returnedAt: DateTime.now(),
        items: result,
        visitUuid: widget.visitUuid,
        notes: _notes.text,
      );

      if (mounted) {
        await syncAndReload(context, triggerSource: 'return:create');
        if (mounted) Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final master = context.watch<MasterDataController>();
    final customers = master.customers;
    final products = master.products;

    return Scaffold(
      appBar: AppBar(title: const Text('New return')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _customerId,
            decoration: const InputDecoration(labelText: 'Customer'),
            items: customers
                .map(
                  (row) => DropdownMenuItem(
                    value: row['id'].toString(),
                    child: Text((row['name'] ?? 'Customer').toString()),
                  ),
                )
                .toList(),
            onChanged: widget.initialCustomerId == null
                ? (value) => setState(() => _customerId = value)
                : null,
          ),
          const SizedBox(height: 16),
          ..._lines.asMap().entries.map((entry) {
            final index = entry.key;
            final line = entry.value;

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text('Item ${index + 1}')),
                        IconButton(
                          onPressed: () {
                            setState(() {
                              final removed = _lines.removeAt(index);
                              removed.dispose();
                            });
                          },
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: line.productId,
                      decoration: const InputDecoration(labelText: 'Product'),
                      items: products
                          .map(
                            (row) => DropdownMenuItem(
                              value: row['id'].toString(),
                              child: Text(
                                (row['name'] ?? 'Product').toString(),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) line.productId = value;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: line.quantity,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: 'Quantity'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: line.condition,
                      decoration: const InputDecoration(labelText: 'Condition'),
                      items: const [
                        DropdownMenuItem(
                          value: 'resalable',
                          child: Text('Resalable'),
                        ),
                        DropdownMenuItem(
                          value: 'damaged',
                          child: Text('Damaged'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) line.condition = value;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: line.reason,
                      decoration: const InputDecoration(
                        labelText: 'Reason / condition note',
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          OutlinedButton.icon(
            onPressed: products.isEmpty ? null : () => _addLine(products),
            icon: const Icon(Icons.add),
            label: const Text('Add returned product'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Return notes'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _saving ? null : () => _save(customers, products),
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.assignment_return_outlined),
            label: const Text('Save return'),
          ),
        ],
      ),
    );
  }
}

class _ReturnLineDraft {
  _ReturnLineDraft({required this.productId});

  String productId;
  String condition = 'resalable';
  final quantity = TextEditingController();
  final reason = TextEditingController();

  void dispose() {
    quantity.dispose();
    reason.dispose();
  }
}
