import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../features/visits/visit_map_data.dart';
import '../state/attendance_controller.dart';
import '../state/visit_controller.dart';

const _kabul = LatLng(34.5553, 69.2075);
const _tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

class VisitsMapView extends StatefulWidget {
  const VisitsMapView({
    super.key,
    required this.customers,
    required this.visitedCustomerIds,
    required this.activeCustomerId,
  });

  final List<MapCustomer> customers;
  final Set<String> visitedCustomerIds;
  final String? activeCustomerId;

  @override
  State<VisitsMapView> createState() => _VisitsMapViewState();
}

class _VisitsMapViewState extends State<VisitsMapView> {
  final _mapController = MapController();

  LatLng? _position;
  Timer? _refreshTimer;
  bool _locating = false;
  bool _centered = false;

  List<MapCustomer> get _ordered => sortByDistance(widget.customers, _position);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_locate(moveCamera: true)),
    );
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => unawaited(_locate()),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _locate({bool moveCamera = false}) async {
    if (_locating) {
      return;
    }

    _locating = true;

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final fix = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 12));

      if (!mounted) {
        return;
      }

      final point = LatLng(fix.latitude, fix.longitude);
      setState(() => _position = point);

      if (moveCamera || !_centered) {
        _centered = true;
        _mapController.move(point, 14);
      }
    } catch (_) {
      // A map position is best-effort; cached customers remain browsable.
    } finally {
      _locating = false;
    }
  }

  Future<void> _navigate(MapCustomer customer) async {
    final coords =
        '${customer.point.latitude.toStringAsFixed(6)},${customer.point.longitude.toStringAsFixed(6)}';
    final candidates = <Uri>[
      Uri.parse('google.navigation:q=$coords'),
      Uri.parse('geo:$coords?q=$coords(${Uri.encodeComponent(customer.name)})'),
      Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$coords'),
    ];

    for (final uri in candidates) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          return;
        }
      } catch (_) {
        // Try the next navigation target.
      }
    }

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No navigation app is available.')),
    );
  }

  Future<void> _openCustomer(MapCustomer customer) async {
    final attendance = context.read<AttendanceController>();
    final visits = context.read<VisitController>();
    final messenger = ScaffoldMessenger.of(context);
    final distance = distanceMeters(customer, _position);
    final visited = widget.visitedCustomerIds.contains(customer.id);
    final active = widget.activeCustomerId == customer.id;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                customer.name,
                style: Theme.of(sheetContext).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (customer.address.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(customer.address),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (customer.plannedOrder != null)
                    Chip(
                      avatar: const Icon(Icons.route, size: 16),
                      label: Text(
                        'Stop ${customer.plannedOrder}'
                        '${customer.routeName == null ? '' : ' · ${customer.routeName}'}',
                      ),
                    ),
                  if (distance != null)
                    Chip(
                      avatar: const Icon(Icons.straighten, size: 16),
                      label: Text(formatDistance(distance)),
                    ),
                  if (active) const Chip(label: Text('Active visit')),
                  if (!active && visited) const Chip(label: Text('Visited')),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        unawaited(_navigate(customer));
                      },
                      icon: const Icon(Icons.navigation_outlined),
                      label: const Text('Navigate'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed:
                          active || visits.hasActiveVisit || !attendance.working
                          ? null
                          : () async {
                              Navigator.pop(sheetContext);
                              await visits.checkIn(customer.customer);
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    visits.message ??
                                        'Visit check-in saved locally.',
                                  ),
                                ),
                              );
                            },
                      icon: const Icon(Icons.add_location_alt_outlined),
                      label: Text(active ? 'Active' : 'Check in'),
                    ),
                  ),
                ],
              ),
              if (!attendance.working) ...[
                const SizedBox(height: 10),
                Text(
                  'Start your work day before checking in.',
                  style: TextStyle(color: Colors.orange.shade800),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Marker _customerMarker(MapCustomer customer) {
    final active = widget.activeCustomerId == customer.id;
    final visited = widget.visitedCustomerIds.contains(customer.id);

    final color = active
        ? Colors.indigo
        : visited
        ? Colors.green.shade600
        : customer.plannedOrder != null
        ? Colors.orange.shade700
        : Colors.blueGrey.shade600;

    return Marker(
      point: customer.point,
      width: 46,
      height: 56,
      alignment: Alignment.topCenter,
      child: GestureDetector(
        onTap: () => unawaited(_openCustomer(customer)),
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            Icon(Icons.location_on, size: 46, color: color),
            Positioned(
              top: 9,
              child: customer.plannedOrder != null
                  ? Text(
                      '${customer.plannedOrder}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : Icon(
                      visited ? Icons.check : Icons.storefront_outlined,
                      size: 14,
                      color: Colors.white,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ordered = _ordered;
    final closest = ordered.take(8).toList();
    final planned =
        widget.customers
            .where((customer) => customer.plannedOrder != null)
            .toList()
          ..sort((a, b) => a.plannedOrder!.compareTo(b.plannedOrder!));

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: widget.customers.isNotEmpty
                ? widget.customers.first.point
                : _kabul,
            initialZoom: 12,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: _tileUrl,
              userAgentPackageName: 'com.wesoft.fieldsales',
              maxZoom: 19,
            ),
            if (planned.length > 1)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: planned.map((customer) => customer.point).toList(),
                    color: Colors.indigo.withValues(alpha: 0.6),
                    strokeWidth: 3,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                for (final customer in widget.customers)
                  _customerMarker(customer),
                if (_position != null)
                  Marker(
                    point: _position!,
                    width: 26,
                    height: 26,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: const [
                          BoxShadow(blurRadius: 6, color: Colors.black26),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        Positioned(
          left: 12,
          top: 12,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                '${widget.customers.length} customers · '
                '${widget.visitedCustomerIds.length} visited',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
          ),
        ),
        Positioned(
          right: 12,
          top: 12,
          child: FloatingActionButton.small(
            heroTag: 'visits-map-locate',
            onPressed: () => unawaited(_locate(moveCamera: true)),
            child: const Icon(Icons.my_location),
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 84,
          child: Card(
            elevation: 3,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _position == null
                        ? 'Customers in planned order'
                        : 'Nearest first',
                    style: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 72,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: closest.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (_, index) {
                        final customer = closest[index];
                        final meters = distanceMeters(customer, _position);
                        final visited = widget.visitedCustomerIds.contains(
                          customer.id,
                        );

                        return InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            _mapController.move(customer.point, 15);
                            unawaited(_openCustomer(customer));
                          },
                          child: Container(
                            width: 172,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  customer.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  [
                                    if (customer.plannedOrder != null)
                                      'Stop ${customer.plannedOrder}',
                                    if (visited) 'Visited',
                                    if (meters != null) formatDistance(meters),
                                  ].join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '© OpenStreetMap contributors',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
