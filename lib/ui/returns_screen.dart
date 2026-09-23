import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/stock/stock_return_repository.dart';
import '../state/app_state.dart';
import '../state/master_data_controller.dart';
import 'return_create_screen.dart';
import 'sync_refresh.dart';

class ReturnsScreen extends StatefulWidget {
  const ReturnsScreen({super.key});

  @override
  State<ReturnsScreen> createState() => _ReturnsScreenState();
}

class _ReturnsScreenState extends State<ReturnsScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _rows = const [];

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    final tenantId = context.read<AppState>().session?.tenantId;
    if (tenantId == null) return;

    final rows = await context.read<StockReturnRepository>().history(tenantId);
    if (mounted) {
      setState(() {
        _rows = rows;
        _loading = false;
      });
    }
  }

  Future<void> _refresh() async {
    await syncAndReload(context, triggerSource: 'pull:returns');
    await _load();
  }

  Future<void> _create() async {
    final master = context.read<MasterDataController>();

    if (master.customers.isEmpty || master.products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sync customers and products before creating a return.',
          ),
        ),
      );
      return;
    }

    final saved = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const ReturnCreateScreen()));

    if (saved == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: _rows.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.all(24),
                      children: const [
                        SizedBox(height: 120),
                        Icon(Icons.assignment_return_outlined, size: 54),
                        SizedBox(height: 14),
                        Center(
                          child: Text(
                            'No customer returns recorded yet.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _rows.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, index) {
                        final row = _rows[index];
                        final items = (row['items'] as List? ?? const []);
                        final syncStatus = row['sync_status']?.toString() ?? '';

                        return Card(
                          child: ExpansionTile(
                            leading: const Icon(
                              Icons.assignment_return_outlined,
                            ),
                            title: Text(
                              row['return_number']?.toString() ??
                                  row['customer_name']?.toString() ??
                                  'Return',
                            ),
                            subtitle: Text(
                              [
                                row['customer_name']?.toString(),
                                row['status']?.toString(),
                                if (syncStatus != 'synced') 'sync: $syncStatus',
                              ].whereType<String>().join(' · '),
                            ),
                            children: [
                              for (final raw in items.whereType<Map>())
                                ListTile(
                                  dense: true,
                                  title: Text(
                                    (raw['name'] ?? 'Product').toString(),
                                  ),
                                  subtitle: Text(
                                    "${raw['condition'] ?? ''}"
                                    "${raw['reason'] == null ? '' : ' · ${raw['reason']}'}",
                                  ),
                                  trailing: Text(
                                    "${raw['quantity']} ${raw['unit'] ?? ''}",
                                  ),
                                ),
                              if (row['status_note'] != null)
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(
                                    "Review: ${row['status_note']}",
                                    style: TextStyle(
                                      color: Colors.orange.shade700,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('New return'),
      ),
    );
  }
}
