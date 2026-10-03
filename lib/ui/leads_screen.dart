import 'package:field_sales_mobile/l10n/localized_material.dart';
import 'package:provider/provider.dart';
import '../l10n/l10n.dart';

import '../state/lead_controller.dart';
import 'sync_refresh.dart';

class LeadsScreen extends StatefulWidget {
  const LeadsScreen({super.key});

  @override
  State<LeadsScreen> createState() => _LeadsScreenState();
}

class _LeadsScreenState extends State<LeadsScreen> {
  static const stages = [
    'new',
    'contacted',
    'qualified',
    'proposal',
    'negotiation',
    'won',
    'lost',
  ];
  static const sources = [
    'field',
    'referral',
    'website',
    'phone',
    'campaign',
    'walk_in',
    'other',
  ];
  static const priorities = ['low', 'normal', 'high'];
  String? _stage;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LeadController>();
    final rows = _stage == null
        ? state.leads
        : state.leads.where((row) => row['stage'] == _stage).toList();
    final open = state.leads
        .where((row) => !['won', 'lost'].contains(row['stage']))
        .length;
    final won = state.leads.where((row) => row['stage'] == 'won').length;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: state.busy ? null : () => _create(context),
        icon: const Icon(Icons.add),
        label: const Text('New lead'),
      ),
      body: RefreshIndicator(
        onRefresh: () => syncAndReload(context, triggerSource: 'pull:leads'),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const CircleAvatar(
                          child: Icon(Icons.filter_alt_outlined),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Leads & sales pipeline',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 17,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Capture prospects and move opportunities toward conversion.',
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
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _Metric(label: 'Open', value: '$open'),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _Metric(label: 'Won', value: '$won'),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _Metric(
                            label: 'Total',
                            value: '${state.leads.length}',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: const Text('All'),
                      selected: _stage == null,
                      onSelected: (_) => setState(() => _stage = null),
                    ),
                  ),
                  ...stages.map(
                    (stage) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text(_label(stage)),
                        selected: _stage == stage,
                        onSelected: (_) => setState(() => _stage = stage),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (state.message != null) ...[
              const SizedBox(height: 8),
              Text(
                state.message!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 10),
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(child: Text('No leads in this stage.')),
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
                          (lead['name']?.toString().trim().isNotEmpty ?? false)
                              ? lead['name'].toString().trim()[0].toUpperCase()
                              : '?',
                        ),
                      ),
                      title: Text(
                        lead['name']?.toString() ?? 'Lead',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 3),
                          Text(
                            '${_label(lead['stage']?.toString() ?? 'new')} · ${lead['probability'] ?? 0}% · ${_label(lead['priority']?.toString() ?? 'normal')}',
                          ),
                          if (lead['estimated_value'] != null)
                            Text(
                              '${lead['currency'] ?? 'AFN'} ${_number(lead['estimated_value'])}',
                            ),
                          if (lead['contact_person'] != null ||
                              lead['phone'] != null)
                            Text(
                              [lead['contact_person'], lead['phone']]
                                  .where(
                                    (value) =>
                                        value != null &&
                                        value.toString().trim().isNotEmpty,
                                  )
                                  .join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                      trailing:
                          lead['sync_status'] == 'synced' &&
                              lead['pending_conversion'] != 1
                          ? const Icon(Icons.chevron_right)
                          : const Icon(Icons.cloud_upload_outlined, size: 20),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _create(BuildContext context) async {
    final name = TextEditingController();
    final contact = TextEditingController();
    final phone = TextEditingController();
    final email = TextEditingController();
    final address = TextEditingController();
    final value = TextEditingController();
    final currency = TextEditingController(text: 'AFN');
    final notes = TextEditingController();
    var source = 'field';
    var priority = 'normal';
    DateTime? expectedCloseDate;

    final save =
        await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          builder: (sheetContext) => StatefulBuilder(
            builder: (context, setModalState) => Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'New lead',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: name,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: L10n.text('Business or prospect name'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: contact,
                      decoration: InputDecoration(
                        labelText: L10n.text('Contact person'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: phone,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(labelText: L10n.text('Phone')),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(labelText: L10n.text('Email')),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: address,
                      maxLines: 2,
                      decoration: InputDecoration(labelText: L10n.text('Address')),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: source,
                            decoration: InputDecoration(
                              labelText: L10n.text('Source'),
                            ),
                            items: sources
                                .map(
                                  (item) => DropdownMenuItem(
                                    value: item,
                                    child: Text(_label(item)),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) =>
                                setModalState(() => source = v ?? source),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: priority,
                            decoration: InputDecoration(
                              labelText: L10n.text('Priority'),
                            ),
                            items: priorities
                                .map(
                                  (item) => DropdownMenuItem(
                                    value: item,
                                    child: Text(_label(item)),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) =>
                                setModalState(() => priority = v ?? priority),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: value,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: L10n.text('Estimated value'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 90,
                          child: TextField(
                            controller: currency,
                            maxLength: 3,
                            textCapitalization: TextCapitalization.characters,
                            decoration: InputDecoration(
                              labelText: L10n.text('Currency'),
                              counterText: '',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event_outlined),
                      title: const Text('Expected close date'),
                      subtitle: Text(_dateLabel(expectedCloseDate)),
                      trailing: expectedCloseDate == null
                          ? const Icon(Icons.add)
                          : IconButton(
                              onPressed: () =>
                                  setModalState(() => expectedCloseDate = null),
                              icon: const Icon(Icons.clear),
                            ),
                      onTap: () async {
                        final selected = await showDatePicker(
                          context: context,
                          initialDate:
                              expectedCloseDate ??
                              DateTime.now().add(const Duration(days: 7)),
                          firstDate: DateTime.now().subtract(
                            const Duration(days: 365),
                          ),
                          lastDate: DateTime.now().add(
                            const Duration(days: 3650),
                          ),
                        );
                        if (selected != null) {
                          setModalState(() => expectedCloseDate = selected);
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: notes,
                      maxLines: 3,
                      decoration: InputDecoration(labelText: L10n.text('Notes')),
                    ),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: () {
                        if (name.text.trim().isNotEmpty) {
                          Navigator.pop(sheetContext, true);
                        }
                      },
                      child: const Text('Save offline'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ) ??
        false;

    if (!save || !context.mounted) return;
    await context.read<LeadController>().create(
      name: name.text,
      contactPerson: contact.text,
      phone: phone.text,
      email: email.text,
      address: address.text,
      source: source,
      priority: priority,
      estimatedValue: double.tryParse(value.text.trim()),
      currency: currency.text.trim().isEmpty ? 'AFN' : currency.text.trim(),
      expectedCloseDate: expectedCloseDate,
      notes: notes.text,
    );
  }

  Future<void> _details(BuildContext context, Map<String, dynamic> lead) async {
    final controller = context.read<LeadController>();
    final uuid = lead['offline_uuid']?.toString();
    if (uuid == null) return;
    var activityRows = await controller.activities(uuid);
    if (!context.mounted) return;
    var selectedStage = lead['stage']?.toString() ?? 'new';
    var selectedSource = lead['source']?.toString() ?? 'field';
    var selectedPriority = lead['priority']?.toString() ?? 'normal';
    var expectedCloseDate = _parseDate(lead['expected_close_date']);
    final nameEditor = TextEditingController(
      text: lead['name']?.toString() ?? '',
    );
    final contactEditor = TextEditingController(
      text: lead['contact_person']?.toString() ?? '',
    );
    final phoneEditor = TextEditingController(
      text: lead['phone']?.toString() ?? '',
    );
    final emailEditor = TextEditingController(
      text: lead['email']?.toString() ?? '',
    );
    final addressEditor = TextEditingController(
      text: lead['address']?.toString() ?? '',
    );
    final valueEditor = TextEditingController(
      text: lead['estimated_value'] == null
          ? ''
          : _number(lead['estimated_value']),
    );
    final currencyEditor = TextEditingController(
      text: lead['currency']?.toString() ?? 'AFN',
    );
    final lostReasonEditor = TextEditingController(
      text: lead['lost_reason']?.toString() ?? '',
    );
    final notesEditor = TextEditingController(
      text: lead['notes']?.toString() ?? '',
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setModalState) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: .82,
          maxChildSize: .95,
          minChildSize: .5,
          builder: (_, scrollController) => ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      lead['name']?.toString() ?? 'Lead',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (lead['sync_status'] != 'synced' ||
                      lead['pending_conversion'] == 1)
                    const Icon(Icons.cloud_upload_outlined),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                [lead['contact_person'], lead['phone'], lead['email']]
                    .where(
                      (value) =>
                          value != null && value.toString().trim().isNotEmpty,
                    )
                    .join(' · '),
              ),
              if (lead['estimated_value'] != null) ...[
                const SizedBox(height: 8),
                Text(
                  '${lead['currency'] ?? 'AFN'} ${_number(lead['estimated_value'])}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
              if (lead['converted_customer_name'] != null) ...[
                const SizedBox(height: 8),
                Chip(
                  avatar: const Icon(Icons.check_circle_outline, size: 18),
                  label: Text('Customer: ${lead['converted_customer_name']}'),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: nameEditor,
                enabled: lead['converted_customer_uuid'] == null,
                decoration: InputDecoration(
                  labelText: L10n.text('Business or prospect name'),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: contactEditor,
                enabled: lead['converted_customer_uuid'] == null,
                decoration: InputDecoration(labelText: L10n.text('Contact person')),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phoneEditor,
                enabled: lead['converted_customer_uuid'] == null,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: L10n.text('Phone')),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: emailEditor,
                enabled: lead['converted_customer_uuid'] == null,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(labelText: L10n.text('Email')),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: addressEditor,
                enabled: lead['converted_customer_uuid'] == null,
                maxLines: 2,
                decoration: InputDecoration(labelText: L10n.text('Address')),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: selectedSource,
                      decoration: InputDecoration(labelText: L10n.text('Source')),
                      items: sources
                          .map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(_label(item)),
                            ),
                          )
                          .toList(),
                      onChanged: lead['converted_customer_uuid'] != null
                          ? null
                          : (value) => setModalState(
                              () => selectedSource = value ?? selectedSource,
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: selectedPriority,
                      decoration: InputDecoration(labelText: L10n.text('Priority')),
                      items: priorities
                          .map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(_label(item)),
                            ),
                          )
                          .toList(),
                      onChanged: lead['converted_customer_uuid'] != null
                          ? null
                          : (value) => setModalState(
                              () =>
                                  selectedPriority = value ?? selectedPriority,
                            ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: selectedStage,
                decoration: InputDecoration(labelText: L10n.text('Pipeline stage')),
                items: stages
                    .map(
                      (stage) => DropdownMenuItem(
                        value: stage,
                        child: Text(_label(stage)),
                      ),
                    )
                    .toList(),
                onChanged: lead['converted_customer_uuid'] != null
                    ? null
                    : (value) => setModalState(
                        () => selectedStage = value ?? selectedStage,
                      ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: valueEditor,
                      enabled: lead['converted_customer_uuid'] == null,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: L10n.text('Estimated value'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 90,
                    child: TextField(
                      controller: currencyEditor,
                      enabled: lead['converted_customer_uuid'] == null,
                      maxLength: 3,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: L10n.text('Currency'),
                        counterText: '',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: const Text('Expected close date'),
                subtitle: Text(_dateLabel(expectedCloseDate)),
                trailing: expectedCloseDate == null
                    ? const Icon(Icons.add)
                    : IconButton(
                        onPressed: lead['converted_customer_uuid'] != null
                            ? null
                            : () =>
                                  setModalState(() => expectedCloseDate = null),
                        icon: const Icon(Icons.clear),
                      ),
                onTap: lead['converted_customer_uuid'] != null
                    ? null
                    : () async {
                        final selected = await showDatePicker(
                          context: context,
                          initialDate:
                              expectedCloseDate ??
                              DateTime.now().add(const Duration(days: 7)),
                          firstDate: DateTime.now().subtract(
                            const Duration(days: 365),
                          ),
                          lastDate: DateTime.now().add(
                            const Duration(days: 3650),
                          ),
                        );
                        if (selected != null) {
                          setModalState(() => expectedCloseDate = selected);
                        }
                      },
              ),
              if (selectedStage == 'lost') ...[
                const SizedBox(height: 10),
                TextField(
                  controller: lostReasonEditor,
                  enabled: lead['converted_customer_uuid'] == null,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: L10n.text('Lost reason'),
                    helperText: L10n.text('Required when the opportunity is marked lost.'),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: notesEditor,
                enabled: lead['converted_customer_uuid'] == null,
                maxLines: 3,
                decoration: InputDecoration(labelText: L10n.text('Notes')),
              ),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: lead['converted_customer_uuid'] != null
                    ? null
                    : () async {
                        if (nameEditor.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Lead name is required.'),
                            ),
                          );
                          return;
                        }
                        if (selectedStage == 'lost' &&
                            lostReasonEditor.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Enter a reason before marking this lead lost.',
                              ),
                            ),
                          );
                          return;
                        }
                        await controller.updateOpportunity(
                          lead,
                          name: nameEditor.text,
                          contactPerson: contactEditor.text,
                          phone: phoneEditor.text,
                          email: emailEditor.text,
                          address: addressEditor.text,
                          source: selectedSource,
                          stage: selectedStage,
                          priority: selectedPriority,
                          estimatedValue: double.tryParse(
                            valueEditor.text.trim(),
                          ),
                          currency: currencyEditor.text.trim().isEmpty
                              ? 'AFN'
                              : currencyEditor.text,
                          expectedCloseDate: expectedCloseDate,
                          lostReason: lostReasonEditor.text,
                          notes: notesEditor.text,
                        );
                        if (sheetContext.mounted) {
                          Navigator.pop(sheetContext);
                        }
                      },
                child: const Text('Save changes'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  await _activity(context, lead);
                  activityRows = await controller.activities(uuid);
                  if (sheetContext.mounted) setModalState(() {});
                },
                icon: const Icon(Icons.add_comment_outlined),
                label: const Text('Add activity'),
              ),
              if (lead['converted_customer_uuid'] == null) ...[
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () async {
                    await controller.convert(lead);
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  },
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('Convert to customer'),
                ),
              ],
              const SizedBox(height: 22),
              const Text(
                'Activity timeline',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              if (activityRows.isEmpty)
                const Text('No activity cached yet.')
              else
                ...activityRows.map(
                  (row) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.timeline_outlined),
                    title: Text(_label(row['type']?.toString() ?? 'note')),
                    subtitle: Text(row['notes']?.toString() ?? ''),
                    trailing: row['sync_status'] == 'synced'
                        ? null
                        : const Icon(Icons.cloud_upload_outlined, size: 18),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    nameEditor.dispose();
    contactEditor.dispose();
    phoneEditor.dispose();
    emailEditor.dispose();
    addressEditor.dispose();
    valueEditor.dispose();
    currencyEditor.dispose();
    lostReasonEditor.dispose();
    notesEditor.dispose();
  }

  Future<void> _activity(
    BuildContext context,
    Map<String, dynamic> lead,
  ) async {
    final notes = TextEditingController();
    var type = 'note';
    const types = ['note', 'call', 'meeting', 'visit', 'other'];
    final save =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, setModalState) => AlertDialog(
              title: const Text('Add lead activity'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    items: types
                        .map(
                          (item) => DropdownMenuItem(
                            value: item,
                            child: Text(_label(item)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setModalState(() => type = value ?? type),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notes,
                    autofocus: true,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: L10n.text('What happened?'),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    if (notes.text.trim().isNotEmpty) {
                      Navigator.pop(dialogContext, true);
                    }
                  },
                  child: const Text('Save offline'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (!save || !context.mounted) return;
    await context.read<LeadController>().addActivity(lead, type, notes.text);
  }

  static DateTime? _parseDate(dynamic value) {
    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  static String _dateLabel(DateTime? value) {
    if (value == null) return 'Not set';
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  static String _label(String value) => value
      .split('_')
      .map(
        (part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}',
      )
      .join(' ');

  static String _number(dynamic value) {
    final number = value is num ? value.toDouble() : double.tryParse('$value');
    return number == null
        ? '$value'
        : number.toStringAsFixed(number.truncateToDouble() == number ? 0 : 2);
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}
