import 'package:field_sales_mobile/l10n/localized_material.dart';
import 'package:provider/provider.dart';

import '../state/notification_controller.dart';
import 'fieldpulse_theme.dart';
import 'widgets/fieldpulse_ui.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotificationController>().refresh(silent: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<NotificationController>();

    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          if (controller.items.isEmpty)
            const FieldPulseEmptyState(
              icon: Icons.notifications_none_rounded,
              title: 'No notifications yet',
              message: 'Route alerts, supervisor messages and status updates will appear here.',
            ),
          for (final item in controller.items)
            FieldPulseGlassCard(
              padding: EdgeInsets.zero,
              onTap: () => controller.markRead(item),
              tint: item.unread ? FieldPulseTheme.blue : FieldPulseTheme.muted,
              child: ListTile(
                leading: FieldPulseIconBadge(
                  color: item.unread
                      ? FieldPulseTheme.blue
                      : FieldPulseTheme.muted,
                  icon: item.type == 'team.supervisor_nudge'
                      ? Icons.campaign_outlined
                      : item.type == 'route.missed_visits'
                      ? Icons.route_outlined
                      : Icons.notifications_outlined,
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        style: TextStyle(
                          fontWeight: item.unread
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (item.unread) const Badge(smallSize: 8),
                  ],
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(item.message),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
