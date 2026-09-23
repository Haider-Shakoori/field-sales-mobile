import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/inventory_controller.dart';
import 'return_create_screen.dart';

class ReturnsScreen extends StatelessWidget {
  const ReturnsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<InventoryController>();

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => state.sync(),
        child: state.returns.isEmpty
            ? ListView(
                padding: const EdgeInsets.all(24),
                children: const [
                  SizedBox(height: 120),
                  Icon(Icons.assignment_return_outlined, size: 52),
                  SizedBox(height: 12),
                  Center(child: Text('No customer returns recorded yet.')),
                  SizedBox(height: 6),
                  Center(
                    child: Text(
                      'Returns are saved locally first and synchronize when '
                      'connectivity is available.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: state.returns.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, index) {
                  final item = state.returns[index];
                  final status = item['status']?.toString() ?? 'pending';
                  final sync = item['sync_status']?.toString() ?? 'pending';

                  return Card(
                    child: ListTile(
                      leading: Icon(
                        status == 'approved'
                            ? Icons.check_circle_outline
                            : status == 'rejected'
                            ? Icons.cancel_outlined
                            : Icons.schedule_outlined,
                      ),
                      title: Text(
                        item['return_number']?.toString().isNotEmpty == true
                            ? item['return_number'].toString()
                            : item['customer_name']?.toString() ?? 'Return',
                      ),
                      subtitle: Text(
                        '${item['customer_name'] ?? 'Customer'} · '
                        '${status.toUpperCase()}'
                        '${sync == 'synced' ? '' : ' · Sync: $sync'}',
                      ),
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: state.busy
            ? null
            : () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ReturnCreateScreen()),
                );
                if (context.mounted) {
                  await context.read<InventoryController>().reloadLocal();
                }
              },
        icon: const Icon(Icons.assignment_return_outlined),
        label: const Text('New return'),
      ),
    );
  }
}
