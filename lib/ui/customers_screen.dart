import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/call_activity_controller.dart';
import '../state/master_data_controller.dart';
import 'sync_refresh.dart';
import 'call_history_screen.dart';
import 'customer_statement_screen.dart';
import 'customer_create_screen.dart';
import 'reorder_recommendations_screen.dart';

class CustomersScreen extends StatelessWidget {
  const CustomersScreen({super.key});

  static const callOutcomes = <String, String>{
    'answered': 'Answered',
    'no_answer': 'No answer',
    'busy': 'Busy',
    'call_back_later': 'Call back later',
    'order_discussion': 'Order discussion',
    'payment_follow_up': 'Payment follow-up',
    'other': 'Other',
  };

  Future<void> _create(BuildContext context) async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CustomerCreateScreen()),
    );

    if (created == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Customer saved with shop location.')),
      );
    }
  }

  Future<void> _edit(
    BuildContext context,
    Map<String, dynamic> customer,
  ) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CustomerCreateScreen(customer: customer),
      ),
    );

    if (updated == true && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Customer changes saved.')));
    }
  }

  Future<void> _callCustomer(
    BuildContext context,
    Map<String, dynamic> customer,
  ) async {
    final phone = customer['phone']?.toString().trim() ?? '';
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This customer has no phone number.')),
      );
      return;
    }

    final calledAt = DateTime.now().toUtc();
    final launched = await launchUrl(
      Uri(scheme: 'tel', path: phone),
      mode: LaunchMode.externalApplication,
    );

    if (!launched || !context.mounted) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The phone dialer could not be opened.'),
          ),
        );
      }
      return;
    }

    String? outcome;
    final notes = TextEditingController();

    final save =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, setState) => AlertDialog(
              title: const Text('Save call activity?'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: outcome,
                      hint: const Text('Outcome (optional)'),
                      decoration: const InputDecoration(labelText: 'Outcome'),
                      items: callOutcomes.entries
                          .map(
                            (entry) => DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() => outcome = value),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notes,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Notes (optional)',
                        alignLabelWithHint: true,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Skip'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Save offline'),
                ),
              ],
            ),
          ),
        ) ??
        false;

    if (!save || !context.mounted) {
      return;
    }

    await context.read<CallActivityController>().record(
      customer: customer,
      phoneNumber: phone,
      calledAt: calledAt,
      outcome: outcome,
      notes: notes.text,
    );
  }

  Future<void> _messageCustomer(
    BuildContext context,
    Map<String, dynamic> customer,
  ) async {
    final phone = customer['phone']?.toString().trim().isNotEmpty == true
        ? customer['phone'].toString().trim()
        : customer['alternate_phone']?.toString().trim() ?? '';

    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This customer has no phone number.')),
      );
      return;
    }

    var channel = 'whatsapp';
    final message = TextEditingController(
      text: 'Hello ${(customer['name'] ?? 'there').toString()}, ',
    );

    final send =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, setState) => AlertDialog(
              title: const Text('Message customer'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: channel,
                      decoration: const InputDecoration(labelText: 'Channel'),
                      items: const [
                        DropdownMenuItem(
                          value: 'whatsapp',
                          child: Text('WhatsApp'),
                        ),
                        DropdownMenuItem(value: 'sms', child: Text('SMS')),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => channel = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: message,
                      maxLines: 5,
                      maxLength: 1600,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Message',
                        alignLabelWithHint: true,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    if (message.text.trim().isNotEmpty) {
                      Navigator.pop(dialogContext, true);
                    }
                  },
                  child: const Text('Open app'),
                ),
              ],
            ),
          ),
        ) ??
        false;

    if (!send || !context.mounted) return;

    final body = message.text.trim();
    final Uri uri;

    if (channel == 'whatsapp') {
      final digits = phone.replaceAll(RegExp(r'\D'), '');
      if (digits.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The customer phone number is invalid.'),
          ),
        );
        return;
      }

      uri = Uri.https('wa.me', '/$digits', {'text': body});
    } else {
      uri = Uri(scheme: 'sms', path: phone, queryParameters: {'body': body});
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            channel == 'whatsapp'
                ? 'WhatsApp could not be opened.'
                : 'The SMS app could not be opened.',
          ),
        ),
      );
    }
  }

  void _showHistory(BuildContext context, Map<String, dynamic> customer) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CallHistoryScreen(
          customerId: customer['id'].toString(),
          customerName: (customer['name'] ?? 'Customer').toString(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<MasterDataController>();
    final callState = context.watch<CallActivityController>();
    final rows = [...state.customers]
      ..sort(
        (a, b) => (a['name'] ?? '').toString().compareTo(
          (b['name'] ?? '').toString(),
        ),
      );

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () =>
            syncAndReload(context, triggerSource: 'pull:customers'),
        child: rows.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 180),
                  Icon(Icons.storefront_outlined, size: 48),
                  SizedBox(height: 12),
                  Center(
                    child: Text('No customers cached yet. Pull down to sync.'),
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                itemCount: rows.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, index) {
                  final customer = rows[index];
                  final offline = customer['offline_uuid'] != null;
                  final phone = customer['phone']?.toString().trim() ?? '';

                  final rawName =
                      customer['name']?.toString().trim() ?? '';
                  final displayName =
                      rawName.isEmpty ? 'Customer' : rawName;
                  final details = [
                    customer['code'],
                    customer['phone'],
                    if (offline) 'Offline-created',
                  ]
                      .where(
                        (value) =>
                            value != null &&
                            value.toString().trim().isNotEmpty,
                      )
                      .map((value) => value.toString().trim())
                      .join(' · ');

                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => _edit(context, customer),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 10, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 24,
                                  child: Text(
                                    displayName.characters.first.toUpperCase(),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        displayName,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      if (details.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          details,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodyMedium,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Padding(
                                  padding: EdgeInsets.only(top: 8),
                                  child: Icon(Icons.chevron_right),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            const Divider(height: 1),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                IconButton(
                                  tooltip: 'Reorder recommendations',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          ReorderRecommendationsScreen(
                                            customer: customer,
                                            products: state.products,
                                          ),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.auto_awesome_outlined,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Statement',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          CustomerStatementScreen(
                                            customer: customer,
                                          ),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.account_balance_wallet_outlined,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Call history',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () =>
                                      _showHistory(context, customer),
                                  icon: const Icon(Icons.history),
                                ),
                                IconButton(
                                  tooltip:
                                      phone.isEmpty ? 'No phone' : 'Message',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: phone.isEmpty
                                      ? null
                                      : () => _messageCustomer(
                                            context,
                                            customer,
                                          ),
                                  icon: const Icon(Icons.chat_bubble_outline),
                                ),
                                IconButton(
                                  tooltip: phone.isEmpty ? 'No phone' : 'Call',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: phone.isEmpty || callState.busy
                                      ? null
                                      : () =>
                                          _callCustomer(context, customer),
                                  icon: const Icon(Icons.call_outlined),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Customer'),
      ),
    );
  }
}
