import 'package:field_sales_mobile/l10n/localized_material.dart';
import 'package:provider/provider.dart';
import '../l10n/l10n.dart';

import '../features/followups/follow_up_repository.dart';
import '../state/follow_up_controller.dart';
import '../state/master_data_controller.dart';

class FollowUpsScreen extends StatefulWidget {
  const FollowUpsScreen({super.key, this.customer});

  final Map<String, dynamic>? customer;

  @override
  State<FollowUpsScreen> createState() => _FollowUpsScreenState();
}

class _FollowUpsScreenState extends State<FollowUpsScreen> {
  bool _showAll = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final controller = context.read<FollowUpController>();
      await controller.reloadLocal();
      if (!mounted) return;
      await controller.sync(silent: true);
    });
  }

  String _label(String value) {
    return value
        .replaceAll('_', ' ')
        .split(' ')
        .map(
          (part) =>
              part.isEmpty ? part : part[0].toUpperCase() + part.substring(1),
        )
        .join(' ');
  }

  String _dateTime(dynamic value) {
    final parsed = value is DateTime
        ? value
        : DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) return '—';

    final local = parsed.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');

    return '${local.year}-$month-$day $hour:$minute';
  }

  Future<DateTime?> _pickDueAt(BuildContext context, DateTime initial) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 7)),
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
    if (widget.customer == null && customers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No customers are available offline yet.'),
        ),
      );
      return;
    }

    Map<String, dynamic>? customer = widget.customer;
    var type = 'call';
    var priority = 'normal';
    var dueAt = DateTime.now().add(const Duration(hours: 2));
    final notes = TextEditingController();

    final save =
        await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (sheetContext) => StatefulBuilder(
            builder: (context, setModalState) => Padding(
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
                    const Text(
                      'New follow-up',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: customer?['id']?.toString(),
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: L10n.text('Customer'),
                        border: OutlineInputBorder(),
                      ),
                      items: customers
                          .map(
                            (row) => DropdownMenuItem(
                              value: row['id']?.toString(),
                              child: Text(
                                (row['name'] ?? 'Customer').toString(),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: widget.customer != null
                          ? null
                          : (value) => setModalState(() {
                              customer = value == null
                                  ? null
                                  : customers.firstWhere(
                                      (row) => row['id']?.toString() == value,
                                    );
                            }),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: type,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: L10n.text('Type'),
                              border: OutlineInputBorder(),
                            ),
                            items: FollowUpRepository.types
                                .map(
                                  (value) => DropdownMenuItem(
                                    value: value,
                                    child: Text(_label(value)),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) =>
                                setModalState(() => type = value ?? type),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: priority,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: L10n.text('Priority'),
                              border: OutlineInputBorder(),
                            ),
                            items: FollowUpRepository.priorities
                                .map(
                                  (value) => DropdownMenuItem(
                                    value: value,
                                    child: Text(_label(value)),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) => setModalState(
                              () => priority = value ?? priority,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.schedule_outlined),
                      title: const Text('Due'),
                      subtitle: Text(_dateTime(dueAt)),
                      trailing: const Icon(Icons.edit_calendar_outlined),
                      onTap: () async {
                        final selected = await _pickDueAt(context, dueAt);
                        if (selected != null) {
                          setModalState(() => dueAt = selected);
                        }
                      },
                    ),
                    TextField(
                      controller: notes,
                      maxLines: 3,
                      maxLength: 5000,
                      decoration: InputDecoration(
                        labelText: L10n.text('Notes'),
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: customer == null
                          ? null
                          : () => Navigator.pop(sheetContext, true),
                      icon: const Icon(Icons.schedule_send_outlined),
                      label: const Text('Save follow-up'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ) ??
        false;

    if (save && customer != null && context.mounted) {
      await context.read<FollowUpController>().create(
        customer: customer!,
        type: type,
        priority: priority,
        dueAt: dueAt,
        notes: notes.text,
      );
    }
    notes.dispose();
  }

  Future<void> _changeStatus(
    BuildContext context,
    Map<String, dynamic> row,
    String status,
  ) async {
    final note = TextEditingController();
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(
              status == 'completed'
                  ? 'Complete follow-up?'
                  : 'Cancel follow-up?',
            ),
            content: TextField(
              controller: note,
              maxLines: 3,
              maxLength: 5000,
              decoration: InputDecoration(
                labelText: L10n.text('Completion note'),
                alignLabelWithHint: true,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Back'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(status == 'completed' ? 'Complete' : 'Cancel'),
              ),
            ],
          ),
        ) ??
        false;

    if (confirmed && context.mounted) {
      await context.read<FollowUpController>().updateStatus(
        row,
        status,
        completionNote: note.text,
      );
    }
    note.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<FollowUpController>();
    final now = DateTime.now();
    final customerId = widget.customer?['id']?.toString();

    final rows = state.followUps.where((row) {
      if (customerId != null &&
          row['customer_uuid']?.toString() != customerId) {
        return false;
      }
      return _showAll || row['status'] == 'pending';
    }).toList();

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => state.sync(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const CircleAvatar(
                      child: Icon(Icons.follow_the_signs_outlined),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.customer == null
                                ? 'Customer follow-ups'
                                : (widget.customer!['name'] ?? 'Customer')
                                      .toString(),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 17,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.customer == null
                                ? 'Assigned actions stay available offline.'
                                : 'Follow-ups for this customer.',
                            style: const TextStyle(fontSize: 12),
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
                  label: Text('Pending'),
                  icon: Icon(Icons.pending_actions_outlined),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('All'),
                  icon: Icon(Icons.view_agenda_outlined),
                ),
              ],
              selected: {_showAll},
              onSelectionChanged: (values) {
                setState(() => _showAll = values.first);
              },
            ),
            if (state.message != null) ...[
              const SizedBox(height: 8),
              Text(
                state.message!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 8),
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Column(
                  children: [
                    Icon(Icons.task_alt_outlined, size: 48),
                    SizedBox(height: 12),
                    Text('No follow-ups in this view.'),
                  ],
                ),
              )
            else
              ...rows.map((row) {
                final status = row['status']?.toString() ?? 'pending';
                final due = DateTime.tryParse(row['due_at']?.toString() ?? '')
                    ?.toLocal();
                final overdue =
                    status == 'pending' && due != null && due.isBefore(now);
                final syncing = row['sync_status']?.toString() != 'synced';

                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                row['customer_name']?.toString() ?? 'Customer',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (syncing)
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
                          "${_label(row['type']?.toString() ?? 'call')} · ${_label(row['priority']?.toString() ?? 'normal')}",
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              overdue
                                  ? Icons.warning_amber_rounded
                                  : Icons.schedule_outlined,
                              size: 18,
                              color: overdue
                                  ? Theme.of(context).colorScheme.error
                                  : null,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Due ${_dateTime(row['due_at'])}',
                                style: TextStyle(
                                  color: overdue
                                      ? Theme.of(context).colorScheme.error
                                      : null,
                                  fontWeight: overdue ? FontWeight.w700 : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (row['notes']?.toString().trim().isNotEmpty ==
                            true) ...[
                          const SizedBox(height: 8),
                          Text(
                            row['notes'].toString(),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Chip(
                              visualDensity: VisualDensity.compact,
                              label: Text(_label(status)),
                            ),
                            if (status == 'pending')
                              OutlinedButton.icon(
                                onPressed: state.busy
                                    ? null
                                    : () => _changeStatus(
                                        context,
                                        row,
                                        'completed',
                                      ),
                                icon: const Icon(Icons.check, size: 16),
                                label: const Text('Complete'),
                              ),
                            if (status == 'pending')
                              TextButton(
                                onPressed: state.busy
                                    ? null
                                    : () => _changeStatus(
                                        context,
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
                );
              }),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: state.busy ? null : () => _create(context),
        icon: const Icon(Icons.add),
        label: const Text('Follow-up'),
      ),
    );
  }
}
