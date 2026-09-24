import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/appointment_controller.dart';
import '../state/master_data_controller.dart';

class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({super.key});

  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen> {
  var _showCompleted = false;

  Future<DateTime?> _pickDateTime(
    BuildContext context,
    DateTime initial,
  ) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );

    if (date == null || !context.mounted) return null;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );

    if (time == null) return null;

    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _create(BuildContext context) async {
    final customers = context.read<MasterDataController>().customers;
    final title = TextEditingController();
    final location = TextEditingController();
    final notes = TextEditingController();
    Map<String, dynamic>? customer;
    var type = 'meeting';
    int? reminder = 30;
    var startsAt = DateTime.now().add(const Duration(hours: 1));
    DateTime? endsAt;

    final save =
        await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (sheetContext) => StatefulBuilder(
            builder: (context, setState) => Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                MediaQuery.viewInsetsOf(context).bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'New appointment',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(sheetContext, false),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: title,
                      autofocus: true,
                      maxLength: 160,
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: type,
                      decoration: const InputDecoration(
                        labelText: 'Type',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'meeting',
                          child: Text('Meeting'),
                        ),
                        DropdownMenuItem(value: 'visit', child: Text('Visit')),
                        DropdownMenuItem(value: 'call', child: Text('Call')),
                        DropdownMenuItem(
                          value: 'collection',
                          child: Text('Collection'),
                        ),
                        DropdownMenuItem(value: 'order', child: Text('Order')),
                        DropdownMenuItem(value: 'other', child: Text('Other')),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => type = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      initialValue: null,
                      decoration: const InputDecoration(
                        labelText: 'Customer',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('No customer'),
                        ),
                        ...customers.map(
                          (row) => DropdownMenuItem<String?>(
                            value: row['id']?.toString(),
                            child: Text(
                              (row['name'] ?? 'Customer').toString(),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          customer = value == null
                              ? null
                              : customers
                                    .cast<Map<String, dynamic>>()
                                    .firstWhere(
                                      (row) => row['id']?.toString() == value,
                                    );
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event_outlined),
                      title: const Text('Starts'),
                      subtitle: Text(_formatDateTime(startsAt)),
                      trailing: const Icon(Icons.edit_calendar_outlined),
                      onTap: () async {
                        final value = await _pickDateTime(context, startsAt);
                        if (value != null) setState(() => startsAt = value);
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event_available_outlined),
                      title: const Text('Ends'),
                      subtitle: Text(
                        endsAt == null ? 'Not set' : _formatDateTime(endsAt!),
                      ),
                      trailing: endsAt == null
                          ? const Icon(Icons.add)
                          : IconButton(
                              onPressed: () => setState(() => endsAt = null),
                              icon: const Icon(Icons.clear),
                            ),
                      onTap: () async {
                        final value = await _pickDateTime(
                          context,
                          endsAt ?? startsAt.add(const Duration(hours: 1)),
                        );
                        if (value != null && value.isAfter(startsAt)) {
                          setState(() => endsAt = value);
                        }
                      },
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<int?>(
                      initialValue: reminder,
                      decoration: const InputDecoration(
                        labelText: 'Reminder',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem<int?>(
                          value: null,
                          child: Text('None'),
                        ),
                        DropdownMenuItem<int?>(
                          value: 0,
                          child: Text('At start time'),
                        ),
                        DropdownMenuItem<int?>(
                          value: 15,
                          child: Text('15 minutes before'),
                        ),
                        DropdownMenuItem<int?>(
                          value: 30,
                          child: Text('30 minutes before'),
                        ),
                        DropdownMenuItem<int?>(
                          value: 60,
                          child: Text('1 hour before'),
                        ),
                        DropdownMenuItem<int?>(
                          value: 120,
                          child: Text('2 hours before'),
                        ),
                        DropdownMenuItem<int?>(
                          value: 1440,
                          child: Text('1 day before'),
                        ),
                      ],
                      onChanged: (value) => setState(() => reminder = value),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: location,
                      maxLength: 255,
                      decoration: const InputDecoration(
                        labelText: 'Location',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notes,
                      maxLines: 3,
                      maxLength: 5000,
                      decoration: const InputDecoration(
                        labelText: 'Notes',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: () {
                        if (title.text.trim().isNotEmpty) {
                          Navigator.pop(sheetContext, true);
                        }
                      },
                      icon: const Icon(Icons.event_available),
                      label: const Text('Save appointment'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ) ??
        false;

    if (!save || !context.mounted) return;

    await context.read<AppointmentController>().create(
      customer: customer,
      title: title.text,
      type: type,
      startsAt: startsAt,
      endsAt: endsAt,
      reminderMinutesBefore: reminder,
      location: location.text,
      notes: notes.text,
    );
  }

  static String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');

    return '${local.year}-$month-$day $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppointmentController>();
    final now = DateTime.now();

    final rows =
        state.appointments.where((row) {
          if (_showCompleted) return true;
          return row['status'] == 'scheduled';
        }).toList()..sort((a, b) {
          final aDate = DateTime.tryParse(a['starts_at']?.toString() ?? '');
          final bDate = DateTime.tryParse(b['starts_at']?.toString() ?? '');
          return (aDate ?? now).compareTo(bDate ?? now);
        });

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => state.sync(),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            const CircleAvatar(
                              child: Icon(Icons.calendar_month_outlined),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Calendar & appointments',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 17,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Your schedule stays cached for offline use.',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            if (state.pending > 0)
                              Badge(
                                label: Text(state.pending.toString()),
                                child: const Icon(Icons.cloud_upload_outlined),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: false,
                          label: Text('Scheduled'),
                          icon: Icon(Icons.upcoming_outlined),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text('All'),
                          icon: Icon(Icons.view_agenda_outlined),
                        ),
                      ],
                      selected: {_showCompleted},
                      onSelectionChanged: (value) {
                        setState(() => _showCompleted = value.first);
                      },
                    ),
                    if (state.message != null) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          state.message!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (rows.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.event_busy_outlined, size: 48),
                        SizedBox(height: 12),
                        Text('No appointments cached yet.'),
                        SizedBox(height: 4),
                        Text(
                          'Pull down to sync or create one for later.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverList.separated(
                itemCount: rows.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final row = rows[index];
                  final starts = DateTime.tryParse(
                    row['starts_at']?.toString() ?? '',
                  )?.toLocal();
                  final status = row['status']?.toString() ?? 'scheduled';
                  final pending = row['sync_status']?.toString() != 'synced';
                  final overdue =
                      status == 'scheduled' &&
                      starts != null &&
                      starts.isBefore(now);

                  return Padding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      index == 0 ? 8 : 0,
                      16,
                      index == rows.length - 1 ? 96 : 0,
                    ),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 52,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: overdue
                                    ? Theme.of(context)
                                          .colorScheme
                                          .errorContainer
                                    : Theme.of(context)
                                          .colorScheme
                                          .primaryContainer,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    starts == null
                                        ? '--'
                                        : starts.day.toString().padLeft(2, '0'),
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    starts == null
                                        ? '--:--'
                                        : '${starts.hour.toString().padLeft(2, '0')}:${starts.minute.toString().padLeft(2, '0')}',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          row['title']?.toString() ??
                                              'Appointment',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      if (pending)
                                        const Tooltip(
                                          message: 'Waiting to sync',
                                          child: Icon(
                                            Icons.cloud_upload_outlined,
                                            size: 18,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    [
                                          row['type'],
                                          row['customer_name'],
                                          row['location'],
                                        ]
                                        .where(
                                          (value) =>
                                              value != null &&
                                              value
                                                  .toString()
                                                  .trim()
                                                  .isNotEmpty,
                                        )
                                        .join(' · '),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                  if (row['notes']
                                          ?.toString()
                                          .trim()
                                          .isNotEmpty ==
                                      true) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      row['notes'].toString(),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Chip(
                                        visualDensity: VisualDensity.compact,
                                        label: Text(status),
                                      ),
                                      if (status == 'scheduled')
                                        OutlinedButton.icon(
                                          onPressed: state.busy
                                              ? null
                                              : () => state.updateStatus(
                                                  row,
                                                  'completed',
                                                ),
                                          icon: const Icon(
                                            Icons.check,
                                            size: 16,
                                          ),
                                          label: const Text('Complete'),
                                        ),
                                      if (status == 'scheduled')
                                        TextButton(
                                          onPressed: state.busy
                                              ? null
                                              : () => state.updateStatus(
                                                  row,
                                                  'cancelled',
                                                ),
                                          child: const Text('Cancel'),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: state.busy ? null : () => _create(context),
        icon: const Icon(Icons.add),
        label: const Text('Appointment'),
      ),
    );
  }
}
