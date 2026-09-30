import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/expense_controller.dart';
import 'fuel_create_screen.dart';
import 'sync_refresh.dart';

class FuelScreen extends StatelessWidget {
  const FuelScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ExpenseController>();
    final entries = state.expenses
        .where((row) => row['category']?.toString() == 'fuel')
        .toList();

    final liters = entries.fold<double>(
      0,
      (sum, row) => sum + _number(row['fuel_liters']),
    );
    final costs = <String, double>{};
    for (final row in entries) {
      final currency = row['currency']?.toString() ?? 'AFN';
      costs[currency] = (costs[currency] ?? 0) + _number(row['amount']);
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => syncAndReload(context, triggerSource: 'pull:fuel'),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            Row(
              children: [
                Expanded(
                  child: _SummaryCard(
                    label: 'Fuel entries',
                    value: entries.length.toString(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SummaryCard(
                    label: 'Total liters',
                    value: liters.toStringAsFixed(2),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _SummaryCard(
              label: 'Total cost',
              value: costs.isEmpty
                  ? '—'
                  : costs.entries
                        .map((e) => '${e.value.toStringAsFixed(2)} ${e.key}')
                        .join(' · '),
            ),
            const SizedBox(height: 16),
            if (entries.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(Icons.local_gas_station_outlined, size: 48),
                      SizedBox(height: 10),
                      Text('No fuel entries yet.'),
                      SizedBox(height: 4),
                      Text(
                        'Add the first refueling with vehicle, odometer, GPS and receipt evidence.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else
              ...entries.map((row) {
                final uploaded =
                    row['receipt_uploaded'] == 1 ||
                    row['receipt_uploaded'] == true;
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.local_gas_station_outlined),
                    title: Text(
                      row['vehicle_reference']?.toString().isNotEmpty == true
                          ? row['vehicle_reference'].toString()
                          : 'Vehicle not recorded',
                    ),
                    subtitle: Text(
                      [
                        '${_number(row['fuel_liters']).toStringAsFixed(2)} L',
                        row['merchant']?.toString() ?? 'Fuel station',
                        '${row['odometer_km'] ?? '—'} km',
                        row['full_tank'] == 1 ? 'Full tank' : 'Partial fill',
                        uploaded ? 'Receipt synced' : 'Receipt pending',
                      ].join(' · '),
                    ),
                    trailing: Text(
                      '${_number(row['amount']).toStringAsFixed(2)} '
                      '${row['currency'] ?? 'AFN'}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: state.busy
            ? null
            : () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FuelCreateScreen()),
              ),
        icon: const Icon(Icons.add),
        label: const Text('Fuel'),
      ),
    );
  }

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 5),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
