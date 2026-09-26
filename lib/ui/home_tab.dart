import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../state/attendance_controller.dart';
import 'history_screen.dart';
import 'privacy_dialog.dart';
import 'sync_refresh.dart';

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

  Future<void> _end(
    BuildContext context,
    AttendanceController controller,
  ) async {
    final closing = await controller.dayClosingSummary();

    if (!context.mounted) return;

    if (closing.activeVisits > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Complete the active customer visit before ending the day.',
          ),
        ),
      );
      return;
    }

    var syncBeforeEnd = true;
    final vehicle = TextEditingController(
      text: controller.session?['vehicle_reference']?.toString() ?? '',
    );
    final odometer = TextEditingController();

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (dialogContext, setDialogState) => AlertDialog(
              title: const Text('End Day'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Review today before ending the day.'),
                  const SizedBox(height: 8),
                  Text('Visits: ${closing.visits}'),
                  Text(
                    'Orders: ${closing.orders} · AFN ${closing.orderTotal.toStringAsFixed(0)}',
                  ),
                  Text(
                    'Collections: ${closing.collections} · AFN ${closing.collectionTotal.toStringAsFixed(0)}',
                  ),
                  Text(
                    'Expenses: ${closing.expenses} · AFN ${closing.expenseTotal.toStringAsFixed(0)}',
                  ),
                  Text('Pending sync: ${closing.pendingSync}'),
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
                    decoration: InputDecoration(
                      labelText: 'End odometer km (optional)',
                      helperText:
                          controller.session?['odometer_start_km'] == null
                          ? null
                          : 'Start: ${controller.session!['odometer_start_km']} km',
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Sync data'),
                    subtitle: Text(
                      syncBeforeEnd
                          ? 'Pending data will be uploaded before ending.'
                          : 'Work day will end without syncing pending data.',
                    ),
                    value: syncBeforeEnd,
                    onChanged: (value) =>
                        setDialogState(() => syncBeforeEnd = value),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('End Day'),
                ),
              ],
            ),
          ),
        ) ??
        false;

    if (!confirmed || !context.mounted) {
      vehicle.dispose();
      odometer.dispose();
      return;
    }

    final rawOdometer = odometer.text.trim();
    final endOdometer = rawOdometer.isEmpty
        ? null
        : double.tryParse(rawOdometer);

    if (rawOdometer.isNotEmpty && (endOdometer == null || endOdometer < 0)) {
      vehicle.dispose();
      odometer.dispose();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid odometer reading.')),
      );
      return;
    }

    final vehicleReference = vehicle.text.trim();
    vehicle.dispose();
    odometer.dispose();

    await controller.endDay(
      sync: syncBeforeEnd,
      vehicleReference: vehicleReference,
      odometerEndKm: endOdometer,
    );

    if (!context.mounted) return;

    if (!controller.working && controller.message == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Work day ended successfully.')),
      );
    }
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
