import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/master_data/master_data_repository.dart';
import '../features/stock/stock_repository.dart';
import '../state/app_state.dart';

class StockReturnsScreen extends StatefulWidget {
  const StockReturnsScreen({super.key});

  @override
  State<StockReturnsScreen> createState() => _StockReturnsScreenState();
}

class _StockReturnsScreenState extends State<StockReturnsScreen> {
  bool _loading = true;
  String? _error;
  bool _enabled = false;
  List<Map<String, dynamic>> _stock = const [];
  List<Map<String, dynamic>> _returns = const [];

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load({bool refresh = false}) async {
    final tenantId = context.read<AppState>().session?.tenantId;
    if (tenantId == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    final repository = context.read<StockRepository>();

    try {
      if (refresh) {
        await repository.refresh(tenantId);
        await repository.syncPending(tenantId);
        await repository.refreshReturns(tenantId);
      }

      final enabled = await repository.enabled(tenantId);
      final stock = await repository.list(tenantId);
      final returns = await repository.returns(tenantId);

      if (mounted) {
        setState(() {
          _enabled = enabled;
          _stock = stock;
          _returns = returns;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _newReturn() async {
    final tenantId = context.read<AppState>().session?.tenantId;
    if (tenantId == null) return;

    final master = context.read<MasterDataRepository>();
    final customers = await master.list('customers', tenantId);
    final products = await master.list('products', tenantId);

    if (!mounted) return;

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            ReturnCreateScreen(customers: customers, products: products),
      ),
    );

    if (saved == true && mounted) {
      await _load(refresh: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(refresh: true),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: Icon(
                _enabled ? Icons.inventory_2 : Icons.inventory_2_outlined,
              ),
              title: Text(
                _enabled
                    ? 'Salesman stock control enabled'
                    : 'Stock control disabled',
              ),
              subtitle: Text(
                _enabled
                    ? 'Orders are checked against your available van stock.'
                    : 'Your company has not enabled stock enforcement yet.',
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'My stock',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                onPressed: () => _load(refresh: true),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          if (_stock.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('No salesman stock has been issued yet.'),
              ),
            ),
          ..._stock.map(
            (row) => Card(
              child: ListTile(
                title: Text(row['name']?.toString() ?? 'Product'),
                subtitle: Text(
                  '${row['sku'] ?? ''} · Damaged: ${_qty(row['damaged_qty'])}',
                ),
                trailing: Text(
                  '${_qty(row['sellable_qty'])} ${row['unit'] ?? ''}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Customer returns',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              FilledButton.icon(
                onPressed: _newReturn,
                icon: const Icon(Icons.keyboard_return),
                label: const Text('New return'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_returns.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('No customer returns recorded.'),
              ),
            ),
          ..._returns.map(
            (row) => Card(
              child: ListTile(
                leading: const Icon(Icons.assignment_return_outlined),
                title: Text(
                  row['return_number']?.toString() ??
                      row['customer_name']?.toString() ??
                      'Return',
                ),
                subtitle: Text(
                  '${row['customer_name'] ?? ''} · ${row['status'] ?? 'pending'}',
                ),
                trailing: Text(row['sync_status']?.toString() ?? ''),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  static String _qty(dynamic value) {
    final number = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0;
    return number.toStringAsFixed(4);
  }
}

class ReturnCreateScreen extends StatefulWidget {
  const ReturnCreateScreen({
    required this.customers,
    required this.products,
    super.key,
  });

  final List<Map<String, dynamic>> customers;
  final List<Map<String, dynamic>> products;

  @override
  State<ReturnCreateScreen> createState() => _ReturnCreateScreenState();
}

class _ReturnCreateScreenState extends State<ReturnCreateScreen> {
  String? _customerId;
  String? _productId;
  String _condition = 'resalable';
  final _quantity = TextEditingController(text: '1');
  final _reason = TextEditingController();
  final _notes = TextEditingController();
  final _items = <Map<String, dynamic>>[];
  bool _saving = false;

  Map<String, dynamic>? _find(List<Map<String, dynamic>> rows, String? id) {
    if (id == null) return null;
    for (final row in rows) {
      if (row['id']?.toString() == id) return row;
    }
    return null;
  }

  void _addItem() {
    final product = _find(widget.products, _productId);
    final quantity = double.tryParse(_quantity.text.trim());

    if (product == null || quantity == null || quantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a product and valid quantity.')),
      );
      return;
    }

    final duplicate = _items.any(
      (item) =>
          item['product_id'] == product['id'] &&
          item['condition'] == _condition,
    );
    if (duplicate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('That product/condition is already added.'),
        ),
      );
      return;
    }

    setState(() {
      _items.add({
        'product_id': product['id'],
        'sku': product['sku'],
        'name': product['name'],
        'unit': product['unit'],
        'quantity': quantity,
        'condition': _condition,
        'reason': _reason.text.trim().isEmpty ? null : _reason.text.trim(),
      });
      _productId = null;
      _quantity.text = '1';
      _reason.clear();
    });
  }

  Future<void> _save() async {
    final tenantId = context.read<AppState>().session?.tenantId;
    final customer = _find(widget.customers, _customerId);

    if (tenantId == null || customer == null || _items.isEmpty || _saving) {
      return;
    }

    setState(() => _saving = true);

    try {
      await context.read<StockRepository>().createReturnOffline(
        tenantId: tenantId,
        customer: customer,
        items: _items,
        notes: _notes.text,
      );

      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Bad state: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _quantity.dispose();
    _reason.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New customer return')),
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
            onChanged: (value) => setState(() => _customerId = value),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _productId,
            decoration: const InputDecoration(labelText: 'Product'),
            items: widget.products
                .map(
                  (product) => DropdownMenuItem(
                    value: product['id'].toString(),
                    child: Text(product['name']?.toString() ?? 'Product'),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => _productId = value),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _quantity,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Quantity'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _condition,
                  decoration: const InputDecoration(labelText: 'Condition'),
                  items: const [
                    DropdownMenuItem(
                      value: 'resalable',
                      child: Text('Resalable'),
                    ),
                    DropdownMenuItem(value: 'damaged', child: Text('Damaged')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _condition = value);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            decoration: const InputDecoration(labelText: 'Reason (optional)'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _addItem,
            icon: const Icon(Icons.add),
            label: const Text('Add returned item'),
          ),
          const SizedBox(height: 12),
          ..._items.asMap().entries.map(
            (entry) => Card(
              child: ListTile(
                title: Text(entry.value['name']?.toString() ?? 'Product'),
                subtitle: Text(
                  '${entry.value['quantity']} · ${entry.value['condition']}',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => setState(() => _items.removeAt(entry.key)),
                ),
              ),
            ),
          ),
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save return'),
          ),
        ],
      ),
    );
  }
}
