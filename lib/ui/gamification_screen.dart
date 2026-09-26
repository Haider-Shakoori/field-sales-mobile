import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/gamification/gamification_repository.dart';

class GamificationScreen extends StatefulWidget {
  const GamificationScreen({super.key});

  @override
  State<GamificationScreen> createState() => _GamificationScreenState();
}

class _GamificationScreenState extends State<GamificationScreen> {
  Map<String, dynamic>? data;
  Object? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await context.read<GamificationRepository>().load();
      if (mounted) setState(() => data = value);
    } catch (e) {
      if (mounted) setState(() => error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Center(child: Text('Could not load team recognition: $error'));
    }
    if (data == null) return const Center(child: CircularProgressIndicator());
    if (data!['enabled'] != true) {
      return const Center(child: Text('Gamification is not enabled for this organization.'));
    }

    final me = data!['me'] is Map ? Map<String, dynamic>.from(data!['me']) : null;
    final leaderboard = (data!['leaderboard'] as List? ?? const []);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (me != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${me['level']}', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text('${me['points']} points · Rank #${me['rank']}'),
                    const SizedBox(height: 8),
                    Text(
                      (me['achievements'] as List? ?? const []).isEmpty
                          ? 'Complete verified field outcomes to unlock achievements.'
                          : (me['achievements'] as List).join(' · '),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text('30-day leaderboard', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final raw in leaderboard)
            Builder(builder: (_) {
              final row = Map<String, dynamic>.from(raw as Map);
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(child: Text('#${row['rank']}')),
                  title: Text('${row['salesman_name']}'),
                  subtitle: Text('${row['level']} · ${row['active_days']} active day(s)'),
                  trailing: Text('${row['points']} pts'),
                ),
              );
            }),
        ],
      ),
    );
  }
}
