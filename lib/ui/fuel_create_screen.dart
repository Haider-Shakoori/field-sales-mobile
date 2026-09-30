import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../state/attendance_controller.dart';
import '../state/expense_controller.dart';

class FuelCreateScreen extends StatefulWidget {
  const FuelCreateScreen({super.key});

  @override
  State<FuelCreateScreen> createState() => _FuelCreateScreenState();
}

class _FuelCreateScreenState extends State<FuelCreateScreen> {
  final _amount = TextEditingController();
  final _currency = TextEditingController(text: 'AFN');
  final _liters = TextEditingController();
  final _unitPrice = TextEditingController();
  final _odometer = TextEditingController();
  final _vehicle = TextEditingController();
  final _station = TextEditingController();
  final _reference = TextEditingController();
  final _notes = TextEditingController();

  String? _receiptPath;
  bool _fullTank = true;
  bool _saving = false;
  bool _seededVehicle = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seededVehicle) return;
    _seededVehicle = true;
    final active = context.read<AttendanceController>().session;
    final value = active?['vehicle_reference']?.toString().trim() ?? '';
    if (value.isNotEmpty) _vehicle.text = value;
  }

  @override
  void dispose() {
    for (final controller in [
      _amount,
      _currency,
      _liters,
      _unitPrice,
      _odometer,
      _vehicle,
      _station,
      _reference,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickReceipt(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 82,
      maxWidth: 1800,
    );
    if (picked == null) return;

    final root = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(root.path, 'fuel_receipts'));
    await dir.create(recursive: true);
    final extension = p.extension(picked.path).isEmpty
        ? '.jpg'
        : p.extension(picked.path);
    final target = p.join(
      dir.path,
      DateTime.now().toUtc().microsecondsSinceEpoch.toString() + extension,
    );
    await File(picked.path).copy(target);
    if (mounted) setState(() => _receiptPath = target);
  }

  double? _requiredNumber(TextEditingController controller, String label) {
    final value = double.tryParse(controller.text.trim());
    if (value == null || value <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Enter a valid $label.')));
      return null;
    }
    return value;
  }

  Future<void> _save() async {
    final amount = _requiredNumber(_amount, 'amount');
    final liters = _requiredNumber(_liters, 'fuel quantity');
    final odometer = double.tryParse(_odometer.text.trim());
    if (amount == null || liters == null) return;
    if (odometer == null || odometer < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid odometer reading.')),
      );
      return;
    }
    if (_vehicle.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vehicle / plate is required.')),
      );
      return;
    }
    if (_station.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fuel station is required.')),
      );
      return;
    }
    if (_receiptPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Take or attach a receipt photo.')),
      );
      return;
    }

    final unitPrice = _unitPrice.text.trim().isEmpty
        ? null
        : double.tryParse(_unitPrice.text.trim());
    if (_unitPrice.text.trim().isNotEmpty &&
        (unitPrice == null || unitPrice <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid unit price.')),
      );
      return;
    }

    setState(() => _saving = true);
    final controller = context.read<ExpenseController>();
    await controller.create(
      category: 'fuel',
      currency: _currency.text,
      amount: amount,
      fuelLiters: liters,
      fuelUnitPrice: unitPrice,
      odometerKm: odometer,
      vehicleReference: _vehicle.text,
      fullTank: _fullTank,
      receiptLocalPath: _receiptPath,
      merchant: _station.text,
      referenceNumber: _reference.text,
      notes: _notes.text,
    );

    if (!mounted) return;
    setState(() => _saving = false);
    if (controller.message == 'Expense saved locally.') {
      Navigator.pop(context);
    } else if (controller.message != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(controller.message!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add fuel entry')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _vehicle,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Vehicle / plate *',
              helperText: 'Prefilled from the active shift when available.',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _station,
            decoration: const InputDecoration(labelText: 'Fuel station *'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _liters,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Liters *'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _odometer,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Odometer km *'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Total amount *',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 90,
                child: TextField(
                  controller: _currency,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 3,
                  decoration: const InputDecoration(
                    labelText: 'Currency',
                    counterText: '',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _unitPrice,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Price per liter (optional)',
              helperText:
                  'Derived automatically from amount ÷ liters if blank.',
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Filled to full tank'),
            subtitle: const Text(
              'Full-tank entries are used for vehicle km/L calculations.',
            ),
            value: _fullTank,
            onChanged: (value) => setState(() => _fullTank = value),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Receipt evidence *',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _receiptPath == null
                        ? 'No receipt attached.'
                        : 'Receipt attached and stored offline.',
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _pickReceipt(ImageSource.camera),
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: const Text('Camera'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _pickReceipt(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Gallery'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reference,
            decoration: const InputDecoration(
              labelText: 'Receipt / reference number (optional)',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          const Card(
            child: ListTile(
              leading: Icon(Icons.location_on_outlined),
              title: Text('GPS captured automatically'),
              subtitle: Text(
                'The entry, receipt and GPS evidence are saved offline first and sync when internet returns.',
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.local_gas_station_outlined),
            label: Text(_saving ? 'Saving…' : 'Save fuel entry'),
          ),
        ],
      ),
    );
  }
}
