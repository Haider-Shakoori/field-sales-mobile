import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/team/team_repository.dart';
import '../state/app_state.dart';

class SalesmanAccountScreen extends StatefulWidget {
  const SalesmanAccountScreen({super.key});

  @override
  State<SalesmanAccountScreen> createState() => _SalesmanAccountScreenState();
}

class _SalesmanAccountScreenState extends State<SalesmanAccountScreen> {
  Map<String, dynamic>? _data;
  bool _busy = false;
  bool _loadingMore = false;
  String? _error;
  int _page = 1;
  int _lastPage = 1;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({required bool reset}) async {
    if (_busy || _loadingMore) return;

    setState(() {
      if (reset) {
        _busy = true;
        _error = null;
      } else {
        _loadingMore = true;
      }
    });

    try {
      final nextPage = reset ? 1 : _page + 1;
      final result = await context.read<TeamRepository>().referralPortfolio(
        page: nextPage,
        perPage: 30,
      );

      if (!mounted) return;

      final meta = result['_meta'] is Map
          ? Map<String, dynamic>.from(result['_meta'] as Map)
          : const <String, dynamic>{};
      final pagination = meta['pagination'] is Map
          ? Map<String, dynamic>.from(meta['pagination'] as Map)
          : const <String, dynamic>{};

      if (!reset && _data != null) {
        final existing = _customers(_data!);
        final incoming = _customers(result);
        result['customers'] = [...existing, ...incoming];
      }

      setState(() {
        _data = result;
        _page =
            int.tryParse('${pagination['current_page'] ?? nextPage}') ??
            nextPage;
        _lastPage =
            int.tryParse('${pagination['last_page'] ?? _page}') ?? _page;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _loadingMore = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> _customers(Map<String, dynamic> source) {
    final rows = source['customers'];
    if (rows is! List) return const [];

    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_busy && _data == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_data == null) {
      return _ErrorState(
        message: _error ?? 'Referral account data is unavailable.',
        onRetry: () => _load(reset: true),
      );
    }

    final data = _data!;
    final salesman = data['salesman'] is Map
        ? Map<String, dynamic>.from(data['salesman'] as Map)
        : const <String, dynamic>{};
    final summary = data['summary'] is Map
        ? Map<String, dynamic>.from(data['summary'] as Map)
        : const <String, dynamic>{};
    final customers = _customers(data);
    final session = context.watch<AppState>().session;

    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    child: Text(
                      (salesman['name'] ?? session?.name ?? 'S')
                          .toString()
                          .trim()
                          .characters
                          .first
                          .toUpperCase(),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          salesman['name']?.toString() ??
                              session?.name ??
                              'Salesman',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          salesman['employee_code']?.toString() ??
                              'FieldPulse account',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.verified_user_outlined),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.0,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            children: [
              _MetricCard(
                label: 'Referred customers',
                value: '${summary['referred_customers'] ?? 0}',
                icon: Icons.storefront_outlined,
              ),
              _MetricCard(
                label: 'Orders',
                value: '${summary['orders'] ?? 0}',
                icon: Icons.receipt_long_outlined,
              ),
              _MetricCard(
                label: 'Collections',
                value: '${summary['collections'] ?? 0}',
                icon: Icons.payments_outlined,
              ),
              _MetricCard(
                label: 'Visits',
                value: '${summary['visits'] ?? 0}',
                icon: Icons.location_on_outlined,
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: Text(
                  'My referred customers',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${summary['active_customers'] ?? 0} active',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (customers.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'No customers are currently attributed to you as referrals.',
                ),
              ),
            )
          else
            ...customers.map((customer) => _CustomerCard(customer: customer)),
          if (_page < _lastPage) ...[
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: _loadingMore ? null : () => _load(reset: false),
              icon: _loadingMore
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.expand_more),
              label: Text(_loadingMore ? 'Loading…' : 'Load more customers'),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({required this.customer});

  final Map<String, dynamic> customer;

  @override
  Widget build(BuildContext context) {
    final balances = customer['balances'] is List
        ? (customer['balances'] as List)
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
        : const <Map<String, dynamic>>[];

    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customer['name']?.toString() ?? 'Customer',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [customer['code'], customer['territory']]
                            .where(
                              (value) => value != null && '$value'.isNotEmpty,
                            )
                            .join(' · '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (customer['assigned_to_me'] == true)
                  const Chip(label: Text('Assigned to me'))
                else if (customer['assigned_salesman'] != null)
                  const Chip(label: Text('Assigned elsewhere')),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _SmallMetric(
                  label: 'Orders',
                  value: '${customer['orders'] ?? 0}',
                ),
                _SmallMetric(
                  label: 'Collections',
                  value: '${customer['collections'] ?? 0}',
                ),
                _SmallMetric(
                  label: 'Visits',
                  value: '${customer['visits'] ?? 0}',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Outstanding', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 6),
            if (balances.isEmpty)
              const Text('No credit outstanding')
            else
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: balances.map((row) {
                  final raw = row['outstanding_balance'];
                  final amount = raw is num
                      ? raw.toDouble()
                      : double.tryParse('$raw') ?? 0;
                  return Chip(
                    label: Text(
                      '${row['currency'] ?? ''} ${amount.toStringAsFixed(2)}',
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }
}

class _SmallMetric extends StatelessWidget {
  const _SmallMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 44),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}
