import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/mileage/mileage_repository.dart';
import '../state/app_state.dart';

class MileageScreen extends StatefulWidget {
  const MileageScreen({super.key});

  @override
  State<MileageScreen> createState() => _MileageScreenState();
}

class _MileageScreenState extends State<MileageScreen> {
  bool _loading = true;
  String? _message;
  List<Map<String, dynamic>> _rows = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading && _rows.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  Future<void> _load() async {
    final tenantId = context.read<AppState>().session?.tenantId;
    if (tenantId == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _message = 'Signed-in tenant is unavailable.';
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _loading = true;
        _message = null;
      });
    }

    try {
      final rows = await context.read<MileageRepository>().history(tenantId);

      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = '$error';
      });
    }
  }

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _costs(dynamic raw) {
    if (raw is! Map || raw.isEmpty) return 'No approved fuel cost';
    return raw.entries
        .map(
          (entry) => '${entry.key} ${_number(entry.value).toStringAsFixed(2)}',
        )
        .join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final today = _rows.isEmpty ? null : _rows.first;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (_message != null) ...[
              Card(
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(_message!),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (today != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.local_gas_station_outlined),
                          const SizedBox(width: 8),
                          Text(
                            'Today',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          Chip(
                            label: Text(
                              today['source'] == 'server'
                                  ? 'Server summary'
                                  : 'Offline estimate',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _Metric(
                            label: 'Distance',
                            value:
                                '${_number(today['effective_distance_km']).toStringAsFixed(1)} km',
                          ),
                          _Metric(
                            label: 'GPS',
                            value:
                                '${_number(today['gps_distance_km']).toStringAsFixed(1)} km',
                          ),
                          _Metric(
                            label: 'Fuel',
                            value:
                                '${_number(today['fuel_liters']).toStringAsFixed(2)} L',
                          ),
                          _Metric(
                            label: 'Efficiency',
                            value: today['km_per_liter'] == null
                                ? '—'
                                : '${_number(today['km_per_liter']).toStringAsFixed(2)} km/L',
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        today['vehicle_reference']?.toString().isNotEmpty ==
                                true
                            ? 'Vehicle: ${today['vehicle_reference']}'
                            : 'No vehicle reference recorded.',
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _costs(today['fuel_cost_by_currency']),
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              'Recent mileage',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            if (!_loading && _rows.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'No mileage is available yet. Start and end a work day to create a record.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ..._rows.map((row) {
              final odometer = row['odometer_distance_km'];
              final variance = row['distance_variance_km'];
              final local = row['source'] != 'server';

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Icon(
                        local ? Icons.offline_bolt_outlined : Icons.route,
                      ),
                    ),
                    title: Text(
                      '${row['date'] ?? 'Mileage'} · '
                      '${_number(row['effective_distance_km']).toStringAsFixed(1)} km',
                    ),
                    subtitle: Text(
                      [
                        if (row['vehicle_reference'] != null)
                          'Vehicle: ${row['vehicle_reference']}',
                        'GPS ${_number(row['gps_distance_km']).toStringAsFixed(1)} km',
                        if (odometer != null)
                          'Odometer ${_number(odometer).toStringAsFixed(1)} km',
                        if (variance != null)
                          'Variance ${_number(variance).toStringAsFixed(1)} km',
                        if (_number(row['fuel_liters']) > 0)
                          'Fuel ${_number(row['fuel_liters']).toStringAsFixed(2)} L',
                      ].join(' · '),
                    ),
                    isThreeLine: true,
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  'GPS distance filters mock locations, low-accuracy points, '
                  'and implausible movement. When start and end odometer '
                  'readings exist, odometer distance is used for efficiency '
                  'while GPS stays the reconciliation baseline.',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 132,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
