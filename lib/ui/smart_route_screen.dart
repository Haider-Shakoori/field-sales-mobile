import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../features/routes/daily_route_plan_repository.dart';
import '../state/app_state.dart';

class SmartRouteScreen extends StatefulWidget {
  const SmartRouteScreen({super.key});

  @override
  State<SmartRouteScreen> createState() => _SmartRouteScreenState();
}

class _SmartRouteScreenState extends State<SmartRouteScreen> {
  Map<String, dynamic>? _plan;
  DateTime? _cachedAt;
  bool _loading = true;
  bool _refreshing = false;
  String? _changingOpportunityId;
  String? _message;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    final tenantId = context.read<AppState>().session?.tenantId;
    if (tenantId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final repository = context.read<DailyRoutePlanRepository>();
    final cached = await repository.cached(tenantId);
    final cachedAt = await repository.cachedAt(tenantId);

    if (mounted) {
      setState(() {
        _plan = cached;
        _cachedAt = cachedAt;
        _loading = false;
      });
    }

    await _refresh();
  }

  Future<Position?> _currentPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;

      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 12));

      return position.accuracy <= 200 ? position : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _refresh() async {
    if (_refreshing) return;

    final tenantId = context.read<AppState>().session?.tenantId;
    if (tenantId == null) return;

    final repository = context.read<DailyRoutePlanRepository>();

    setState(() {
      _refreshing = true;
      _message = null;
    });

    try {
      final position = await _currentPosition();
      final plan = await repository.refresh(
        tenantId,
        latitude: position?.latitude,
        longitude: position?.longitude,
        accuracy: position?.accuracy,
      );

      if (!mounted) return;

      setState(() {
        _plan = plan;
        _cachedAt = DateTime.now().toUtc();
        _message = position == null
            ? 'Route refreshed. GPS was unavailable, so the server used business priority and the assigned route as the starting fallback.'
            : null;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _message = _plan == null
            ? 'Smart route is unavailable offline until it has been synced once.'
            : 'Offline mode: showing the last cached smart route.';
      });
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _addOpportunity(Map<String, dynamic> opportunity) async {
    final tenantId = context.read<AppState>().session?.tenantId;
    final customerId = opportunity['customer_id']?.toString();

    if (tenantId == null || customerId == null || customerId.isEmpty) return;

    setState(() => _changingOpportunityId = customerId);

    try {
      final repository = context.read<DailyRoutePlanRepository>();
      await repository.includeOpportunity(tenantId, customerId);
      await _refresh();

      if (mounted) {
        setState(() {
          _message = 'Opportunity added to today\'s route and re-optimized from your current position.';
        });
      }
    } finally {
      if (mounted) setState(() => _changingOpportunityId = null);
    }
  }

  Future<void> _removeOpportunity(Map<String, dynamic> stop) async {
    final tenantId = context.read<AppState>().session?.tenantId;
    final customerId = stop['customer_id']?.toString();

    if (tenantId == null || customerId == null || customerId.isEmpty) return;

    setState(() => _changingOpportunityId = customerId);

    try {
      final repository = context.read<DailyRoutePlanRepository>();
      await repository.removeOpportunity(tenantId, customerId);
      await _refresh();

      if (mounted) {
        setState(() {
          _message = 'Extra opportunity stop removed from today\'s route.';
        });
      }
    } finally {
      if (mounted) setState(() => _changingOpportunityId = null);
    }
  }

  List<Map<String, dynamic>> get _opportunities {
    final raw = _plan?['nearby_opportunities'];
    if (raw is! List) return const [];

    return raw.whereType<Map>().map(Map<String, dynamic>.from).toList();
  }

  Map<String, dynamic> get _dynamicRoute {
    final raw = _plan?['dynamic_route'];

    return raw is Map
        ? Map<String, dynamic>.from(raw)
        : const <String, dynamic>{};
  }

  List<Map<String, dynamic>> get _stops {
    final raw = _plan?['stops'];
    if (raw is! List) return const [];

    return raw.whereType<Map>().map(Map<String, dynamic>.from).toList();
  }

  Map<String, dynamic> get _summary {
    final raw = _plan?['summary'];
    return raw is Map
        ? Map<String, dynamic>.from(raw)
        : const <String, dynamic>{};
  }

  Map<String, dynamic> get _schedule {
    final raw = _plan?['schedule'];
    return raw is Map
        ? Map<String, dynamic>.from(raw)
        : const <String, dynamic>{};
  }

  String? _clock(dynamic iso) {
    final parsed = DateTime.tryParse(iso?.toString() ?? '');
    if (parsed == null) return null;
    final local = parsed.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _priorityLabel(String value) => switch (value) {
    'urgent' => 'Urgent',
    'high' => 'High',
    'elevated' => 'Elevated',
    'completed' => 'Visited',
    _ => 'Normal',
  };

  Widget _metric(String label, dynamic value) => Chip(
    label: Text('$label ${value ?? 0}'),
    visualDensity: VisualDensity.compact,
  );

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final plan = _plan;
    final source = plan?['source'] is Map
        ? Map<String, dynamic>.from(plan!['source'] as Map)
        : const <String, dynamic>{};
    final route = plan?['route'] is Map
        ? Map<String, dynamic>.from(plan!['route'] as Map)
        : const <String, dynamic>{};
    final start = plan?['start_location'] is Map
        ? Map<String, dynamic>.from(plan!['start_location'] as Map)
        : null;
    final distance = plan?['approximate_air_distance_km'];
    final included =
        (_dynamicRoute['included_opportunity_ids'] as List? ?? const []).length;
    final radius = _dynamicRoute['nearby_radius_km'] ?? 5;
    final enabled = plan?['enabled'] != false;
    final capacityUtilization =
        (_summary['capacity_utilization_percent'] as num?)?.toDouble();
    final overflowStops = (_summary['overflow_stops'] as num?)?.toInt() ?? 0;

    if (!enabled) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.alt_route),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Smart route planning is disabled',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (_refreshing)
                          const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Your company has turned off route optimization in FieldPulse settings. Your assigned customers, routes, visits, and normal field work are unchanged.',
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        onPressed: _refreshing ? null : _refresh,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Refresh setting'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(_message!),
                ),
              ),
            ],
            const SizedBox(height: 80),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.alt_route),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          route['name']?.toString() ??
                              source['name']?.toString() ??
                              "Today's smart route",
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (_refreshing)
                        const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    [
                      if (plan?['date'] != null) plan!['date'].toString(),
                      if (source['type'] != null) 'Source: ${source['type']}',
                      if (distance != null) '~$distance km',
                    ].join(' · '),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    start != null
                        ? 'Live route: optimized from your current GPS position, business priority, and proximity.'
                        : 'Optimized by business priority and proximity. Re-optimize when GPS is available.',
                  ),
                  if (_cachedAt != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Cached ${_cachedAt!.toLocal()}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _metric('Stops', _summary['total_stops']),
                      _metric('Remaining', _summary['remaining']),
                      _metric('Urgent', _summary['urgent']),
                      _metric('High', _summary['high']),
                      _metric('Visited', _summary['visited']),
                      _metric(
                        'Travel',
                        '${_summary['estimated_travel_minutes'] ?? 0} min',
                      ),
                      if (capacityUtilization != null)
                        _metric(
                          'Route load',
                          '${capacityUtilization.toStringAsFixed(0)}%',
                        ),
                      if (overflowStops > 0) _metric('Overflow', overflowStops),
                      if (included > 0) _metric('Extra', included),
                    ],
                  ),
                  if (_schedule.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      overflowStops > 0
                          ? '$overflowStops stop(s) exceed the configured workday capacity. Consider removing optional stops or reprioritizing the remaining route.'
                          : 'The remaining route fits within the configured workday capacity.',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: _refreshing ? null : _refresh,
                      icon: const Icon(Icons.my_location),
                      label: const Text('Re-optimize now'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(_message!),
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (_stops.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    "No customers are available in today's assigned route or territory.",
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            )
          else
            ..._stops.map((stop) {
              final reasons = (stop['reasons'] as List? ?? const [])
                  .map((value) => value.toString())
                  .toList();
              final overdue = (stop['overdue'] as List? ?? const [])
                  .whereType<Map>()
                  .map((row) {
                    final currency = row['currency']?.toString() ?? '';
                    final amount = row['overdue'];
                    return amount is num && amount > 0
                        ? '$currency $amount overdue'
                        : null;
                  })
                  .whereType<String>()
                  .toList();
              final visited = stop['visited_today'] == true;
              final opportunity = stop['is_opportunity'] == true;
              final customerId = stop['customer_id']?.toString();
              final changing =
                  customerId != null && customerId == _changingOpportunityId;
              final priority = stop['priority']?.toString() ?? 'normal';

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          child: visited
                              ? const Icon(Icons.check)
                              : Text(
                                  (stop['recommended_order'] ?? '-').toString(),
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
                                      stop['customer_name']?.toString() ??
                                          'Customer',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  ),
                                  Chip(
                                    label: Text(_priorityLabel(priority)),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ],
                              ),
                              if (opportunity)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Text(
                                    'Extra opportunity stop',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ),
                              if ((stop['address'] ?? '')
                                  .toString()
                                  .trim()
                                  .isNotEmpty)
                                Text(stop['address'].toString()),
                              const SizedBox(height: 6),
                              Text(
                                [
                                  if (stop['distance_from_previous_km'] != null)
                                    '${stop['distance_from_previous_km']} km from previous',
                                  if ((stop['estimated_travel_minutes']
                                              as num?) !=
                                          null &&
                                      (stop['estimated_travel_minutes']
                                              as num) >
                                          0)
                                    '~${stop['estimated_travel_minutes']} min travel',
                                  if (stop['planned_visit_minutes'] != null)
                                    '${stop['planned_visit_minutes']} min visit',
                                  if (stop['route_sequence'] != null)
                                    'Route #${stop['route_sequence']}',
                                ].join(' · '),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              if (!visited &&
                                  stop['estimated_arrival_at'] != null) ...[
                                const SizedBox(height: 5),
                                Text(
                                  [
                                    'ETA ${_clock(stop['estimated_arrival_at']) ?? '-'}',
                                    if (_clock(
                                          stop['estimated_departure_at'],
                                        ) !=
                                        null)
                                      'finish ${_clock(stop['estimated_departure_at'])}',
                                    if (stop['capacity_status'] == 'overflow')
                                      'outside planned capacity',
                                  ].join(' · '),
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ],
                              if (reasons.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(reasons.join(' · ')),
                              ],
                              if (overdue.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  overdue.join(' · '),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                              if (opportunity && !visited) ...[
                                const SizedBox(height: 10),
                                TextButton.icon(
                                  onPressed: changing
                                      ? null
                                      : () => _removeOpportunity(stop),
                                  icon: changing
                                      ? const SizedBox.square(
                                          dimension: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.remove_circle_outline),
                                  label: const Text('Remove extra stop'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          if (_opportunities.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Nearby opportunities',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  'within ${radius.toString()} km',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Nearby customers inside your assignment scope but outside today\'s assigned route. Add one only when it makes business sense.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            ..._opportunities.map((opportunity) {
              final reasons = (opportunity['reasons'] as List? ?? const [])
                  .map((value) => value.toString())
                  .toList();
              final customerId = opportunity['customer_id']?.toString();
              final changing =
                  customerId != null && customerId == _changingOpportunityId;
              final priority = opportunity['priority']?.toString() ?? 'normal';

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const CircleAvatar(
                              child: Icon(Icons.near_me_outlined),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                opportunity['customer_name']?.toString() ??
                                    'Customer',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ),
                            Chip(
                              label: Text(_priorityLabel(priority)),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${opportunity['distance_km']?.toString() ?? '-'} km away',
                        ),
                        if ((opportunity['address'] ?? '')
                            .toString()
                            .trim()
                            .isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(opportunity['address'].toString()),
                        ],
                        if (reasons.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            reasons.join(' · '),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: changing
                                ? null
                                : () => _addOpportunity(opportunity),
                            icon: changing
                                ? const SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.add_road),
                            label: const Text('Add to today\'s route'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}
