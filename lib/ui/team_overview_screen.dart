import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../core/config.dart';
import '../state/management_controller.dart';

const _kabul = LatLng(34.5553, 69.2075);

class TeamOverviewScreen extends StatelessWidget {
  const TeamOverviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ManagementController>();
    final rawMembers = state.overview?['members'];
    final members = rawMembers is List
        ? rawMembers
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList(growable: false)
        : const <Map<String, dynamic>>[];

    final located = members
        .where((member) {
          final location = member['location'];
          return location is Map &&
              _number(location['latitude']) != null &&
              _number(location['longitude']) != null;
        })
        .toList(growable: false);

    return RefreshIndicator(
      onRefresh: () => context.read<ManagementController>().refresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          if (located.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                height: 300,
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: _mapCenter(located),
                    initialZoom: 11,
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
                      markers: [for (final member in located) _marker(member)],
                    ),
                    const RichAttributionWidget(
                      attributions: [
                        TextSourceAttribution('OpenStreetMap contributors'),
                      ],
                    ),
                  ],
                ),
              ),
            )
          else
            const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Row(
                  children: [
                    Icon(Icons.location_off_outlined),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'No current team locations are available yet.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          Text(
            '${members.length} team members',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          for (final member in members) ...[
            _MemberCard(member: member),
            const SizedBox(height: 8),
          ],
          if (members.isEmpty && state.busy)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  static Marker _marker(Map<String, dynamic> member) {
    final location = Map<String, dynamic>.from(member['location'] as Map);
    final status = member['work_status']?.toString() ?? 'not_started';
    final color = status == 'working'
        ? Colors.green
        : status == 'completed'
        ? Colors.indigo
        : Colors.grey;

    return Marker(
      point: LatLng(
        _number(location['latitude'])!,
        _number(location['longitude'])!,
      ),
      width: 52,
      height: 58,
      alignment: Alignment.topCenter,
      child: Tooltip(
        message: member['name']?.toString() ?? 'Salesman',
        child: Icon(Icons.location_on, size: 48, color: color),
      ),
    );
  }

  static LatLng _mapCenter(List<Map<String, dynamic>> members) {
    var lat = 0.0;
    var lng = 0.0;
    var count = 0;

    for (final member in members) {
      final location = member['location'];
      if (location is! Map) continue;
      final item = Map<String, dynamic>.from(location);
      final itemLat = _number(item['latitude']);
      final itemLng = _number(item['longitude']);
      if (itemLat == null || itemLng == null) continue;
      lat += itemLat;
      lng += itemLng;
      count++;
    }

    return count == 0 ? _kabul : LatLng(lat / count, lng / count);
  }

  static double? _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({required this.member});

  final Map<String, dynamic> member;

  @override
  Widget build(BuildContext context) {
    final orders = _map(member['orders']);
    final collections = _map(member['collections']);
    final status = member['work_status']?.toString() ?? 'not_started';

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  child: Text(
                    (member['name']?.toString().trim().isNotEmpty == true
                            ? member['name'].toString().trim()[0]
                            : '?')
                        .toUpperCase(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        member['name']?.toString() ?? 'Salesman',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        [
                              member['employee_code'],
                              _nestedName(member['route']),
                              _nestedName(member['territory']),
                            ]
                            .where(
                              (value) => value != null && value!.isNotEmpty,
                            )
                            .join(' · '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                _StatusChip(status: status),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MiniMetric(
                  icon: Icons.storefront_outlined,
                  text: '${member['visits'] ?? 0} visits',
                ),
                _MiniMetric(
                  icon: Icons.receipt_long_outlined,
                  text: '${orders['count'] ?? 0} orders',
                ),
                _MiniMetric(
                  icon: Icons.payments_outlined,
                  text: '${collections['count'] ?? 0} collections',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : const {};

  static String? _nestedName(dynamic value) {
    if (value is! Map) return null;
    return value['name']?.toString();
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final label = status == 'working'
        ? 'Working'
        : status == 'completed'
        ? 'Done'
        : 'Not started';
    final color = status == 'working'
        ? Colors.green
        : status == 'completed'
        ? Colors.indigo
        : Colors.grey;

    return Chip(
      avatar: Icon(Icons.circle, size: 10, color: color),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15),
        const SizedBox(width: 5),
        Text(text, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}
