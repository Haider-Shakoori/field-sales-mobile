import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../core/config.dart';
import '../state/master_data_controller.dart';

const _kabulCenter = LatLng(34.5553, 69.2075);

class CustomerCreateScreen extends StatefulWidget {
  const CustomerCreateScreen({super.key});

  @override
  State<CustomerCreateScreen> createState() => _CustomerCreateScreenState();
}

class _CustomerCreateScreenState extends State<CustomerCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _mapController = MapController();
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();

  LatLng? _shopLocation;
  bool _locating = false;
  bool _saving = false;
  String? _locationMessage;

  @override
  void dispose() {
    _mapController.dispose();
    _name.dispose();
    _code.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    if (_locating) return;

    setState(() {
      _locating = true;
      _locationMessage = null;
    });

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw StateError('Turn on location services and try again.');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        throw StateError(
          'Location permission is permanently denied. Enable it in phone settings or tap the shop on the map.',
        );
      }

      if (permission == LocationPermission.denied) {
        throw StateError(
          'Location permission was denied. Allow it or tap the shop on the map.',
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 12));

      if (!mounted) return;

      final point = LatLng(position.latitude, position.longitude);
      setState(() {
        _shopLocation = point;
        _locationMessage =
            'Current location selected. Drag the map and tap again if the shop entrance is slightly different.';
      });
      _mapController.move(point, 18);
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _locationMessage =
              'Could not get a precise GPS fix. Move to an open area or tap the shop on the map.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _locationMessage = error
              .toString()
              .replaceFirst('Bad state: ', '')
              .replaceFirst('StateError: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _selectLocation(LatLng point) {
    setState(() {
      _shopLocation = point;
      _locationMessage = 'Shop location selected.';
    });
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;

    if (_shopLocation == null) {
      setState(() {
        _locationMessage =
            'Select the exact shop location on the map before saving.';
      });
      return;
    }

    setState(() => _saving = true);

    try {
      await context.read<MasterDataController>().createCustomer(
        name: _name.text,
        code: _code.text,
        phone: _phone.text,
        address: _address.text,
        latitude: _shopLocation!.latitude,
        longitude: _shopLocation!.longitude,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _locationMessage =
            'The customer could not be saved. Your entry is still on this screen; please try again.';
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _shopLocation;

    return Scaffold(
      appBar: AppBar(title: const Text('New customer')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Customer / shop name',
                  prefixIcon: Icon(Icons.storefront_outlined),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Customer name is required.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _code,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Code (optional)',
                  prefixIcon: Icon(Icons.tag_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _address,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Address',
                  prefixIcon: Icon(Icons.home_work_outlined),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Shop location',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Tap the exact shop on the map. Latitude and longitude are saved automatically.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.tonalIcon(
                    onPressed: _locating ? null : _useCurrentLocation,
                    icon: _locating
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location, size: 18),
                    label: Text(_locating ? 'Locating…' : 'My location'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: SizedBox(
                  height: 330,
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: selected ?? _kabulCenter,
                      initialZoom: selected == null ? 11 : 17,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                      ),
                      onTap: (_, point) => _selectLocation(point),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: AppConfig.tileUrlTemplate,
                        userAgentPackageName: 'com.businessos.fieldpulse',
                        maxZoom: 19,
                      ),
                      if (selected != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: selected,
                              width: 50,
                              height: 58,
                              alignment: Alignment.topCenter,
                              child: const Icon(
                                Icons.location_on,
                                size: 50,
                                color: Colors.indigo,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _CoordinateCard(
                      label: 'Latitude',
                      value: selected?.latitude,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _CoordinateCard(
                      label: 'Longitude',
                      value: selected?.longitude,
                    ),
                  ),
                ],
              ),
              if (_locationMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  _locationMessage!,
                  style: TextStyle(
                    fontSize: 12,
                    color: selected == null
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(_saving ? 'Saving…' : 'Save customer'),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Customer creation remains offline-first. The location will sync with the customer when connectivity is available.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoordinateCard extends StatelessWidget {
  const _CoordinateCard({required this.label, required this.value});

  final String label;
  final double? value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
            value?.toStringAsFixed(7) ?? 'Not selected',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFeatures: [FontFeature.tabularFigures()],
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
