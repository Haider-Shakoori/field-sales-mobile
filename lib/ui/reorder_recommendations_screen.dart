import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/insights/sales_insights_repository.dart';
import '../state/app_state.dart';

class ReorderRecommendationsScreen extends StatefulWidget {
  const ReorderRecommendationsScreen({super.key});
  @override
  State<ReorderRecommendationsScreen> createState() =>
      _ReorderRecommendationsScreenState();
}

class _ReorderRecommendationsScreenState
    extends State<ReorderRecommendationsScreen> {
  Future<List<Map<String, dynamic>>>? _future;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<List<Map<String, dynamic>>> _load() {
    final tenant = context.read<AppState>().session?.tenantId;
    if (tenant == null) return Future.value(const []);
    return context.read<SalesInsightsRepository>().reorderRecommendations(
      tenant,
    );
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: _refresh,
    child: FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        final rows = snapshot.data ?? const [];
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(child: Icon(Icons.repeat)),
                  title: Text('Reorder recommendations'),
                  subtitle: Text(
                    'Suggestions are based on actual customer purchase cadence and cached for offline use.',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (snapshot.connectionState == ConnectionState.waiting &&
                rows.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(30),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (rows.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(30),
                  child: Text('No reorder opportunities are due.'),
                ),
              )
            else
              ...rows.map(
                (row) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    child: ListTile(
                      leading: Icon(
                        row['priority'] == 'overdue'
                            ? Icons.priority_high
                            : Icons.schedule,
                      ),
                      title: Text(
                        '${row['customer_name']} · ${row['product_name']}',
                      ),
                      subtitle: Text(
                        '${row['reason']}\nSuggested qty: ${row['suggested_quantity']} · Confidence ${row['confidence']}%',
                      ),
                      isThreeLine: true,
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