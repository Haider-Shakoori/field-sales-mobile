import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/notification_controller.dart';

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
        padding: const EdgeInsets.all(16),
        children: [
          if (controller.items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 80),
              child: Column(
                children: [
                  Icon(Icons.notifications_none, size: 48),
                  SizedBox(height: 12),
                  Text('No notifications yet'),
                  SizedBox(height: 6),
                  Text(
                    'Route alerts, supervisor messages and status updates will appear here.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          for (final item in controller.items)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: CircleAvatar(
                  child: Icon(
                    item.type == 'team.supervisor_nudge'
                        ? Icons.campaign_outlined
                        : item.type == 'route.missed_visits'
                        ? Icons.route_outlined
                        : Icons.notifications_outlined,
                  ),
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
                    if (item.unread)
                      const Badge(smallSize: 8),
                  ],
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(item.message),
                ),
                onTap: () => controller.markRead(item),
              ),
            ),
        ],
      ),
    );
  }
}
