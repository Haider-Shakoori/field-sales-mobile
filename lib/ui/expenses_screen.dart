import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/expense_controller.dart';
import 'expense_create_screen.dart';
import 'sync_refresh.dart';

class ExpensesScreen extends StatelessWidget {
  const ExpensesScreen({super.key});

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

  void _showDetail(BuildContext context, Map<String, dynamic> expense) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                expense['expense_number']?.toString() ?? 'Expense',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                "${expense['amount']} ${expense['currency']}",
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                "Category: ${_label(expense['category']?.toString() ?? 'other')}",
              ),
              Text(
                "Status: ${_label(expense['status']?.toString() ?? 'pending')}",
              ),
              Text("Spent: ${expense['spent_at'] ?? '—'}"),
              if (expense['category'] == 'fuel') ...[
                if (expense['fuel_liters'] != null)
                  Text("Fuel: ${expense['fuel_liters']} L"),
                if (expense['fuel_unit_price'] != null)
                  Text(
                    "Unit price: ${expense['fuel_unit_price']} ${expense['currency']}",
                  ),
                if (expense['odometer_km'] != null)
                  Text("Odometer: ${expense['odometer_km']} km"),
              ],
              if (expense['merchant'] != null)
                Text("Merchant: ${expense['merchant']}"),
              if (expense['reference_number'] != null)
                Text("Reference: ${expense['reference_number']}"),
              if (expense['notes'] != null) Text("Notes: ${expense['notes']}"),
              if (expense['review_note'] != null)
                Text("Review note: ${expense['review_note']}"),
              const SizedBox(height: 12),
              Text(
                "GPS: ${expense['latitude']}, ${expense['longitude']} · ±${expense['accuracy']} m",
              ),
              if (expense['sync_status'] != 'synced') ...[
                const SizedBox(height: 8),
                Text(
                  "Sync: ${expense['sync_status']}",
                  style: TextStyle(color: Colors.orange.shade700),
                ),
              ],
              if (expense['last_error'] != null) ...[
                const SizedBox(height: 8),
                Text(
                  expense['last_error'].toString(),
                  style: const TextStyle(color: Colors.red),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ExpenseController>();

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => syncAndReload(context, triggerSource: 'pull:expenses'),
        child: state.expenses.isEmpty
            ? ListView(
                padding: const EdgeInsets.all(20),
                children: const [
                  SizedBox(height: 140),
                  Icon(Icons.receipt_long_outlined, size: 52),
                  SizedBox(height: 12),
                  Center(child: Text('No expenses recorded yet.')),
                  SizedBox(height: 6),
                  Center(
                    child: Text(
                      'Expense claims are saved locally first and can sync when connectivity returns.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                itemCount: state.expenses.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, index) {
                  final expense = state.expenses[index];
                  final syncStatus =
                      expense['sync_status']?.toString() ?? 'pending';

                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: Text(
                        expense['expense_number']?.toString() ??
                            'Offline expense',
                      ),
                      subtitle: Text(
                        [
                          _label(expense['category']?.toString() ?? 'other'),
                          _label(expense['status']?.toString() ?? 'pending'),
                          if (syncStatus != 'synced') 'Sync: $syncStatus',
                        ].join(' · '),
                      ),
                      trailing: Text(
                        "${expense['amount']} ${expense['currency']}",
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      onTap: () => _showDetail(context, expense),
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: state.busy
            ? null
            : () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ExpenseCreateScreen()),
              ),
        icon: const Icon(Icons.add),
        label: const Text('Expense'),
      ),
    );
  }
}
