import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/call_activity_controller.dart';
import '../state/collection_controller.dart';
import '../state/master_data_controller.dart';
import '../state/order_controller.dart';
import '../state/visit_controller.dart';

class SyncScreen extends StatelessWidget {
  const SyncScreen({super.key});

  Future<void> _syncAll(BuildContext context) async {
    await context.read<MasterDataController>().sync();
    if (context.mounted) {
      await context.read<VisitController>().sync();
      if (context.mounted) {
        await context.read<CallActivityController>().sync();
        if (context.mounted) {
          await context.read<OrderController>().sync();
          if (context.mounted) {
            await context.read<CollectionController>().sync();
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<MasterDataController>();
    final visits = context.watch<VisitController>();
    final calls = context.watch<CallActivityController>();
    final orders = context.watch<OrderController>();
    final collections = context.watch<CollectionController>();
    final pending =
        state.pending +
        visits.pending +
        calls.pending +
        orders.pending +
        collections.pending;
    final busy =
        state.busy ||
        visits.busy ||
        calls.busy ||
        orders.busy ||
        collections.busy;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Offline sync',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                ),
                const SizedBox(height: 12),
                Text('Pending local changes: $pending'),
                const SizedBox(height: 6),
                Text(
                  state.lastSyncedAt == null
                      ? 'No online refresh in this app session yet.'
                      : 'Last refreshed: ${state.lastSyncedAt!.toLocal()}',
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: busy ? null : () => _syncAll(context),
                  icon: busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: Text(busy ? 'Syncing…' : 'Sync now'),
                ),
                if (state.message != null) ...[
                  const SizedBox(height: 12),
                  Text(state.message!),
                ],
                if (visits.message != null) ...[
                  const SizedBox(height: 8),
                  Text(visits.message!),
                ],
                if (calls.message != null) ...[
                  const SizedBox(height: 8),
                  Text(calls.message!),
                ],
                if (orders.message != null) ...[
                  const SizedBox(height: 8),
                  Text(orders.message!),
                ],
                if (collections.message != null) ...[
                  const SizedBox(height: 8),
                  Text(collections.message!),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Card(
          child: ListTile(
            leading: Icon(Icons.cloud_off_outlined),
            title: Text('Local-first by design'),
            subtitle: Text(
              'Cached master data stays available without internet. '
              'Customers, visits, photos, calls, orders and collections are saved locally before upload.',
            ),
          ),
        ),
      ],
    );
  }
}
