import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/retry.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config.dart';
import '../core/sync/connectivity_gate.dart';
import '../features/maps/offline_map_cache.dart';
import '../features/visits/visit_map_data.dart';
import '../state/attendance_controller.dart';
import '../state/visit_controller.dart';
import 'sync_refresh.dart';

const _kabul = LatLng(34.5553, 69.2075);

/// Limits the number of in-flight tile requests so an initial map fill does
/// not burst several simultaneous TLS handshakes through the device/emulator
/// NAT, which has been observed to reset such bursts as a group.
class _ThrottledHttpClient extends http.BaseClient {
  _ThrottledHttpClient(this._inner, this._maxConcurrent)
    : assert(_maxConcurrent > 0);

  final http.Client _inner;
  final int _maxConcurrent;

  final _waiters = Queue<Completer<void>>();
  int _active = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_active >= _maxConcurrent) {
      final completer = Completer<void>();
      _waiters.add(completer);
      await completer.future;
    }
    _active++;
    try {
      return await _inner.send(request);
    } finally {
      _active--;
      if (_waiters.isNotEmpty) _waiters.removeFirst().complete();
    }
  }

  @override
  void close() => _inner.close();
}

bool _retryableStatus(http.BaseResponse response) {
  const statuses = {408, 429, 500, 502, 503, 504};
  return statuses.contains(response.statusCode);
}

bool _retryableError(Object error, StackTrace stackTrace) {
  if (error is SocketException ||
      error is TlsException ||
      error is TimeoutException) {
    return true;
  }
  if (error is http.ClientException) {
    final message = error.message.toLowerCase();
    return message.contains('socketexception') ||
        message.contains('connection reset') ||
        message.contains('connection terminated') ||
        message.contains('handshake') ||
        message.contains('failed host lookup') ||
        message.contains('timeout');
  }
  return false;
}

Duration _retryDelay(int attempt) =>
    const Duration(milliseconds: 400) * (attempt + 1);

/// Process-lifetime HTTP client used for all map tiles. Shared so tile
/// requests stay throttled across map instances and avoid re-bursting after
/// the map widget is rebuilt.
final http.Client _tileHttpClient = RetryClient(
  _ThrottledHttpClient(http.Client(), 6),
  retries: 3,
  when: _retryableStatus,
  whenError: _retryableError,
  delay: _retryDelay,
);

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
  StreamSubscription<bool>? _connectivitySubscription;
  bool _locating = false;
  bool _centered = false;
  bool _online = true;
  int? _cacheBytes;

  final Map<TileCoordinates, int> _tileRetries = {};
  final Map<TileCoordinates, Timer> _tileRetryTimers = {};

  static const _maxTileRetries = 5;

  void _onTileError(TileImage tile, Object error, StackTrace? stackTrace) {
    final coordinates = tile.coordinates;
    final attempts = _tileRetries[coordinates] ?? 0;

    if (attempts >= _maxTileRetries) return;

    _tileRetries[coordinates] = attempts + 1;
    _tileRetryTimers[coordinates]?.cancel();
    _tileRetryTimers[coordinates] = Timer(
      Duration(seconds: 2 + attempts * 3),
      () {
        _tileRetryTimers.remove(coordinates);
        if (!mounted) return;
        tile.load();
      },
    );
  }

  List<MapCustomer> get _ordered => sortByDistance(widget.customers, _position);

  @override
  void initState() {
    super.initState();
    unawaited(_loadConnectivityAndCache());
    _connectivitySubscription = ConnectivityGate.instance.statusChanges.listen(
      (online) {
        if (mounted) {
          setState(() => _online = online);
        }
      },
    );
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
    _connectivitySubscription?.cancel();
    for (final timer in _tileRetryTimers.values) {
      timer.cancel();
    }
    _tileRetryTimers.clear();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _loadConnectivityAndCache() async {
    final online = await ConnectivityGate.instance.isOnline();
    final cacheBytes = await OfflineMapCache.sizeBytes();

    if (!mounted) {
      return;
    }

    setState(() {
      _online = online;
      _cacheBytes = cacheBytes;
    });
  }

  String _formatCacheSize(int? bytes) {
    if (bytes == null || bytes <= 0) {
      return 'no cached tiles yet';
    }

    final megabytes = bytes / (1024 * 1024);
    if (megabytes < 1) {
      return '${(bytes / 1024).round()} KB cached';
    }

    return '${megabytes.toStringAsFixed(megabytes < 10 ? 1 : 0)} MB cached';
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
              urlTemplate: AppConfig.tileUrlTemplate,
              userAgentPackageName: 'com.businessos.fieldpulse',
              errorTileCallback: _onTileError,
              evictErrorTileStrategy:
                  EvictErrorTileStrategy.notVisibleRespectMargin,
              tileProvider: NetworkTileProvider(
                httpClient: _tileHttpClient,
                cachingProvider: OfflineMapCache.provider,
                headers: {
                  'User-Agent':
                      'FieldPulse Sales Mobile/1.0 (field-sales-mobile; '
                      'https://fieldpulse.businessos.af)',
                },
              ),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${widget.customers.length} customers · '
                    '${widget.visitedCustomerIds.length} visited',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _online
                        ? 'Online map · ${_formatCacheSize(_cacheBytes)}'
                        : 'Offline map · cached tiles only',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
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
          right: 12,
          top: 72,
          child: FloatingActionButton.small(
            heroTag: 'visits-map-sync',
            onPressed: () =>
                unawaited(syncAndReload(context, triggerSource: 'map:visits')),
            child: const Icon(Icons.sync),
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
