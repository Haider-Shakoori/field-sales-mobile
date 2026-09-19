import 'package:flutter/material.dart';

class CollectionDetailScreen extends StatelessWidget {
  const CollectionDetailScreen({required this.collection, super.key});

  final Map<String, dynamic> collection;

  @override
  Widget build(BuildContext context) {
    final flagged = collection['overpayment_flag'] == 1;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          collection['receipt_number']?.toString() ?? 'Collection receipt',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Collection receipt',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    collection['receipt_number']?.toString() ??
                        'Offline receipt',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "${collection['amount']} ${collection['currency']}",
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "Customer: ${collection['customer_name'] ?? 'Customer'}",
                  ),
                  Text(
                    "Payment: ${(collection['payment_method'] ?? 'cash').toString().replaceAll('_', ' ')}",
                  ),
                  Text("Status: ${collection['status'] ?? 'pending'}"),
                  Text("Collected: ${collection['collected_at'] ?? '—'}"),
                  if (collection['reference_number'] != null)
                    Text("Reference: ${collection['reference_number']}"),
                  if (collection['visit_uuid'] != null)
                    Text("Visit: ${collection['visit_uuid']}"),
                  if (collection['notes'] != null)
                    Text("Notes: ${collection['notes']}"),
                  if (collection['status_note'] != null)
                    Text("Status note: ${collection['status_note']}"),
                  if (collection['sync_status'] != 'synced')
                    Text(
                      "Sync: ${collection['sync_status']}",
                      style: TextStyle(color: Colors.orange.shade700),
                    ),
                  if (collection['last_error'] != null)
                    Text(
                      collection['last_error'].toString(),
                      style: const TextStyle(color: Colors.red),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: const Text('Balance at capture'),
              subtitle: Text(
                "${collection['balance_before']} ${collection['currency']}",
              ),
            ),
          ),
          if (flagged) ...[
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.warning_amber_outlined),
                title: const Text('Requires review'),
                subtitle: const Text(
                  'This amount was above the cached outstanding balance at capture time. It cannot be verified above the authoritative server balance.',
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: const Text('GPS evidence'),
              subtitle: Text(
                "${collection['latitude']}, ${collection['longitude']} · ±${collection['accuracy']} m"
                "${collection['distance_meters'] == null ? '' : ' · customer ${collection['distance_meters']} m'}"
                "${collection['within_geofence'] == null
                    ? ''
                    : collection['within_geofence'] == 1
                    ? ' · inside geofence'
                    : ' · outside geofence'}",
              ),
            ),
          ),
        ],
      ),
    );
  }
}
