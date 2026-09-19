import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/call_activity_controller.dart';

class CallHistoryScreen extends StatelessWidget {
  const CallHistoryScreen({
    required this.customerId,
    required this.customerName,
    super.key,
  });

  final String customerId;
  final String customerName;

  static const outcomes = <String, String>{
    'answered': 'Answered',
    'no_answer': 'No answer',
    'busy': 'Busy',
    'call_back_later': 'Call back later',
    'order_discussion': 'Order discussion',
    'payment_follow_up': 'Payment follow-up',
    'other': 'Other',
  };

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CallActivityController>();
    final rows = state.activities
        .where((row) => row['customer_uuid']?.toString() == customerId)
        .toList();

    return Scaffold(
      appBar: AppBar(title: Text(customerName + ' · Calls')),
      body: RefreshIndicator(
        onRefresh: () => state.sync(),
        child: rows.isEmpty
            ? ListView(
                padding: const EdgeInsets.all(24),
                children: const [
                  SizedBox(height: 140),
                  Icon(Icons.call_outlined, size: 52),
                  SizedBox(height: 12),
                  Center(child: Text('No call activity recorded yet.')),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: rows.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, index) {
                  final row = rows[index];
                  final outcome = row['outcome']?.toString();

                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.call_outlined),
                      title: Text(
                        outcome == null
                            ? 'Outcome not recorded'
                            : outcomes[outcome] ?? outcome,
                      ),
                      subtitle: Text(
                        [
                              row['called_at']?.toString(),
                              row['phone_number']?.toString(),
                              row['notes']?.toString(),
                              if (row['sync_status'] != 'synced')
                                'Sync: ' + row['sync_status'].toString(),
                            ]
                            .where(
                              (value) =>
                                  value != null &&
                                  value.toString().trim().isNotEmpty,
                            )
                            .join('\n'),
                      ),
                      isThreeLine: true,
                    ),
                  );
                },
              ),
      ),
    );
  }
}
