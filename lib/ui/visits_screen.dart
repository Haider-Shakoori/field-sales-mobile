import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/visits/visit_map_data.dart';
import '../state/attendance_controller.dart';
import '../state/master_data_controller.dart';
import '../state/visit_controller.dart';
import 'collection_create_screen.dart';
import 'order_create_screen.dart';
import 'return_create_screen.dart';
import 'visit_forms_screen.dart';
import 'sync_refresh.dart';
import 'visits_map_view.dart';

class VisitsScreen extends StatefulWidget {
  const VisitsScreen({super.key});

  @override
  State<VisitsScreen> createState() => _VisitsScreenState();
}

class _VisitsScreenState extends State<VisitsScreen> {
  bool _showMap = false;

  static const outcomes = <String, String>{
    'order_placed': 'Order placed',
    'collection_made': 'Collection made',
    'complaint_received': 'Complaint received',
    'no_stock_needed': 'No stock needed',
    'shop_closed': 'Shop closed',
    'customer_unavailable': 'Customer unavailable',
  };

  Future<void> _startVisit(BuildContext context) async {
    final attendance = context.read<AttendanceController>();
    final visits = context.read<VisitController>();

    if (!attendance.working) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Start your work day before checking in.'),
        ),
      );
      return;
    }

    if (visits.hasActiveVisit) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Check out of the active visit first.')),
      );
      return;
    }

    final customers = context.read<MasterDataController>().customers;
    if (customers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No customers are available offline yet.'),
        ),
      );
      return;
    }

    final customer = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          itemCount: customers.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, index) {
            final row = customers[index];
            return ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: Text((row['name'] ?? 'Customer').toString()),
              subtitle: Text(
                [row['code'], row['address']]
                    .where(
                      (value) =>
                          value != null && value.toString().trim().isNotEmpty,
                    )
                    .join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => Navigator.pop(sheetContext, row),
            );
          },
        ),
      ),
    );

    if (customer != null && context.mounted) {
      await visits.checkIn(customer);
    }
  }

  Future<void> _checkOut(
    BuildContext context,
    Map<String, dynamic> visit,
  ) async {
    var outcome = outcomes.keys.first;
    final notes = TextEditingController();

    final save =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, setState) => AlertDialog(
              title: Text("Check out · ${visit['customer_name']}"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: outcome,
                      decoration: const InputDecoration(labelText: 'Outcome'),
                      items: outcomes.entries
                          .map(
                            (entry) => DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) setState(() => outcome = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notes,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Notes',
                        alignLabelWithHint: true,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Check out'),
                ),
              ],
            ),
          ),
        ) ??
        false;

    if (save && context.mounted) {
      await context.read<VisitController>().checkOut(
        visit,
        outcome: outcome,
        notes: notes.text,
      );
    }
  }

  Future<void> _createOrderFromVisit(
    BuildContext context,
    Map<String, dynamic> visit,
  ) async {
    final master = context.read<MasterDataController>();
    final customerId = visit['customer_uuid']?.toString();

    if (customerId == null || customerId.isEmpty || master.products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Customer or product data is not available offline yet.',
          ),
        ),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OrderCreateScreen(
          customers: master.customers,
          products: master.products,
          initialCustomerId: customerId,
          visitUuid: visit['offline_uuid']?.toString(),
        ),
      ),
    );
  }

  Future<void> _createCollectionFromVisit(
    BuildContext context,
    Map<String, dynamic> visit,
  ) async {
    final master = context.read<MasterDataController>();
    final customerId = visit['customer_uuid']?.toString();

    if (customerId == null || customerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Customer data is not available offline yet.'),
        ),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CollectionCreateScreen(
          customers: master.customers,
          initialCustomerId: customerId,
          visitUuid: visit['offline_uuid']?.toString(),
        ),
      ),
    );
  }

  Future<void> _createReturnFromVisit(
    BuildContext context,
    Map<String, dynamic> visit,
  ) async {
    final master = context.read<MasterDataController>();
    final customerId = visit['customer_uuid']?.toString();

    if (customerId == null || customerId.isEmpty || master.products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Customer or product data is not available offline yet.',
          ),
        ),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReturnCreateScreen(
          initialCustomerId: customerId,
          visitUuid: visit['offline_uuid']?.toString(),
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, VisitController state) =>
      state.visits.isEmpty
      ? ListView(
          padding: const EdgeInsets.all(20),
          children: const [
            SizedBox(height: 150),
            Icon(Icons.location_on_outlined, size: 52),
            SizedBox(height: 12),
            Center(child: Text('No customer visits recorded yet.')),
            SizedBox(height: 6),
            Center(
              child: Text(
                'Check-ins are stored locally first and can sync later.',
                textAlign: TextAlign.center,
              ),
            ),
          ],
        )
      : ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: state.visits.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, index) {
            final visit = state.visits[index];
            final active = visit['status'] == 'active';
            final planned = visit['is_planned'];
            final within = visit['checkin_within_geofence'];
            final syncStatus = visit['sync_status']?.toString() ?? '';

            String geofence;
            if (within == 1) {
              geofence = 'Inside geofence';
            } else if (within == 0) {
              geofence = 'Outside geofence';
            } else {
              geofence = 'Geofence pending sync';
            }

            String type;
            if (planned == 1) {
              type = 'Planned';
            } else if (planned == 0) {
              type = 'Unplanned';
            } else {
              type = 'Plan status pending';
            }

            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            visit['customer_name']?.toString() ?? 'Customer',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        Chip(label: Text(active ? 'Active' : 'Completed')),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text('$type · $geofence'),
                    const SizedBox(height: 4),
                    Text(
                      "Check-in: ${visit['checked_in_at'] ?? '—'}",
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    if (!active && visit['outcome'] != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        "Outcome: ${outcomes[visit['outcome']] ?? visit['outcome']}",
                      ),
                    ],
                    if (syncStatus != 'synced') ...[
                      const SizedBox(height: 6),
                      Text(
                        'Sync: $syncStatus',
                        style: TextStyle(color: Colors.orange.shade700),
                      ),
                    ],
                    if (visit['last_error'] != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        visit['last_error'].toString(),
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: state.busy
                              ? null
                              : () => state.capturePhoto(visit),
                          icon: const Icon(Icons.camera_alt_outlined),
                          label: const Text('Photo'),
                        ),
                        OutlinedButton.icon(
                          onPressed: state.busy
                              ? null
                              : () => _createOrderFromVisit(context, visit),
                          icon: const Icon(Icons.add_shopping_cart),
                          label: const Text('Order'),
                        ),
                        OutlinedButton.icon(
                          onPressed: state.busy
                              ? null
                              : () =>
                                    _createCollectionFromVisit(context, visit),
                          icon: const Icon(Icons.payments_outlined),
                          label: const Text('Collect'),
                        ),
                        if (active)
                          OutlinedButton.icon(
                            onPressed: state.busy
                                ? null
                                : () => _createReturnFromVisit(context, visit),
                            icon: const Icon(Icons.assignment_return_outlined),
                            label: const Text('Return'),
                          ),
                        if (active)
                          OutlinedButton.icon(
                            onPressed: state.busy
                                ? null
                                : () async {
                                    await Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            VisitFormsScreen(visit: visit),
                                      ),
                                    );
                                    if (context.mounted) {
                                      await state.reloadLocal();
                                    }
                                  },
                            icon: const Icon(Icons.fact_check_outlined),
                            label: const Text('Forms'),
                          ),
                        if (active)
                          FilledButton.icon(
                            onPressed: state.busy
                                ? null
                                : () => _checkOut(context, visit),
                            icon: const Icon(Icons.logout),
                            label: const Text('Check out'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );

  Widget _buildMap(BuildContext context, VisitController state) {
    final master = context.watch<MasterDataController>();
    final customers = buildMapCustomers(
      customers: master.customers,
      routes: master.routes,
      routeCustomers: master.routeCustomers,
    );

    if (customers.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          SizedBox(height: 120),
          Icon(Icons.map_outlined, size: 52),
          SizedBox(height: 12),
          Center(child: Text('No customers with map coordinates yet.')),
          SizedBox(height: 6),
          Center(
            child: Text(
              'Sync master data or add coordinates to customers to see them on the map.',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
    }

    final visited = <String>{};
    String? activeId;

    for (final visit in state.visits) {
      final id = visit['customer_uuid']?.toString();
      if (id == null || id.isEmpty) {
        continue;
      }

      if (visit['status'] == 'active') {
        activeId = id;
      } else {
        visited.add(id);
      }
    }

    return VisitsMapView(
      customers: customers,
      visitedCustomerIds: visited,
      activeCustomerId: activeId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<VisitController>();

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.list_alt_outlined),
                  label: Text('List'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.map_outlined),
                  label: Text('Map'),
                ),
              ],
              selected: {_showMap},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  setState(() => _showMap = selection.first),
            ),
          ),
          Expanded(
            child: _showMap
                ? _buildMap(context, state)
                : RefreshIndicator(
                    onRefresh: () =>
                        syncAndReload(context, triggerSource: 'pull:visits'),
                    child: _buildList(context, state),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: state.busy ? null : () => _startVisit(context),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Check in'),
      ),
    );
  }
}
