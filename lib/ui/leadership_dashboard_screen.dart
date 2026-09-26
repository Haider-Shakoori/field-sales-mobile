import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../core/config.dart';
import '../state/app_state.dart';
import '../state/team_controller.dart';

const _kabul = LatLng(34.5553, 69.2075);

class LeadershipDashboardScreen extends StatefulWidget {
  const LeadershipDashboardScreen({super.key});

  @override
  State<LeadershipDashboardScreen> createState() =>
      _LeadershipDashboardScreenState();
}

class _LeadershipDashboardScreenState extends State<LeadershipDashboardScreen> {
  final _mapController = MapController();

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(context.read<TeamController>().refresh());
      }
    });
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _refresh() => context.read<TeamController>().refresh();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final team = context.watch<TeamController>();
    final roleLabel = app.isSalesManager ? 'Sales Manager' : 'Supervisor';

    return Scaffold(
      appBar: AppBar(
        title: Text('$roleLabel · FieldPulse'),
        actions: [
          IconButton(
            tooltip: 'Refresh team',
            onPressed: team.busy ? null : _refresh,
            icon: team.busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => context.read<AppState>().logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            Text(
              'Hello, ${app.session?.name ?? ''}',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              app.isSalesManager
                  ? 'Your supervisors and their field teams'
                  : 'Your assigned field-sales team',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (team.message != null) ...[
              const SizedBox(height: 12),
              _MessageCard(message: team.message!),
            ],
            const SizedBox(height: 18),
            _SummaryGrid(summary: team.summary),
            const SizedBox(height: 18),
            _TeamMap(mapController: _mapController, locations: team.locations),
            const SizedBox(height: 18),
            Text(
              'Reporting hierarchy',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (team.hierarchy.isEmpty)
              const _EmptyCard(
                icon: Icons.groups_outlined,
                text: 'No active reporting assignments found.',
              )
            else
              ...team.hierarchy.map((group) => _HierarchyCard(group: group)),
            const SizedBox(height: 18),
            Text(
              'Recent field activity',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (team.recentActivity.isEmpty)
              const _EmptyCard(
                icon: Icons.timeline_outlined,
                text: 'No recent team activity.',
              )
            else
              ...team.recentActivity
                  .take(12)
                  .map(
                    (row) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Icon(_activityIcon(row['type']?.toString())),
                        title: Text(
                          row['title']?.toString() ?? 'Activity',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          [
                                row['subtitle'],
                                row['status'],
                                _compactTimestamp(row['at']),
                              ]
                              .where(
                                (value) =>
                                    value != null &&
                                    value.toString().trim().isNotEmpty,
                              )
                              .join('\n'),
                        ),
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  IconData _activityIcon(String? type) {
    return switch (type) {
      'order' => Icons.receipt_long_outlined,
      'collection' => Icons.payments_outlined,
      'expense' => Icons.account_balance_wallet_outlined,
      'visit' => Icons.location_on_outlined,
      _ => Icons.timeline_outlined,
    };
  }

  String? _compactTimestamp(dynamic raw) {
    final parsed = DateTime.tryParse(raw?.toString() ?? '');
    if (parsed == null) return null;

    final local = parsed.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');

    return '${local.month}/${local.day} $hour:$minute';
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.summary});

  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    final salesmen = _map(summary['salesmen']);
    final visits = _map(summary['visits']);
    final orders = _map(summary['orders']);
    final collections = _map(summary['collections']);

    final cards = [
      (
        'Team',
        '${salesmen['total'] ?? 0}',
        '${salesmen['on_duty'] ?? 0} on duty',
        Icons.groups_outlined,
      ),
      (
        'Live',
        '${salesmen['live'] ?? 0}',
        '${salesmen['stale'] ?? 0} idle · ${salesmen['offline'] ?? 0} offline',
        Icons.location_searching,
      ),
      (
        'Visits',
        '${visits['completed'] ?? 0}',
        '${visits['active'] ?? 0} active',
        Icons.storefront_outlined,
      ),
      (
        'Orders',
        '${orders['approved_count'] ?? 0}',
        '${orders['pending_count'] ?? 0} pending',
        Icons.receipt_long_outlined,
      ),
      (
        'Collections',
        '${collections['verified_count'] ?? 0}',
        '${collections['pending_count'] ?? 0} pending',
        Icons.payments_outlined,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 12) / 2;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: cards
              .map(
                (card) => SizedBox(
                  width: width,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(card.$4, size: 22),
                          const SizedBox(height: 10),
                          Text(
                            card.$2,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            card.$1,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            card.$3,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Map<String, dynamic> _map(dynamic value) {
    return value is Map
        ? Map<String, dynamic>.from(value)
        : const <String, dynamic>{};
  }
}

class _TeamMap extends StatelessWidget {
  const _TeamMap({required this.mapController, required this.locations});

  final MapController mapController;
  final List<Map<String, dynamic>> locations;

  @override
  Widget build(BuildContext context) {
    final located = locations
        .map((row) {
          final raw = row['location'];
          if (raw is! Map) return null;
          final location = Map<String, dynamic>.from(raw);
          final latitude = _number(location['latitude']);
          final longitude = _number(location['longitude']);
          if (latitude == null || longitude == null) return null;

          return (row: row, point: LatLng(latitude, longitude));
        })
        .whereType<({Map<String, dynamic> row, LatLng point})>()
        .toList();

    final center = located.isEmpty ? _kabul : located.first.point;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                const Icon(Icons.map_outlined),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Team live map',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Text('${located.length}/${locations.length} located'),
              ],
            ),
          ),
          SizedBox(
            height: 330,
            child: FlutterMap(
              mapController: mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: located.isEmpty ? 11 : 12,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: AppConfig.tileUrlTemplate,
                  userAgentPackageName: 'com.businessos.fieldpulse',
                  maxZoom: 19,
                ),
                MarkerLayer(
                  markers: [
                    for (final item in located)
                      Marker(
                        point: item.point,
                        width: 52,
                        height: 62,
                        alignment: Alignment.topCenter,
                        child: Tooltip(
                          message:
                              item.row['salesman_name']?.toString() ??
                              'Salesman',
                          child: Icon(
                            Icons.location_on,
                            size: 50,
                            color: switch (item.row['status']?.toString()) {
                              'online' => Colors.green,
                              'idle' => Colors.orange,
                              _ => Colors.blueGrey,
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Text(
              'Green = online · orange = idle · grey = offline/stale location',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  double? _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}

class _HierarchyCard extends StatelessWidget {
  const _HierarchyCard({required this.group});

  final Map<String, dynamic> group;

  @override
  Widget build(BuildContext context) {
    final rows = group['salesmen'];
    final salesmen = rows is List
        ? rows
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
        : const <Map<String, dynamic>>[];

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: const CircleAvatar(
          child: Icon(Icons.supervisor_account_outlined),
        ),
        title: Text(
          group['supervisor_name']?.toString() ?? 'Supervisor',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text('${salesmen.length} salesmen'),
        children: salesmen
            .map(
              (salesman) => ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: Text(
                  salesman['salesman_name']?.toString() ?? 'Salesman',
                ),
                subtitle: Text(
                  [
                        salesman['employee_code'],
                        salesman['territory'],
                        salesman['route'],
                      ]
                      .where(
                        (value) =>
                            value != null && value.toString().trim().isNotEmpty,
                      )
                      .join(' · '),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(
          Icons.info_outline,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: Text(message),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}
