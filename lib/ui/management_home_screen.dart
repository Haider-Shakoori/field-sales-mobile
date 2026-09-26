import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../state/management_controller.dart';

class ManagementHomeScreen extends StatelessWidget {
  const ManagementHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final state = context.watch<ManagementController>();
    final overview = state.overview;
    final summary = overview?['summary'] is Map
        ? Map<String, dynamic>.from(overview!['summary'] as Map)
        : const <String, dynamic>{};

    return RefreshIndicator(
      onRefresh: () => context.read<ManagementController>().refresh(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Good day, ${app.session?.name ?? ''}',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            _roleLabel(app.session?.role),
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 18),
          if (state.message != null)
            _MessageCard(message: state.message!)
          else if (overview == null && state.busy)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else ...[
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.55,
              children: [
                _MetricCard(
                  icon: Icons.groups_outlined,
                  label: 'Team',
                  value: '${summary['team_size'] ?? 0}',
                  detail: '${summary['working'] ?? 0} working',
                ),
                _MetricCard(
                  icon: Icons.storefront_outlined,
                  label: 'Visits',
                  value: '${summary['visits'] ?? 0}',
                  detail: 'Today',
                ),
                _MetricCard(
                  icon: Icons.receipt_long_outlined,
                  label: 'Orders',
                  value: '${summary['orders'] ?? 0}',
                  detail: _money(summary['order_total']),
                ),
                _MetricCard(
                  icon: Icons.payments_outlined,
                  label: 'Collections',
                  value: '${summary['collections'] ?? 0}',
                  detail: _money(summary['collection_total']),
                ),
                _MetricCard(
                  icon: Icons.receipt_outlined,
                  label: 'Expenses',
                  value: '${summary['expenses'] ?? 0}',
                  detail: _money(summary['expense_total']),
                ),
                _MetricCard(
                  icon: Icons.task_alt_outlined,
                  label: 'Completed day',
                  value: '${summary['completed'] ?? 0}',
                  detail: '${summary['not_started'] ?? 0} not started',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Live management view'),
                subtitle: Text(
                  'Updated from FieldPulse server for ${overview?['date'] ?? 'today'}. Pull down to refresh.',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _money(dynamic value) {
    final number = value is num ? value.toDouble() : double.tryParse('$value');
    if (number == null) return 'AFN 0';
    return 'AFN ${number.toStringAsFixed(number == number.roundToDouble() ? 0 : 2)}';
  }

  static String _roleLabel(String? role) => switch (role) {
    'supervisor' => 'Sales Supervisor',
    'sales_manager' => 'Sales Manager',
    'owner' => 'Owner',
    'company_admin' => 'Company Admin',
    _ => 'Management',
  };
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
            const Spacer(),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(label, style: Theme.of(context).textTheme.labelLarge),
            Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.cloud_off_outlined),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}
