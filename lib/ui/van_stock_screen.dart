import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/inventory_controller.dart';

class VanStockScreen extends StatelessWidget {
  const VanStockScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<InventoryController>();

    return RefreshIndicator(
      onRefresh: () => state.sync(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Icon(
                    state.enabled
                        ? Icons.local_shipping_outlined
                        : Icons.inventory_2_outlined,
                    size: 34,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          state.enabled
                              ? 'Van stock control enabled'
                              : 'Van stock control disabled',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          state.enabled
                              ? 'Orders use your assigned vehicle stock.'
                              : 'Orders currently use the standard unrestricted flow.',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (state.message != null) ...[
            const SizedBox(height: 10),
            Text(state.message!),
          ],
          const SizedBox(height: 16),
          if (state.stock.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No van stock has been assigned yet. Pull to refresh after '
                  'a manager loads stock.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            ...state.stock.map((item) {
              final available =
                  (item['local_available_quantity'] as num?)?.toDouble() ?? 0;
              final serverAvailable =
                  (item['available_quantity'] as num?)?.toDouble() ?? 0;
              final pendingUse = (serverAvailable - available).clamp(
                0,
                double.infinity,
              );

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${item['sku'] ?? ''} · ${item['name'] ?? 'Product'}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        _quantityRow(
                          'Available offline',
                          available,
                          item['unit'],
                          bold: true,
                        ),
                        _quantityRow(
                          'Server available',
                          serverAvailable,
                          item['unit'],
                        ),
                        _quantityRow(
                          'Reserved on server',
                          (item['reserved_quantity'] as num?)?.toDouble() ?? 0,
                          item['unit'],
                        ),
                        if (pendingUse > 0)
                          _quantityRow(
                            'Queued offline orders',
                            pendingUse.toDouble(),
                            item['unit'],
                          ),
                        _quantityRow(
                          'Damaged',
                          (item['damaged_quantity'] as num?)?.toDouble() ?? 0,
                          item['unit'],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _quantityRow(
    String label,
    double value,
    dynamic unit, {
    bool bold = false,
  }) {
    final style = TextStyle(fontWeight: bold ? FontWeight.bold : null);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text('${value.toStringAsFixed(4)} ${unit ?? ''}', style: style),
        ],
      ),
    );
  }
}
