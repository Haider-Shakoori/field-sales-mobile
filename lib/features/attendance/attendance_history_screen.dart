import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/attendance.dart';
import '../../core/sync/sync_status.dart';
import '../../l10n/app_l10n.dart';
import 'attendance_card.dart';
import 'attendance_controller.dart';

/// Lightweight local attendance history (SQLite only — no analytics).
class AttendanceHistoryScreen extends StatefulWidget {
  const AttendanceHistoryScreen({super.key});

  @override
  State<AttendanceHistoryScreen> createState() =>
      _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AttendanceController>().loadHistory();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final controller = context.watch<AttendanceController>();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.attendanceHistory),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => controller.loadHistory(),
          ),
        ],
      ),
      body: controller.historyLoading
          ? const Center(child: CircularProgressIndicator())
          : controller.history.isEmpty
          ? Center(child: Text(l10n.attendanceHistoryEmpty))
          : RefreshIndicator(
              onRefresh: () => controller.loadHistory(),
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: controller.history.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) =>
                    _SessionTile(session: controller.history[index]),
              ),
            ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session});

  final LocalWorkSession session;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    final active = session.status == WorkSessionStatus.active;

    return ListTile(
      leading: Icon(
        active ? Icons.play_circle_outline : Icons.check_circle_outline,
        color: active ? scheme.primary : scheme.outline,
      ),
      title: Text(session.date),
      subtitle: Text(
        '${formatTime(session.startTime)} – '
        '${formatTime(session.endTime)}\n'
        '${l10n.durationLabel}: '
        '${formatDuration(session.duration ?? Duration.zero)}',
      ),
      isThreeLine: true,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            active ? l10n.statusActive : l10n.statusCompleted,
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 4),
          Text(
            _syncLabel(l10n, session.syncStatus),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: session.syncStatus == SyncStatus.failed
                  ? scheme.error
                  : scheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  String _syncLabel(AppL10n l10n, SyncStatus status) => switch (status) {
    SyncStatus.synced => l10n.syncSynced,
    SyncStatus.failed => l10n.syncFailed,
    _ => l10n.syncPending,
  };
}
