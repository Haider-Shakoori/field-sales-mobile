import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/lead_controller.dart';

class LeadsScreen extends StatefulWidget {
  const LeadsScreen({super.key});
  @override
  State<LeadsScreen> createState() => _LeadsScreenState();
}

class _LeadsScreenState extends State<LeadsScreen> {
  String _stage = 'open';
  static const stages = [
    'new',
    'contacted',
    'qualified',
    'proposal',
    'negotiation',
    'won',
    'lost',
  ];
  static const stageLabels = {
    'new': 'New',
    'contacted': 'Contacted',
    'qualified': 'Qualified',
    'proposal': 'Proposal',
    'negotiation': 'Negotiation',
    'won': 'Won',
    'lost': 'Lost',
  };
  static const sources = [
    'field',
    'referral',
    'website',
    'phone',
    'campaign',
    'walk_in',
    'other',
  ];

  Future<void> _create(BuildContext context) async {
    final name = TextEditingController(),
        contact = TextEditingController(),
        phone = TextEditingController(),
        email = TextEditingController(),
        value = TextEditingController(),
        notes = TextEditingController();
    String source = 'field', priority = 'normal', currency = 'AFN';
    final save = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('New lead'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Prospect or business name',
                  ),
                ),
                TextField(
                  controller: contact,
                  decoration: const InputDecoration(
                    labelText: 'Contact person',
                  ),
                ),
                TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone'),
                ),
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: source,
                  items: sources
                      .map(
                        (e) => DropdownMenuItem(
                          value: e,
                          child: Text(e.replaceAll('_', ' ')),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => source = v ?? source),
                  decoration: const InputDecoration(labelText: 'Source'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: priority,
                  items: ['low', 'normal', 'high']
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) => setState(() => priority = v ?? priority),
                  decoration: const InputDecoration(labelText: 'Priority'),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: value,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Estimated value',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 90,
                      child: TextField(
                        controller: TextEditingController(text: currency),
                        onChanged: (v) => currency = v,
                        decoration: const InputDecoration(
                          labelText: 'Currency',
                        ),
                      ),
                    ),
                  ],
                ),
                TextField(
                  controller: notes,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialog, name.text.trim().isNotEmpty),
              child: const Text('Save offline'),
            ),
          ],
        ),
      ),
    );
    if (save != true || !context.mounted) return;
    await context.read<LeadController>().create(
      name: name.text,
      contactPerson: contact.text,
      phone: phone.text,
      email: email.text,
      source: source,
      priority: priority,
      estimatedValue: double.tryParse(value.text),
      currency: currency,
      notes: notes.text,
    );
  }

  Future<void> _details(BuildContext context, Map<String, dynamic> lead) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => _LeadSheet(lead: lead),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LeadController>();
    final rows = state.leads
        .where(
          (lead) =>
              _stage == 'all' ||
              (_stage == 'open' && !['won', 'lost'].contains(lead['stage'])) ||
              lead['stage'] == _stage,
        )
        .toList();
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => state.sync(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const CircleAvatar(child: Icon(Icons.filter_alt_outlined)),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Leads & pipeline',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Capture prospects offline and move them toward conversion.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    if (state.pending > 0)
                      Badge(
                        label: Text('${state.pending}'),
                        child: const Icon(Icons.cloud_upload_outlined),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _stage,
              items: [
                const DropdownMenuItem(
                  value: 'open',
                  child: Text('Open pipeline'),
                ),
                const DropdownMenuItem(value: 'all', child: Text('All stages')),
                ...stages.map(
                  (s) =>
                      DropdownMenuItem(value: s, child: Text(stageLabels[s]!)),
                ),
              ],
              onChanged: (v) => setState(() => _stage = v ?? 'open'),
              decoration: const InputDecoration(labelText: 'Stage'),
            ),
            if (state.message != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  state.message!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 12),
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('No leads in this view.')),
              )
            else
              ...rows.map(
                (lead) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    child: ListTile(
                      onTap: () => _details(context, lead),
                      leading: CircleAvatar(
                        child: Text(
                          (lead['name']?.toString() ?? '?')
                              .substring(0, 1)
                              .toUpperCase(),
                        ),
                      ),
                      title: Text(lead['name']?.toString() ?? 'Lead'),
                      subtitle: Text(
                        '${stageLabels[lead['stage']] ?? lead['stage']} · ${lead['priority']}\n${lead['contact_person'] ?? lead['phone'] ?? ''}',
                      ),
                      isThreeLine: true,
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (lead['estimated_value'] != null)
                            Text(
                              '${lead['currency']} ${lead['estimated_value']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          Text('${lead['probability'] ?? 0}%'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: state.busy ? null : () => _create(context),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Lead'),
      ),
    );
  }
}

class _LeadSheet extends StatefulWidget {
  const _LeadSheet({required this.lead});
  final Map<String, dynamic> lead;
  @override
  State<_LeadSheet> createState() => _LeadSheetState();
}

class _LeadSheetState extends State<_LeadSheet> {
  late String stage;
  late String priority;
  final notes = TextEditingController();
  final activity = TextEditingController();
  String activityType = 'note';
  @override
  void initState() {
    super.initState();
    stage = widget.lead['stage']?.toString() ?? 'new';
    priority = widget.lead['priority']?.toString() ?? 'normal';
    notes.text = widget.lead['notes']?.toString() ?? '';
  }

  @override
  void dispose() {
    notes.dispose();
    activity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LeadController>();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.lead['name']?.toString() ?? 'Lead',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: stage,
                items: _LeadsScreenState.stages
                    .map(
                      (s) => DropdownMenuItem(
                        value: s,
                        child: Text(_LeadsScreenState.stageLabels[s]!),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => stage = v ?? stage),
                decoration: const InputDecoration(labelText: 'Stage'),
              ),
              DropdownButtonFormField<String>(
                initialValue: priority,
                items: ['low', 'normal', 'high']
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) => setState(() => priority = v ?? priority),
                decoration: const InputDecoration(labelText: 'Priority'),
              ),
              TextField(
                controller: notes,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Opportunity notes',
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: state.busy
                    ? null
                    : () async {
                        await state.update(
                          widget.lead,
                          stage: stage,
                          priority: priority,
                          notes: notes.text,
                        );
                        if (context.mounted) Navigator.pop(context);
                      },
                child: const Text('Save changes'),
              ),
              const Divider(height: 32),
              Text(
                'Add activity',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              DropdownButtonFormField<String>(
                initialValue: activityType,
                items: ['note', 'call', 'meeting', 'visit', 'other']
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) =>
                    setState(() => activityType = v ?? activityType),
                decoration: const InputDecoration(labelText: 'Type'),
              ),
              TextField(
                controller: activity,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'What happened?'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: state.busy || activity.text.trim().isEmpty
                    ? null
                    : () async {
                        await state.addActivity(
                          widget.lead,
                          type: activityType,
                          notes: activity.text,
                        );
                        if (context.mounted) Navigator.pop(context);
                      },
                child: const Text('Save activity offline'),
              ),
              if (widget.lead['converted_customer_uuid'] == null &&
                  stage != 'lost') ...[
                const Divider(height: 32),
                FilledButton.tonalIcon(
                  onPressed: state.busy
                      ? null
                      : () async {
                          await state.convert(widget.lead);
                          if (context.mounted) Navigator.pop(context);
                        },
                  icon: const Icon(Icons.storefront),
                  label: const Text('Mark Won & convert to customer'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}