import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/master_data_controller.dart';

class SyncScreen extends StatelessWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<MasterDataController>();

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
                Text('Pending local changes: ${state.pending}'),
                const SizedBox(height: 6),
                Text(
                  state.lastSyncedAt == null
                      ? 'No online refresh in this app session yet.'
                      : 'Last refreshed: ${state.lastSyncedAt!.toLocal()}',
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: state.busy ? null : () => state.sync(),
                  icon: state.busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: Text(state.busy ? 'Syncing…' : 'Sync now'),
                ),
                if (state.message != null) ...[
                  const SizedBox(height: 12),
                  Text(state.message!),
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
              'New customers are saved locally before any upload attempt.',
            ),
          ),
        ),
      ],
    );
  }
}
