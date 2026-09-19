import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/collection_controller.dart';

class CollectionCreateScreen extends StatefulWidget {
  const CollectionCreateScreen({
    required this.customers,
    this.initialCustomerId,
    this.visitUuid,
    super.key,
  });

  final List<Map<String, dynamic>> customers;
  final String? initialCustomerId;
  final String? visitUuid;

  @override
  State<CollectionCreateScreen> createState() => _CollectionCreateScreenState();
}

class _CollectionCreateScreenState extends State<CollectionCreateScreen> {
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _notes = TextEditingController();

  String? _customerId;
  String _currency = 'AFN';
  String _paymentMethod = 'cash';
  bool _saving = false;

  static const _methods = <String, String>{
    'cash': 'Cash',
    'bank_transfer': 'Bank transfer',
    'cheque': 'Cheque',
    'card': 'Card',
    'mobile_money': 'Mobile money',
    'other': 'Other',
  };

  @override
  void initState() {
    super.initState();
    _customerId = widget.initialCustomerId;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _useFirstBalanceCurrency(),
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  Map<String, dynamic>? get _customer {
    for (final row in widget.customers) {
      if (row['id']?.toString() == _customerId) return row;
    }
    return null;
  }

  List<Map<String, dynamic>> _balances(BuildContext context) {
    final id = _customerId;
    if (id == null) return const [];

    return context.read<CollectionController>().balancesForCustomer(id);
  }

  void _useFirstBalanceCurrency() {
    if (!mounted) return;
    final rows = _balances(context);
    if (rows.isNotEmpty) {
      setState(() => _currency = rows.first['currency']?.toString() ?? 'AFN');
    }
  }

  Future<void> _save() async {
    final customer = _customer;
    if (customer == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Select a customer.')));
      return;
    }

    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid collection amount.')),
      );
      return;
    }

    if (_paymentMethod != 'cash' && _reference.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reference number is required for non-cash payments.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    final controller = context.read<CollectionController>();

    await controller.create(
      customer: customer,
      currency: _currency,
      amount: amount,
      paymentMethod: _paymentMethod,
      referenceNumber: _reference.text,
      visitUuid: widget.visitUuid,
      notes: _notes.text,
    );

    if (!mounted) return;
    setState(() => _saving = false);

    if (controller.message == 'Collection saved locally.') {
      Navigator.pop(context);
    } else if (controller.message != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(controller.message!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final balances = _balances(context);
    Map<String, dynamic>? selectedBalance;
    for (final row in balances) {
      if (row['currency']?.toString() == _currency) {
        selectedBalance = row;
        break;
      }
    }

    final availableCurrencies = balances
        .map((row) => row['currency']?.toString())
        .whereType<String>()
        .toSet()
        .toList();

    if (!availableCurrencies.contains(_currency)) {
      availableCurrencies.add(_currency);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('New collection')),
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
                ? (value) {
                    setState(() {
                      _customerId = value;
                      _currency = 'AFN';
                    });
                    _useFirstBalanceCurrency();
                  }
                : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _currency,
            decoration: const InputDecoration(labelText: 'Currency'),
            items: availableCurrencies
                .map(
                  (currency) =>
                      DropdownMenuItem(value: currency, child: Text(currency)),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _currency = value);
            },
          ),
          if (selectedBalance != null) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Cached customer balance',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Outstanding: ${selectedBalance['outstanding_balance']} $_currency",
                    ),
                    Text(
                      "Pending collections: ${selectedBalance['pending_collections']} $_currency",
                    ),
                    Text(
                      "Available to collect: ${selectedBalance['available_to_collect'] ?? selectedBalance['outstanding_balance']} $_currency",
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  'No cached receivable balance is available. The collection can still be saved offline and will be reviewed by the server on sync.',
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Amount'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _paymentMethod,
            decoration: const InputDecoration(labelText: 'Payment method'),
            items: _methods.entries
                .map(
                  (entry) => DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _paymentMethod = value);
            },
          ),
          if (_paymentMethod != 'cash') ...[
            const SizedBox(height: 12),
            TextField(
              controller: _reference,
              decoration: const InputDecoration(labelText: 'Reference number'),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              alignLabelWithHint: true,
            ),
          ),
          if (widget.visitUuid != null) ...[
            const SizedBox(height: 12),
            const Text(
              'This collection will be linked to the current customer visit.',
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.payments_outlined),
            label: Text(_saving ? 'Saving…' : 'Save collection'),
          ),
        ],
      ),
    );
  }
}
