import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../state/attendance_controller.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final db = context.read<AttendanceController>().db.db;
    final tenantId = context.read<AppState>().session?.tenantId;
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance history')),
      body: FutureBuilder(
        future: tenantId == null
            ? Future.value(<Map<String, Object?>>[])
            : db.query(
                'local_work_sessions',
                where: 'tenant_id=?',
                whereArgs: [tenantId],
                orderBy: 'date DESC',
              ),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snap.data!;
          if (rows.isEmpty) {
            return const Center(child: Text('No work days yet.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final r = rows[i];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Icon(
                      r['status'] == 'completed' ? Icons.check : Icons.work,
                    ),
                  ),
                  title: Text('${r['date']}'),
                  subtitle: Text(
                    '${r['start_time']}\n${r['end_time'] ?? 'In progress'}',
                  ),
                  isThreeLine: true,
                  trailing: Chip(label: Text('${r['sync_status']}')),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
