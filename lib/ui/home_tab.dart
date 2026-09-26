import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../state/attendance_controller.dart';
import '../state/sync_controller.dart';
import 'history_screen.dart';
import 'privacy_dialog.dart';
import 'sync_refresh.dart';

class _EndDayMetric extends StatelessWidget {
  const _EndDayMetric({
    required this.label,
    required this.value,
    required this.detail,
  });

  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 145,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  Future<void> _start(
    BuildContext context,
    AttendanceController controller,
  ) async {
    final hasPrivacyAck = await controller.hasPrivacyAck();

    if (!context.mounted) {
      return;
    }

    if (!hasPrivacyAck) {
      final accepted =
          await showDialog<bool>(
            context: context,
            builder: (_) => const PrivacyDialog(),
          ) ??
          false;

      if (!accepted) {
        return;
      }

      await controller.acknowledgePrivacy();

      if (!context.mounted) {
        return;
      }
    }

    final vehicle = TextEditingController();
    final odometer = TextEditingController();

    final details = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Start Day'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Vehicle and odometer are optional. Add them when you want mileage reconciliation.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: vehicle,
              decoration: const InputDecoration(
                labelText: 'Vehicle / plate (optional)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: odometer,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Start odometer km (optional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final raw = odometer.text.trim();
              final value = raw.isEmpty ? null : double.tryParse(raw);

              if (raw.isNotEmpty && (value == null || value < 0)) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('Enter a valid odometer reading.'),
                  ),
                );
                return;
              }

              Navigator.pop(dialogContext, {
                'vehicle': vehicle.text.trim(),
                'odometer': value,
              });
            },
            child: const Text('Start Day'),
          ),
        ],
      ),
    );

    vehicle.dispose();
    odometer.dispose();

    if (details == null || !context.mounted) {
      return;
    }

    await controller.startDay(
      vehicleReference: details['vehicle']?.toString(),
      odometerStartKm: details['odometer'] as double?,
    );
  }

  Future<void> _reopen(
    BuildContext context,
    AttendanceController controller,
  ) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Reopen today\'s work day?'),
            content: const Text(
              'Use this only if End Day was tapped by mistake. Your original '
              'Start Day time and existing visits, orders, collections, and '
              'other work stay unchanged. Location tracking will resume.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Reopen Day'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed || !context.mounted) return;

    await controller.reopenDay();

    if (!context.mounted) return;

    if (controller.working && controller.message == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Work day reopened. Tracking has resumed.'),
        ),
      );
    }
  }

  Future<void> _end(
    BuildContext context,
    AttendanceController controller,
  ) async {
    var syncBeforeEnd = true;
    final vehicle = TextEditingController(
      text: controller.session?['vehicle_reference']?.toString() ?? '',
    );
    final odometer = TextEditingController();
    final remarks = TextEditingController();

    final preview = await controller.endDaySummary();

    if (!context.mounted) {
      vehicle.dispose();
      odometer.dispose();
      remarks.dispose();
      return;
    }

    final plan = _map(preview['plan']);
    final planSummary = _map(plan['summary']);
    final visits = _map(preview['visits']);
    final orders = _map(preview['orders']);
    final collections = _map(preview['collections']);
    final expenses = _map(preview['expenses']);
    final returns = _map(preview['returns']);
    final serverSession = _map(preview['session']);
    final missedRows = plan['missed_customers'] is List
        ? (plan['missed_customers'] as List)
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
        : const <Map<String, dynamic>>[];

    remarks.text = serverSession['notes']?.toString() ?? '';

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (dialogContext, setDialogState) => AlertDialog(
              title: const Text('End Day Reconciliation'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (preview['server_available'] != true)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Server summary is unavailable. You can still end the day offline; the record will sync later.',
                          ),
                        ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _EndDayMetric(
                            label: 'Planned',
                            value: '${planSummary['total_stops'] ?? 0}',
                            detail:
                                '${planSummary['remaining'] ?? 0} remaining',
                          ),
                          _EndDayMetric(
                            label: 'Visits',
                            value: '${visits['completed'] ?? 0}',
                            detail: '${visits['active'] ?? 0} active',
                          ),
                          _EndDayMetric(
                            label: 'Orders',
                            value: '${orders['total_count'] ?? 0}',
                            detail: _money(orders['all_totals']),
                          ),
                          _EndDayMetric(
                            label: 'Collections',
                            value: '${collections['total_count'] ?? 0}',
                            detail: _money(collections['all_totals']),
                          ),
                          _EndDayMetric(
                            label: 'Expenses',
                            value: '${expenses['total_count'] ?? 0}',
                            detail: _money(expenses['all_totals']),
                          ),
                          _EndDayMetric(
                            label: 'Returns',
                            value: '${returns['total_count'] ?? 0}',
                            detail: '${returns['pending_count'] ?? 0} pending',
                          ),
                        ],
                      ),
                      if (missedRows.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text(
                          'Missed / remaining customers',
                          style: Theme.of(dialogContext).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        ...missedRows
                            .take(5)
                            .map(
                              (row) => Padding(
                                padding: const EdgeInsets.only(bottom: 3),
                                child: Text(
                                  '• ${row['customer_name'] ?? 'Customer'}'
                                  '${row['priority'] == null ? '' : ' · ${row['priority']}'}',
                                ),
                              ),
                            ),
                        if (missedRows.length > 5)
                          Text('+ ${missedRows.length - 5} more'),
                      ],
                      const SizedBox(height: 14),
                      TextField(
                        controller: vehicle,
                        decoration: const InputDecoration(
                          labelText: 'Vehicle / plate (optional)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: odometer,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'End odometer km (optional)',
                          helperText:
                              controller.session?['odometer_start_km'] == null
                              ? null
                              : 'Start: ${controller.session!['odometer_start_km']} km',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: remarks,
                        maxLines: 3,
                        maxLength: 2000,
                        decoration: const InputDecoration(
                          labelText: 'End-of-day remarks (optional)',
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Sync before closing'),
                        subtitle: Text(
                          syncBeforeEnd
                              ? '${preview['local_pending'] ?? 0} local items will be given a sync attempt before End Day.'
                              : 'The work day will close locally and pending data will sync later.',
                        ),
                        value: syncBeforeEnd,
                        onChanged: (value) =>
                            setDialogState(() => syncBeforeEnd = value),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Confirm End Day'),
                ),
              ],
            ),
          ),
        ) ??
        false;

    if (!confirmed || !context.mounted) {
      vehicle.dispose();
      odometer.dispose();
      remarks.dispose();
      return;
    }

    final rawOdometer = odometer.text.trim();
    final endOdometer = rawOdometer.isEmpty
        ? null
        : double.tryParse(rawOdometer);

    if (rawOdometer.isNotEmpty && (endOdometer == null || endOdometer < 0)) {
      vehicle.dispose();
      odometer.dispose();
      remarks.dispose();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid odometer reading.')),
      );
      return;
    }

    if (syncBeforeEnd) {
      await context.read<SyncController>().run(triggerSource: 'end-day');

      if (!context.mounted) {
        vehicle.dispose();
        odometer.dispose();
        remarks.dispose();
        return;
      }
    }

    final vehicleReference = vehicle.text.trim();
    final notes = remarks.text.trim();
    vehicle.dispose();
    odometer.dispose();
    remarks.dispose();

    await controller.endDay(
      sync: true,
      vehicleReference: vehicleReference,
      odometerEndKm: endOdometer,
      notes: notes,
    );

    if (!context.mounted) return;

    if (!controller.working && controller.message == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Work day closed and reconciliation saved.'),
        ),
      );
    }
  }

  Map<String, dynamic> _map(dynamic value) {
    return value is Map
        ? Map<String, dynamic>.from(value)
        : const <String, dynamic>{};
  }

  String _money(dynamic raw) {
    if (raw is! List || raw.isEmpty) return '0';

    return raw
        .whereType<Map>()
        .map((row) {
          final item = Map<String, dynamic>.from(row);
          final total = item['total'];
          final currency = item['currency'];
          return '$total $currency';
        })
        .join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final controller = context.watch<AttendanceController>();
    final policy = app.policy;

    return RefreshIndicator(
      onRefresh: () async {
        await controller.refreshPolicyAndEvaluate();

        if (!context.mounted) return;

        await syncAndReload(context, triggerSource: 'pull:home');
      },
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Good day, ${app.session?.name ?? ''}',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            policy?.trusted == true
                ? 'Company policy synced'
                : 'Using safe offline policy',
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        controller.working ? Icons.location_on : Icons.schedule,
                        color: controller.working
                            ? Colors.green
                            : Colors.indigo,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        controller.working ? 'Working' : 'Work day',
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      Chip(
                        label: Text(
                          controller.working
                              ? (controller.tracking.active
                                    ? 'Tracking active'
                                    : 'Tracking paused')
                              : (policy?.startMode == 'automatic'
                                    ? 'Automatic'
                                    : 'Manual'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (controller.working) ...[
                    Text('Started ${controller.session?['start_time'] ?? ''}'),
                    const SizedBox(height: 8),
                    const Text(
                      'Location is stored locally first and syncs when connectivity is available.',
                    ),
                    const SizedBox(height: 18),
                    FilledButton.tonal(
                      onPressed: controller.busy
                          ? null
                          : () => _end(context, controller),
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('End Day'),
                      ),
                    ),
                  ] else if (controller.canReopenToday) ...[
                    const Text(
                      'Today\'s work day is closed. If End Day was tapped by '
                      'mistake, reopen the same attendance session to continue '
                      'working without changing the original start time.',
                    ),
                    const SizedBox(height: 18),
                    FilledButton.tonalIcon(
                      onPressed: controller.busy
                          ? null
                          : () => _reopen(context, controller),
                      icon: const Icon(Icons.restart_alt),
                      label: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          controller.busy ? 'Reopening…' : 'Reopen Day',
                        ),
                      ),
                    ),
                  ] else ...[
                    Text(
                      policy?.startMode == 'automatic'
                          ? 'Automatic work day · ${policy?.workdayStartTime}–${policy?.workdayEndTime}'
                          : 'Start when you are ready. Attendance works offline.',
                    ),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: controller.busy
                          ? null
                          : () => _start(context, controller),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          controller.busy ? 'Starting…' : 'Start Day',
                        ),
                      ),
                    ),
                  ],
                  if (controller.message != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.12),
                          border: Border.all(
                            color: Colors.amber.withValues(alpha: 0.35),
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 20,
                              color: Colors.amber.shade800,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                controller.message!,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Attendance history'),
              subtitle: const Text('Local records remain available offline'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HistoryScreen()),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Company tracking policy',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Timezone: ${policy?.timezone.isNotEmpty == true ? policy!.timezone : 'Unavailable'}',
                  ),
                  Text(
                    'GPS: ${policy?.gpsTrackingEnabled == true ? 'Enabled during work' : 'Disabled'}',
                  ),
                  Text(
                    'Intervals: ${policy?.movingSeconds ?? 15}s moving / ${policy?.stationarySeconds ?? 60}s stationary',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
