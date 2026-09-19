import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/master_data_controller.dart';

class CustomersScreen extends StatelessWidget {
  const CustomersScreen({super.key});

  Future<void> _create(BuildContext context) async {
    final name = TextEditingController();
    final code = TextEditingController();
    final phone = TextEditingController();
    final address = TextEditingController();

    final save =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('New customer'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Customer name',
                    ),
                  ),
                  TextField(
                    controller: code,
                    decoration: const InputDecoration(
                      labelText: 'Code (optional)',
                    ),
                  ),
                  TextField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Phone'),
                  ),
                  TextField(
                    controller: address,
                    decoration: const InputDecoration(labelText: 'Address'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (name.text.trim().isNotEmpty) {
                    Navigator.pop(dialogContext, true);
                  }
                },
                child: const Text('Save offline'),
              ),
            ],
          ),
        ) ??
        false;

    if (!save || !context.mounted) {
      return;
    }

    await context.read<MasterDataController>().createCustomer(
      name: name.text,
      code: code.text,
      phone: phone.text,
      address: address.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<MasterDataController>();
    final rows = [...state.customers]
      ..sort(
        (a, b) => (a['name'] ?? '').toString().compareTo(
          (b['name'] ?? '').toString(),
        ),
      );

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => state.sync(),
        child: rows.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 180),
                  Icon(Icons.storefront_outlined, size: 48),
                  SizedBox(height: 12),
                  Center(
                    child: Text('No customers cached yet. Pull down to sync.'),
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, index) {
                  final customer = rows[index];
                  final offline = customer['offline_uuid'] != null;

                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          (customer['name'] ?? '?')
                              .toString()
                              .characters
                              .first
                              .toUpperCase(),
                        ),
                      ),
                      title: Text(customer['name']?.toString() ?? 'Customer'),
                      subtitle: Text(
                        [
                              customer['code'],
                              customer['phone'],
                              if (offline) 'Offline-created',
                            ]
                            .where(
                              (value) =>
                                  value != null &&
                                  value.toString().trim().isNotEmpty,
                            )
                            .join(' · '),
                      ),
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Customer'),
      ),
    );
  }
}
