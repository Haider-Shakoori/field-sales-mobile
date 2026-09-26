import '../../core/api/api_client.dart';

class MobileNotification {
  const MobileNotification({
    required this.id,
    required this.type,
    required this.priority,
    required this.title,
    required this.message,
    required this.createdAt,
    this.readAt,
  });

  final String id, type, priority, title, message, createdAt;
  final String? readAt;
  bool get unread => readAt == null;

  factory MobileNotification.fromJson(Map<String, dynamic> json) =>
      MobileNotification(
        id: '${json['id']}',
        type: '${json['type']}',
        priority: '${json['priority'] ?? 'normal'}',
        title: '${json['title']}',
        message: '${json['message']}',
        createdAt: '${json['created_at'] ?? ''}',
        readAt: json['read_at']?.toString(),
      );
}

class NotificationRepository {
  NotificationRepository(this.api);
  final ApiClient api;

  Future<List<MobileNotification>> list({bool unreadOnly = false}) async {
    final data = await api.get(
      'notifications',
      query: {'unread_only': unreadOnly ? 1 : 0, 'per_page': 100},
    );

    return (data as List? ?? const [])
        .whereType<Map>()
        .map((row) => MobileNotification.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<void> markRead(String id) => api.patch('notifications/$id/read');
}
