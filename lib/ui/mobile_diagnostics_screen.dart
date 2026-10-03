import 'package:field_sales_mobile/l10n/localized_material.dart';
import 'package:provider/provider.dart';

import '../features/devices/device_health_repository.dart';
import '../state/app_state.dart';
import 'fieldpulse_theme.dart';
import 'widgets/fieldpulse_ui.dart';

class MobileDiagnosticsScreen extends StatefulWidget {
  const MobileDiagnosticsScreen({super.key});

  @override
  State<MobileDiagnosticsScreen> createState() =>
      _MobileDiagnosticsScreenState();
}

class _MobileDiagnosticsScreenState extends State<MobileDiagnosticsScreen> {
  DeviceHealthResult? _result;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load({bool report = false}) async {
    final tenantId = context.read<AppState>().session?.tenantId;
    if (tenantId == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final repository = context.read<DeviceHealthRepository>();
      final result = report
          ? await repository.report(tenantId)
          : await repository.current(tenantId);

      if (!mounted) return;
      setState(() => _result = result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;

    return RefreshIndicator(
      onRefresh: () => _load(report: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          _StatusCard(
            status: result?.status ?? 'unknown',
            collectedAt: result?.collectedAt,
            loading: _loading,
            onRun: () => _load(report: true),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Could not upload diagnostics. Local checks are still available.\n$_error',
                ),
              ),
            ),
          ],
          if (result != null) ...[
            if (result.issues.isNotEmpty) ...[
              const SizedBox(height: 12),
              _IssuesCard(issues: result.issues),
            ],
            const SizedBox(height: 12),
            _MetricSection(
              title: 'Battery & background',
              icon: Icons.battery_6_bar_outlined,
              rows: [
                _MetricRow(
                  'Battery',
                  _percent(result.metrics['battery_level']),
                ),
                _MetricRow('Charging', _yesNo(result.metrics['is_charging'])),
                _MetricRow(
                  'Battery saver',
                  _onOff(result.metrics['power_save_mode']),
                ),
                _MetricRow(
                  'Battery optimization',
                  _optimization(result.metrics['battery_optimization_exempt']),
                ),
                _MetricRow(
                  'Background restricted',
                  _yesNo(result.metrics['background_restricted']),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _MetricSection(
              title: 'Location & tracking',
              icon: Icons.my_location_outlined,
              rows: [
                _MetricRow(
                  'Work day',
                  result.metrics['workday_active'] == true
                      ? 'Active'
                      : 'Inactive',
                ),
                _MetricRow(
                  'Location services',
                  _enabledDisabled(result.metrics['location_services_enabled']),
                ),
                _MetricRow(
                  'Location permission',
                  _humanize(result.metrics['location_permission']),
                ),
                _MetricRow(
                  'Background location',
                  _humanize(result.metrics['background_location_permission']),
                ),
                _MetricRow(
                  'Background tracking',
                  result.metrics['background_tracking_active'] == true
                      ? 'Active'
                      : 'Inactive',
                ),
                _MetricRow(
                  'Last GPS fix',
                  _time(result.metrics['last_gps_fix_at']),
                ),
                _MetricRow(
                  'Mock-location signal',
                  result.metrics['mock_location_detected'] == true
                      ? 'Detected'
                      : 'Not detected',
                ),
              ],
            ),
            const SizedBox(height: 12),
            _MetricSection(
              title: 'Connectivity & sync',
              icon: Icons.sync_outlined,
              rows: [
                _MetricRow(
                  'Network',
                  _humanize(result.metrics['network_type']),
                ),
                _MetricRow(
                  'Pending sync',
                  '${result.metrics['pending_sync_count'] ?? 0}',
                ),
                _MetricRow(
                  'Failed sync',
                  '${result.metrics['failed_sync_count'] ?? 0}',
                ),
                _MetricRow(
                  'Blocked sync',
                  '${result.metrics['blocked_sync_count'] ?? 0}',
                ),
                _MetricRow('Last sync', _time(result.metrics['last_sync_at'])),
              ],
            ),
            const SizedBox(height: 12),
            _MetricSection(
              title: 'Device & permissions',
              icon: Icons.phone_android_outlined,
              rows: [
                _MetricRow(
                  'Notifications',
                  _humanize(result.metrics['notification_permission']),
                ),
                _MetricRow(
                  'Physical device',
                  _yesNo(result.metrics['is_physical_device']),
                ),
                _MetricRow(
                  'Root/integrity signal',
                  result.metrics['root_signal_detected'] == true
                      ? 'Detected'
                      : 'Not detected',
                ),
                _MetricRow(
                  'Free storage',
                  _megabytes(result.metrics['storage_free_mb']),
                ),
                _MetricRow(
                  'Total storage',
                  _megabytes(result.metrics['storage_total_mb']),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Integrity and mock-location checks are diagnostic signals only. '
                  'They should be reviewed with other evidence before taking action.',
                ),
              ),
            ),
          ],
          if (_loading && result == null)
            const FieldPulsePremiumLoading(label: 'Checking device health…'),
        ],
      ),
    );
  }

  String _percent(dynamic value) => value == null ? 'Unknown' : '$value%';

  String _megabytes(dynamic value) => value == null ? 'Unknown' : '$value MB';

  String _yesNo(dynamic value) => switch (value) {
    true => 'Yes',
    false => 'No',
    _ => 'Unknown',
  };

  String _onOff(dynamic value) => switch (value) {
    true => 'On',
    false => 'Off',
    _ => 'Unknown',
  };

  String _enabledDisabled(dynamic value) => switch (value) {
    true => 'Enabled',
    false => 'Disabled',
    _ => 'Unknown',
  };

  String _optimization(dynamic value) => switch (value) {
    true => 'Exempt',
    false => 'Restricted',
    _ => 'Unknown',
  };

  String _humanize(dynamic value) {
    if (value == null) return 'Unknown';
    final raw = value.toString().trim();
    if (raw.isEmpty) return 'Unknown';

    return raw
        .replaceAll('_', ' ')
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  String _time(dynamic value) {
    if (value == null) return 'Never';
    final parsed = DateTime.tryParse(value.toString());
    if (parsed == null) return value.toString();

    return parsed.toLocal().toString().split('.').first;
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.status,
    required this.collectedAt,
    required this.loading,
    required this.onRun,
  });

  final String status;
  final DateTime? collectedAt;
  final bool loading;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'healthy' => const Color(0xFF27D7A1),
      'warning' => const Color(0xFFFFB547),
      'critical' => const Color(0xFFFF6B6B),
      _ => const Color(0xFF8FB2D6),
    };

    final label = status.isEmpty
        ? 'Unknown'
        : '${status[0].toUpperCase()}${status.substring(1)}';

    return FieldPulseHeroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const FieldPulseIconBadge(
                icon: Icons.health_and_safety_rounded,
                color: Color(0xFF7CC7FF),
                size: 50,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Mobile diagnostics',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      collectedAt == null
                          ? 'Inspect this phone and its field-work readiness.'
                          : 'Last checked ${collectedAt!.toLocal().toString().split('.').first}',
                      style: const TextStyle(
                        color: Color(0xFFBBD0E8),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              FieldPulseStatusPill(label: label, color: color),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: FieldPulseTheme.navy,
              ),
              onPressed: loading ? null : onRun,
              icon: loading
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: Text(loading ? 'Checking…' : 'Run diagnostics'),
            ),
          ),
        ],
      ),
    );
  }
}

class _IssuesCard extends StatelessWidget {
  const _IssuesCard({required this.issues});

  final List<Map<String, dynamic>> issues;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Needs attention',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          for (final issue in issues)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                issue['severity'] == 'critical'
                    ? Icons.error_outline
                    : issue['severity'] == 'warning'
                    ? Icons.warning_amber_outlined
                    : Icons.info_outline,
              ),
              title: Text(issue['message']?.toString() ?? 'Diagnostic issue'),
              subtitle: Text(
                '${issue['severity'] ?? 'info'} · ${issue['code'] ?? 'device_health'}',
              ),
            ),
        ],
      ),
    ),
  );
}

class _MetricSection extends StatelessWidget {
  const _MetricSection({
    required this.title,
    required this.icon,
    required this.rows,
  });

  final String title;
  final IconData icon;
  final List<_MetricRow> rows;

  @override
  Widget build(BuildContext context) => FieldPulseInfoCard(
    child: Column(
      children: [
        Row(
          children: [
            FieldPulseIconBadge(icon: icon),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const Divider(),
        const SizedBox(height: 8),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    row.label,
                    style: const TextStyle(color: FieldPulseTheme.muted),
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    row.value,
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                      color: FieldPulseTheme.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _MetricRow {
  const _MetricRow(this.label, this.value);

  final String label;
  final String value;
}
