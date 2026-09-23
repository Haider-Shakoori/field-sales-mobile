import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/stock/stock_return_repository.dart';
import '../state/app_state.dart';
import 'sync_refresh.dart';

class StockScreen extends StatefulWidget {
  const StockScreen({super.key});

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  bool _loading = true;
  bool _enabled = false;
  List<Map<String, dynamic>> _rows = const [];

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    final tenantId = context.read<AppState>().session?.tenantId;
    if (tenantId == null) return;

    setState(() => _loading = true);
    final repo = context.read<StockReturnRepository>();
    final rows = await repo.stock(tenantId);
    final enabled = await repo.stockEnabled(tenantId);

    if (mounted) {
      setState(() {
        _rows = rows;
        _enabled = enabled;
        _loading = false;
      });
    }
  }

  Future<void> _refresh() async {
    await syncAndReload(context, triggerSource: 'pull:stock');
    await _load();
  }

  String _qty(dynamic value) {
    final number = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0;
    return number.toStringAsFixed(number % 1 == 0 ? 0 : 2);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_enabled) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: const [
            SizedBox(height: 120),
            Icon(Icons.inventory_2_outlined, size: 54),
            SizedBox(height: 14),
            Center(
              child: Text(
                'Salesman stock control is not enabled for this company.',
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: _rows.isEmpty
          ? ListView(
              padding: const EdgeInsets.all(24),
              children: const [
                SizedBox(height: 120),
                Icon(Icons.inventory_2_outlined, size: 54),
                SizedBox(height: 14),
                Center(
                  child: Text(
                    'No stock has been issued to you yet.',
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
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.inventory_2_outlined),
                    title: Text((row['name'] ?? 'Product').toString()),
                    subtitle: Text(
                      [
                        if ((row['sku'] ?? '').toString().isNotEmpty)
                          row['sku'].toString(),
                        (row['unit'] ?? 'pcs').toString(),
                      ].join(' · '),
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Sellable ${_qty(row['sellable_qty'])}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Damaged ${_qty(row['damaged_qty'])}',
                          style: TextStyle(color: Colors.orange.shade700),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
