import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/sync/sync_controller.dart';
import '../../core/sync/sync_status.dart';
import '../../l10n/app_l10n.dart';

/// Persistent bar showing network state, sync activity and queue counts.
/// Rendered at the bottom of the home shell per the Batch 6 roadmap
/// ("Visible offline / sync status indicator").
class SyncStatusIndicator extends StatelessWidget {
  const SyncStatusIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncController>();
    final l10n = AppL10n.of(context);
    final scheme = Theme.of(context).colorScheme;

    final (label, icon, color) = _describe(sync, l10n, scheme);
    final counts = sync.counts;

    return Material(
      color: scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const Spacer(),
            if (counts.pending > 0)
              _CountChip(
                count: counts.pending,
                label: l10n.pending(counts.pending),
              ),
            if (counts.failed > 0)
              _CountChip(
                count: counts.failed,
                label: l10n.failed(counts.failed),
              ),
          ],
        ),
      ),
    );
  }

  (String, IconData, Color) _describe(
    SyncController sync,
    AppL10n l10n,
    ColorScheme scheme,
  ) {
    if (sync.syncing) {
      return (l10n.syncing, Icons.sync, scheme.primary);
    }
    return switch (sync.network) {
      NetworkState.online => (l10n.online, Icons.cloud_done, scheme.primary),
      NetworkState.limited => (
        l10n.limited,
        Icons.cloud_queue,
        scheme.tertiary,
      ),
      NetworkState.offline => (l10n.offline, Icons.cloud_off, scheme.error),
    };
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.count, required this.label});

  final int count;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label, style: Theme.of(context).textTheme.labelSmall),
      ),
    );
  }
}
