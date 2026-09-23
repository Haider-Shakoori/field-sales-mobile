import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/financial_documents/customer_statement_repository.dart';
import '../state/app_state.dart';

class CustomerStatementScreen extends StatefulWidget {
  const CustomerStatementScreen({
    required this.customer,
    super.key,
  });

  final Map<String, dynamic> customer;

  @override
  State<CustomerStatementScreen> createState() =>
      _CustomerStatementScreenState();
}

class _CustomerStatementScreenState extends State<CustomerStatementScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _statement;
  String? _from;
  String? _to;
  String? _currency;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _load());
  }

  Future<void> _load({bool filtered = false, bool refresh = true}) async {
    final tenantId = context.read<AppState>().session?.tenantId;
    if (tenantId == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final statement = await context.read<CustomerStatementRepository>().load(
        tenantId: tenantId,
        customerUuid: widget.customer['id'].toString(),
        from: filtered ? _from : null,
        to: filtered ? _to : null,
        currency: filtered ? _currency : null,
        refresh: refresh,
      );

      if (!mounted) return;

      setState(() {
        _statement = statement;
        _from = statement['from']?.toString();
        _to = statement['to']?.toString();
        _currency = statement['currency']?.toString() ?? 'AFN';
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Bad state: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDate({required bool from}) async {
    final current = DateTime.tryParse(from ? _from ?? '' : _to ?? '');
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: current ?? DateTime.now(),
    );

    if (selected == null) return;

    final value =
        '${selected.year.toString().padLeft(4, '0')}-'
        '${selected.month.toString().padLeft(2, '0')}-'
        '${selected.day.toString().padLeft(2, '0')}';

    setState(() {
      if (from) {
        _from = value;
      } else {
        _to = value;
      }
    });
  }

  String _money(dynamic value) {
    final number = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0;
    return number.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final statement = _statement;
    final entries = statement?['entries'] is List
        ? List<dynamic>.from(statement!['entries'] as List)
        : const <dynamic>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Statement · ${widget.customer['name'] ?? 'Customer'}',
        ),
      ),
      body: _loading && statement == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _load(
                filtered: _from != null && _to != null && _currency != null,
              ),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => _pickDate(from: true),
                                  child: Text(_from ?? 'From'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => _pickDate(from: false),
                                  child: Text(_to ?? 'To'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: _currency,
                                  decoration: const InputDecoration(
                                    labelText: 'Currency',
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'AFN',
                                      child: Text('AFN'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'USD',
                                      child: Text('USD'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'PKR',
                                      child: Text('PKR'),
                                    ),
                                  ],
                                  onChanged: (value) =>
                                      setState(() => _currency = value),
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                onPressed:
                                    _from == null ||
                                        _to == null ||
                                        _currency == null ||
                                        _loading
                                    ? null
                                    : () => _load(filtered: true),
                                child: const Text('Apply'),
                              ),
                            ],
                          ),
                          if (statement?['_cached'] == true) ...[
                            const SizedBox(height: 10),
                            const Row(
                              children: [
                                Icon(Icons.offline_pin_outlined, size: 18),
                                SizedBox(width: 6),
                                Text('Showing cached statement'),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (statement != null) ...[
                    const SizedBox(height: 12),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      childAspectRatio: 2.2,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      children: [
                        _summary(
                          'Opening',
                          statement['opening_balance'],
                          statement['currency'],
                        ),
                        _summary(
                          'Sales',
                          statement['debits'],
                          statement['currency'],
                        ),
                        _summary(
                          'Payments',
                          statement['credits'],
                          statement['currency'],
                        ),
                        _summary(
                          'Closing',
                          statement['closing_balance'],
                          statement['currency'],
                          bold: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Transactions',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (entries.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('No transactions in this period.'),
                        ),
                      ),
                    ...entries.whereType<Map>().map((raw) {
                      final entry = Map<String, dynamic>.from(raw);
                      final debit = (entry['debit'] as num?)?.toDouble() ?? 0;
                      final credit =
                          (entry['credit'] as num?)?.toDouble() ?? 0;

                      return Card(
                        child: ListTile(
                          leading: Icon(
                            entry['type'] == 'collection'
                                ? Icons.payments_outlined
                                : Icons.receipt_long_outlined,
                          ),
                          title: Text(entry['reference']?.toString() ?? '—'),
                          subtitle: Text(
                            '${entry['description'] ?? ''}\n'
                            '${entry['occurred_at'] ?? ''}',
                          ),
                          isThreeLine: true,
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (debit > 0)
                                Text(
                                  '+${_money(debit)} ${statement['currency']}',
                                ),
                              if (credit > 0)
                                Text(
                                  '-${_money(credit)} ${statement['currency']}',
                                ),
                              Text(
                                'Bal ${_money(entry['balance'])}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                  const SizedBox(height: 28),
                ],
              ),
            ),
    );
  }

  Widget _summary(
    String label,
    dynamic amount,
    dynamic currency, {
    bool bold = false,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label),
            const SizedBox(height: 4),
            Text(
              '${_money(amount)} ${currency ?? ''}',
              style: TextStyle(
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
