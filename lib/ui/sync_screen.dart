import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/call_activity_controller.dart';
import '../state/collection_controller.dart';
import '../state/expense_controller.dart';
import '../state/master_data_controller.dart';
import '../state/order_controller.dart';
import '../state/sync_controller.dart';
import '../state/target_controller.dart';
import '../state/visit_controller.dart';

class SyncScreen extends StatelessWidget {
  const SyncScreen({super.key});

  Future<void> _reloadLocalViews(BuildContext context) async {
    await context.read<MasterDataController>().reloadLocal();
    if (!context.mounted) return;
    await context.read<VisitController>().reloadLocal();
    if (!context.mounted) return;
    await context.read<CallActivityController>().reloadLocal();
    if (!context.mounted) return;
    await context.read<OrderController>().reloadLocal();
    if (!context.mounted) return;
    await context.read<CollectionController>().reloadLocal();
    if (!context.mounted) return;
    await context.read<ExpenseController>().reloadLocal();
    if (!context.mounted) return;
    await context.read<TargetController>().reloadLocal();
    if (!context.mounted) return;
    await context.read<SyncController>().refreshHealth();
  }

  Future<void> _syncAll(BuildContext context) async {
    await context.read<SyncController>().run();
    if (context.mounted) {
      await _reloadLocalViews(context);
    }
  }

  Future<void> _retryFailures(BuildContext context) async {
    await context.read<SyncController>().retryFailures();
    if (context.mounted) {
      await _reloadLocalViews(context);
    }
  }

  String _entityLabel(String value) {
    return value
        .split('_')
        .map(
          (part) => part.isEmpty
              ? part
              : '${part[0].toUpperCase()}${part.substring(1)}',
        )
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final master = context.watch<MasterDataController>();
    final visits = context.watch<VisitController>();
    final calls = context.watch<CallActivityController>();
    final orders = context.watch<OrderController>();
    final collections = context.watch<CollectionController>();
    final expenses = context.watch<ExpenseController>();
    final targets = context.watch<TargetController>();
    final sync = context.watch<SyncController>();

    final pending =
        master.pending +
        visits.pending +
        calls.pending +
        orders.pending +
        collections.pending +
        expenses.pending +
        sync.infrastructurePending;

    final busy =
        sync.busy ||
        master.busy ||
        visits.busy ||
        calls.busy ||
        orders.busy ||
        collections.busy ||
        expenses.busy ||
        targets.busy;

    final latestStatus = sync.latestCycle?['status']?.toString();
    final latestCompleted = sync.latestCycle?['completed_at']?.toString();

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
                Text('Waiting for retry: ${sync.waitingCount}'),
                Text('Blocked items: ${sync.blockedCount}'),
                if (latestStatus != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Last cycle: $latestStatus'
                    '${latestCompleted == null ? '' : ' · $latestCompleted'}',
                  ),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
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
                    if (sync.issueCount > 0)
                      OutlinedButton.icon(
                        onPressed: busy ? null : () => _retryFailures(context),
                        icon: const Icon(Icons.restart_alt),
                        label: const Text('Retry failures now'),
                      ),
                  ],
                ),
                if (sync.message != null) ...[
                  const SizedBox(height: 12),
                  Text(sync.message!),
                ],
              ],
            ),
          ),
        ),
        if (sync.issues.isNotEmpty) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Sync issues',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                  ),
                  const SizedBox(height: 10),
                  ...sync.issues.take(8).map((issue) {
                    final type = _entityLabel(
                      issue['entity_type']?.toString() ?? 'item',
                    );
                    final status = issue['status']?.toString() ?? 'retry_wait';
                    final attempts = issue['attempts']?.toString() ?? '0';
                    final next = issue['next_retry_at']?.toString();

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '$type · $status · attempt $attempts',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Icon(
                                status == 'blocked'
                                    ? Icons.error_outline
                                    : Icons.schedule,
                                size: 20,
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            issue['error_message']?.toString() ??
                                'Sync failed.',
                          ),
                          if (next != null)
                            Text(
                              'Next automatic retry: $next',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                        ],
                      ),
                    );
                  }),
                  if (sync.issues.length > 8)
                    Text(
                      '+${sync.issues.length - 8} more issues',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        const Card(
          child: ListTile(
            leading: Icon(Icons.cloud_off_outlined),
            title: Text('Local-first by design'),
            subtitle: Text(
              'Offline changes are preserved locally. Sync runs in dependency '
              'order, transient failures use backoff, permanent validation '
              'failures are blocked for review, and repeated UUID requests '
              'remain idempotent.',
            ),
          ),
        ),
      ],
    );
  }
}
