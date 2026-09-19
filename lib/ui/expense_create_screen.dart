import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/expenses/expense_repository.dart';
import '../state/expense_controller.dart';

class ExpenseCreateScreen extends StatefulWidget {
  const ExpenseCreateScreen({super.key});

  @override
  State<ExpenseCreateScreen> createState() => _ExpenseCreateScreenState();
}

class _ExpenseCreateScreenState extends State<ExpenseCreateScreen> {
  final _amount = TextEditingController();
  final _currency = TextEditingController(text: 'AFN');
  final _merchant = TextEditingController();
  final _reference = TextEditingController();
  final _notes = TextEditingController();

  String _category = ExpenseRepository.categories.first;
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _currency.dispose();
    _merchant.dispose();
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid expense amount.')),
      );
      return;
    }

    setState(() => _saving = true);
    final controller = context.read<ExpenseController>();

    await controller.create(
      category: _category,
      currency: _currency.text,
      amount: amount,
      merchant: _merchant.text,
      referenceNumber: _reference.text,
      notes: _notes.text,
    );

    if (!mounted) return;
    setState(() => _saving = false);

    if (controller.message == 'Expense saved locally.') {
      Navigator.pop(context);
    } else if (controller.message != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(controller.message!)));
    }
  }

  String _label(String value) {
    return value
        .split('_')
        .map(
          (word) => word.isEmpty
              ? word
              : '${word[0].toUpperCase()}${word.substring(1)}',
        )
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New expense')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: ExpenseRepository.categories
                .map(
                  (value) => DropdownMenuItem(
                    value: value,
                    child: Text(_label(value)),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _category = value);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Amount'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _currency,
            textCapitalization: TextCapitalization.characters,
            maxLength: 3,
            decoration: const InputDecoration(
              labelText: 'Currency',
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _merchant,
            decoration: const InputDecoration(
              labelText: 'Merchant / supplier (optional)',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reference,
            decoration: const InputDecoration(
              labelText: 'Reference number (optional)',
            ),
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
          const SizedBox(height: 12),
          const Card(
            child: ListTile(
              leading: Icon(Icons.location_on_outlined),
              title: Text('GPS evidence'),
              subtitle: Text(
                'Your current location is captured with the expense claim. '
                'The claim is stored locally first and can sync later.',
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.receipt_long_outlined),
            label: Text(_saving ? 'Saving…' : 'Save expense'),
          ),
        ],
      ),
    );
  }
}
