import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/target_controller.dart';

class TargetsScreen extends StatelessWidget {
  const TargetsScreen({super.key});

  String _label(String value) {
    return value
        .split('_')
        .map(
          (word) => word.isEmpty
              ? word
              : '${word[0].toUpperCase()}${word.substring(1)}',
        )
        .join(' ');
  }

  bool _amountTarget(String type) {
    return type == 'sales_amount' || type == 'collections_amount';
  }

  String _value(Map<String, dynamic> target, String key) {
    final type = target['target_type']?.toString() ?? '';
    final raw = target[key];
    final number = raw is num
        ? raw.toDouble()
        : double.tryParse(raw?.toString() ?? '') ?? 0;

    if (_amountTarget(type)) {
      final currency = target['currency']?.toString() ?? '';
      return '${number.toStringAsFixed(2)} $currency'.trim();
    }

    return number.toStringAsFixed(0);
  }

  Widget _targetCard(BuildContext context, Map<String, dynamic> target) {
    final type = target['target_type']?.toString() ?? '';
    final rawPercent = target['progress_percent'];
    final percent = rawPercent is num
        ? rawPercent.toDouble()
        : double.tryParse(rawPercent?.toString() ?? '') ?? 0;
    final bar = (percent / 100).clamp(0.0, 1.0).toDouble();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _label(type),
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              "${target['period_start']} → ${target['period_end']}",
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    "${_value(target, 'achieved_value')} / ${_value(target, 'target_value')}",
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text('${percent.toStringAsFixed(1)}%'),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: bar),
            const SizedBox(height: 8),
            Text(
              'Remaining: ${_value(target, 'remaining_value')}',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            if (target['notes'] != null &&
                target['notes'].toString().trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(target['notes'].toString()),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TargetController>();

    return RefreshIndicator(
      onRefresh: () => state.sync(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Current targets',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (state.currentTargets.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No current targets are cached. Pull to refresh when online.',
                ),
              ),
            )
          else
            ...state.currentTargets.map(
              (target) => _targetCard(context, target),
            ),
          const SizedBox(height: 20),
          Text(
            'Target history',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (state.history.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No target history cached yet.'),
              ),
            )
          else
            ...state.history
                .where(
                  (target) => !state.currentTargets.any(
                    (current) =>
                        current['target_uuid'] == target['target_uuid'],
                  ),
                )
                .map((target) => _targetCard(context, target)),
          if (state.message != null) ...[
            const SizedBox(height: 12),
            Text(state.message!, style: TextStyle(color: Colors.grey.shade600)),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
