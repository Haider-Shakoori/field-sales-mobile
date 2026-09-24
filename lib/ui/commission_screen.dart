import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/insights/sales_insights_repository.dart';
import '../state/app_state.dart';

class CommissionScreen extends StatefulWidget {
  const CommissionScreen({super.key});
  @override
  State<CommissionScreen> createState() => _CommissionScreenState();
}

class _CommissionScreenState extends State<CommissionScreen> {
  Future<Map<String, dynamic>>? _future;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<Map<String, dynamic>> _load() {
    final tenant = context.read<AppState>().session?.tenantId;
    if (tenant == null) return Future.value({'summary': {}, 'earnings': []});
    return context.read<SalesInsightsRepository>().commissions(tenant);
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: _refresh,
    child: FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data ?? const {};
        final summary = data['summary'] is Map
            ? Map<String, dynamic>.from(data['summary'] as Map)
            : <String, dynamic>{};
        final earnings = (data['earnings'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(child: Icon(Icons.payments_outlined)),
                  title: Text('My commissions'),
                  subtitle: Text(
                    'Auditable earnings from approved sales and verified collections. Cached for offline viewing.',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (summary.isNotEmpty)
              ...summary.entries.map((entry) {
                final row = entry.value is Map
                    ? Map<String, dynamic>.from(entry.value as Map)
                    : <String, dynamic>{};
                return Card(
                  child: ListTile(
                    title: Text(entry.key),
                    subtitle: Text(
                      'Earned: ${row['earned'] ?? 0} · Paid: ${row['paid'] ?? 0}',
                    ),
                  ),
                );
              }),
            const SizedBox(height: 10),
            if (earnings.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(30),
                  child: Text('No commission earnings yet.'),
                ),
              )
            else
              ...earnings.map(
                (row) => Card(
                  child: ListTile(
                    title: Text(row['plan']?.toString() ?? 'Commission'),
                    subtitle: Text(
                      '${row['source_type']} · ${row['currency']} ${row['source_amount']} @ ${row['rate_percent']}%',
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${row['currency']} ${row['commission_amount']}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(row['status']?.toString() ?? 'earned'),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}