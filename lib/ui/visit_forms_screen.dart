import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/visits/visit_repository.dart';
import '../state/app_state.dart';
import '../state/visit_controller.dart';

class VisitFormsScreen extends StatefulWidget {
  const VisitFormsScreen({required this.visit, super.key});

  final Map<String, dynamic> visit;

  @override
  State<VisitFormsScreen> createState() => _VisitFormsScreenState();
}

class _VisitFormsScreenState extends State<VisitFormsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _forms = const [];

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    final tenantId = context.read<AppState>().session?.tenantId;
    if (tenantId == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final forms = await context.read<VisitRepository>().applicableForms(
        tenantId,
        customerUuid: widget.visit['customer_uuid'].toString(),
        visitOfflineUuid: widget.visit['offline_uuid'].toString(),
      );

      if (mounted) setState(() => _forms = forms);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Map<String, dynamic> form) async {
    final submission = form['local_submission'];
    if (submission is Map && submission['sync_status'] == 'synced') return;

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            VisitFormEntryScreen(visit: widget.visit, template: form),
      ),
    );

    if (saved == true && mounted) {
      await context.read<VisitController>().sync(silent: true);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Visit forms')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            )
          : _forms.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No visit forms apply to this customer.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _forms.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, index) {
                  final form = _forms[index];
                  final submission = form['local_submission'];
                  final submitted = submission is Map;
                  final status = submitted
                      ? (submission['sync_status'] ?? 'pending').toString()
                      : null;
                  final editable = !submitted || status != 'synced';

                  return Card(
                    child: ListTile(
                      onTap: editable ? () => _open(form) : null,
                      leading: Icon(
                        status == 'synced'
                            ? Icons.check_circle_outline
                            : submitted
                            ? Icons.error_outline
                            : Icons.fact_check_outlined,
                      ),
                      title: Text((form['name'] ?? 'Visit form').toString()),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if ((form['description'] ?? '')
                              .toString()
                              .trim()
                              .isNotEmpty)
                            Text(form['description'].toString()),
                          const SizedBox(height: 4),
                          Text(
                            [
                              if (form['required_on_checkout'] == true)
                                'Required before checkout',
                              if (submitted) 'Saved · $status',
                              if (submitted && status != 'synced')
                                'Tap to edit and retry',
                            ].join(' · '),
                          ),
                          if (submitted &&
                              status != 'synced' &&
                              (submission['last_error'] ?? '')
                                  .toString()
                                  .trim()
                                  .isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                submission['last_error'].toString(),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                        ],
                      ),
                      trailing: editable
                          ? const Icon(Icons.chevron_right)
                          : null,
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class VisitFormEntryScreen extends StatefulWidget {
  const VisitFormEntryScreen({
    required this.visit,
    required this.template,
    super.key,
  });

  final Map<String, dynamic> visit;
  final Map<String, dynamic> template;

  @override
  State<VisitFormEntryScreen> createState() => _VisitFormEntryScreenState();
}

class _VisitFormEntryScreenState extends State<VisitFormEntryScreen> {
  final Map<String, dynamic> _answers = {};
  final Map<String, TextEditingController> _controllers = {};
  List<Map<String, dynamic>> _photos = const [];
  bool _saving = false;
  String? _error;

  List<Map<String, dynamic>> get _questions {
    final raw = widget.template['questions'];
    if (raw is! List) return const [];

    return raw.whereType<Map>().map(Map<String, dynamic>.from).toList();
  }

  @override
  void initState() {
    super.initState();

    final submission = widget.template['local_submission'];
    final previousAnswers = submission is Map && submission['answers'] is List
        ? List<dynamic>.from(submission['answers'] as List)
        : const <dynamic>[];

    for (final raw in previousAnswers) {
      if (raw is! Map || raw['question_id'] == null) continue;
      _answers[raw['question_id'].toString()] = raw['value'];
    }

    for (final question in _questions) {
      final id = question['id'].toString();
      final type = question['type']?.toString();
      if (type == 'text' || type == 'textarea' || type == 'number') {
        _controllers[id] = TextEditingController(
          text: _answers[id]?.toString() ?? '',
        );
      }
    }

    Future.microtask(_loadPhotos);
  }

  Future<void> _loadPhotos() async {
    final tenantId = context.read<AppState>().session?.tenantId;
    if (tenantId == null) return;

    final photos = await context.read<VisitRepository>().visitPhotos(
      tenantId,
      widget.visit['offline_uuid'].toString(),
    );

    if (mounted) setState(() => _photos = photos);
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  bool _blank(dynamic value) {
    if (value == null) return true;
    if (value is String) return value.trim().isEmpty;
    if (value is List) return value.isEmpty;
    return false;
  }

  String? _validate() {
    for (final question in _questions) {
      final id = question['id'].toString();
      final type = question['type']?.toString();
      dynamic value = _answers[id];

      if (_controllers.containsKey(id)) {
        value = _controllers[id]!.text.trim();
        _answers[id] = value;
      }

      if (question['required'] == true && _blank(value)) {
        return '${question['label']} is required.';
      }

      if (_blank(value)) continue;

      if (type == 'number') {
        final number = num.tryParse(value.toString());
        if (number == null) {
          return '${question['label']} must be a number.';
        }

        final validation = question['validation'] is Map
            ? Map<String, dynamic>.from(question['validation'] as Map)
            : const <String, dynamic>{};
        final min = validation['min'] as num?;
        final max = validation['max'] as num?;

        if (min != null && number < min) {
          return '${question['label']} is below the minimum.';
        }
        if (max != null && number > max) {
          return '${question['label']} is above the maximum.';
        }

        _answers[id] = number;
      }
    }

    return null;
  }

  Future<void> _save() async {
    if (_saving) return;

    final validationError = _validate();
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }

    final tenantId = context.read<AppState>().session?.tenantId;
    if (tenantId == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final answers = <Map<String, dynamic>>[];

      for (final question in _questions) {
        final id = question['id'].toString();
        final value = _answers[id];
        if (_blank(value)) continue;

        answers.add({'question_id': id, 'value': value});
      }

      await context.read<VisitRepository>().saveFormSubmissionLocal(
        tenantId: tenantId,
        visit: widget.visit,
        template: widget.template,
        answers: answers,
      );

      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _question(Map<String, dynamic> question) {
    final id = question['id'].toString();
    final type = question['type']?.toString() ?? 'text';
    final label =
        '${question['label'] ?? 'Question'}${question['required'] == true ? ' *' : ''}';
    final help = question['help_text']?.toString();

    late Widget field;

    switch (type) {
      case 'textarea':
        field = TextField(
          controller: _controllers[id],
          maxLines: 4,
          decoration: InputDecoration(labelText: label),
        );
        break;
      case 'number':
        field = TextField(
          controller: _controllers[id],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label),
        );
        break;
      case 'yes_no':
        field = DropdownButtonFormField<bool>(
          initialValue: _answers[id] as bool?,
          decoration: InputDecoration(labelText: label),
          items: const [
            DropdownMenuItem(value: true, child: Text('Yes')),
            DropdownMenuItem(value: false, child: Text('No')),
          ],
          onChanged: (value) => setState(() => _answers[id] = value),
        );
        break;
      case 'single_choice':
        final options = (question['options'] as List? ?? const [])
            .map((value) => value.toString())
            .toList();
        field = DropdownButtonFormField<String>(
          initialValue: _answers[id]?.toString(),
          decoration: InputDecoration(labelText: label),
          items: options
              .map(
                (option) =>
                    DropdownMenuItem(value: option, child: Text(option)),
              )
              .toList(),
          onChanged: (value) => setState(() => _answers[id] = value),
        );
        break;
      case 'multi_choice':
        final options = (question['options'] as List? ?? const [])
            .map((value) => value.toString())
            .toList();
        final selected = (_answers[id] as List? ?? const [])
            .map((value) => value.toString())
            .toSet();
        field = InputDecorator(
          decoration: InputDecoration(labelText: label),
          child: Wrap(
            spacing: 8,
            children: options
                .map(
                  (option) => FilterChip(
                    label: Text(option),
                    selected: selected.contains(option),
                    onSelected: (enabled) {
                      setState(() {
                        final next = {...selected};
                        if (enabled) {
                          next.add(option);
                        } else {
                          next.remove(option);
                        }
                        _answers[id] = next.toList();
                      });
                    },
                  ),
                )
                .toList(),
          ),
        );
        break;
      case 'date':
        final selected = _answers[id]?.toString();
        field = ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          subtitle: Text(selected ?? 'Select date'),
          trailing: const Icon(Icons.calendar_today_outlined),
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              firstDate: DateTime(2020),
              lastDate: DateTime(2100),
              initialDate: DateTime.now(),
            );
            if (date != null) {
              setState(
                () => _answers[id] =
                    '${date.year.toString().padLeft(4, '0')}-'
                    '${date.month.toString().padLeft(2, '0')}-'
                    '${date.day.toString().padLeft(2, '0')}',
              );
            }
          },
        );
        break;
      case 'photo':
        field = DropdownButtonFormField<String>(
          initialValue: _answers[id]?.toString(),
          decoration: InputDecoration(labelText: label),
          items: _photos
              .map(
                (photo) => DropdownMenuItem(
                  value: photo['client_uuid'].toString(),
                  child: Text(
                    'Photo · ${photo['captured_at'] ?? photo['client_uuid']}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: _photos.isEmpty
              ? null
              : (value) => setState(() => _answers[id] = value),
        );
        break;
      default:
        field = TextField(
          controller: _controllers[id],
          decoration: InputDecoration(labelText: label),
        );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          field,
          if (type == 'photo' && _photos.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Capture a visit photo first, then return to this form.',
              ),
            ),
          if (help != null && help.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(help, style: Theme.of(context).textTheme.bodySmall),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.template['name'].toString())),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if ((widget.template['description'] ?? '')
              .toString()
              .trim()
              .isNotEmpty) ...[
            Text(widget.template['description'].toString()),
            const SizedBox(height: 16),
          ],
          if (_error != null) ...[
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
          ],
          ..._questions.map(_question),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('Save form'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
