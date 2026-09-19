import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/master_data_controller.dart';

class RoutesScreen extends StatelessWidget {
  const RoutesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<MasterDataController>();
    final rows = [...state.routes]
      ..sort(
        (a, b) => (a['name'] ?? '').toString().compareTo(
          (b['name'] ?? '').toString(),
        ),
      );

    return RefreshIndicator(
      onRefresh: () => state.sync(),
      child: rows.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 180),
                Icon(Icons.route_outlined, size: 48),
                SizedBox(height: 12),
                Center(child: Text('No routes cached yet. Pull down to sync.')),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, index) {
                final route = rows[index];
                final weekdays = (route['weekdays'] as List? ?? const []).join(
                  ', ',
                );

                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.route),
                    title: Text(route['name']?.toString() ?? 'Route'),
                    subtitle: Text(
                      [
                            route['code'],
                            if (weekdays.isNotEmpty) weekdays,
                            route['is_active'] == false ? 'Inactive' : null,
                          ]
                          .where(
                            (value) =>
                                value != null &&
                                value.toString().trim().isNotEmpty,
                          )
                          .join(' · '),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
