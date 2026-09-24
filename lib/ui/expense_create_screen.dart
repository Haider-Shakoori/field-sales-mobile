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
  final _fuelLiters = TextEditingController();
  final _fuelUnitPrice = TextEditingController();
  final _odometer = TextEditingController();
  final _notes = TextEditingController();

  String _category = ExpenseRepository.categories.first;
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _currency.dispose();
    _merchant.dispose();
    _reference.dispose();
    _fuelLiters.dispose();
    _fuelUnitPrice.dispose();
    _odometer.dispose();
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

    double? parseOptional(
      TextEditingController controller,
      String label, {
      bool allowZero = false,
    }) {
      final raw = controller.text.trim();
      if (raw.isEmpty) return null;

      final value = double.tryParse(raw);
      if (
        value == null ||
        (allowZero ? value < 0 : value <= 0)
      ) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Enter a valid $label.')),
        );
        throw const FormatException();
      }

      return value;
    }

    double? fuelLiters;
    double? fuelUnitPrice;
    double? odometerKm;

    if (_category == 'fuel') {
      try {
        fuelLiters = parseOptional(_fuelLiters, 'fuel quantity');
        fuelUnitPrice = parseOptional(_fuelUnitPrice, 'fuel unit price');
        odometerKm = parseOptional(
          _odometer,
          'odometer reading',
          allowZero: true,
        );
      } on FormatException {
        return;
      }
    }

    setState(() => _saving = true);
    final controller = context.read<ExpenseController>();

    await controller.create(
      category: _category,
      currency: _currency.text,
      amount: amount,
      fuelLiters: fuelLiters,
      fuelUnitPrice: fuelUnitPrice,
      odometerKm: odometerKm,
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
          if (_category == 'fuel') ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Fuel details',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _fuelLiters,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Liters (optional)',
                        helperText:
                            'Used for km/L fuel-efficiency reporting.',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _fuelUnitPrice,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Unit price (optional)',
                        helperText:
                            'Leave blank to derive it from amount ÷ liters.',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _odometer,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Odometer km (optional)',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
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
