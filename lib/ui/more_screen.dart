import 'package:field_sales_mobile/l10n/localized_material.dart';

import 'appointments_screen.dart';
import 'language_selector.dart';

import 'package:provider/provider.dart';

import '../l10n/locale_controller.dart';
import '../state/app_state.dart';
import 'gamification_screen.dart';
import 'widgets/fieldpulse_ui.dart';
import 'notifications_screen.dart';
import 'salesman_account_screen.dart';
import 'collections_screen.dart';
import 'expenses_screen.dart';
import 'fuel_screen.dart';
import 'follow_ups_screen.dart';
import 'mileage_screen.dart';
import 'mobile_diagnostics_screen.dart';
import 'leads_screen.dart';
import 'products_screen.dart';
import 'routes_screen.dart';
import 'smart_route_screen.dart';
import 'stock_returns_screen.dart';
import 'sync_refresh.dart';
import 'sync_screen.dart';
import 'targets_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  void _open(BuildContext context, String title, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: screen,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AppLocaleController>();
    final app = context.watch<AppState>();

    final actions = <_MoreAction>[
      if (app.isSalesman)
        const _MoreAction(
          icon: Icons.account_circle_outlined,
          title: 'My Account',
          subtitle:
              'Referral customers, orders, collections and visit activity',
          screen: SalesmanAccountScreen(),
        ),
      const _MoreAction(
        icon: Icons.notifications_outlined,
        title: 'Notifications',
        subtitle: 'Route alerts, supervisor messages and updates',
        screen: NotificationsScreen(),
      ),
      if (app.gamificationEnabled)
        const _MoreAction(
          icon: Icons.emoji_events_outlined,
          title: 'Recognition',
          subtitle: 'Points, level, achievements and team leaderboard',
          screen: GamificationScreen(),
        ),
      const _MoreAction(
        icon: Icons.filter_alt_outlined,
        title: 'Leads & Pipeline',
        subtitle: 'Prospects, opportunity stages and conversion',
        screen: LeadsScreen(),
      ),
      const _MoreAction(
        icon: Icons.calendar_month_outlined,
        title: 'Calendar',
        subtitle: 'Appointments, reminders and offline schedule',
        screen: AppointmentsScreen(),
      ),
      const _MoreAction(
        icon: Icons.follow_the_signs_outlined,
        title: 'Follow-ups',
        subtitle: 'Assigned customer actions, due dates and completion',
        screen: FollowUpsScreen(),
      ),
      const _MoreAction(
        icon: Icons.payments_outlined,
        title: 'Collections',
        subtitle: 'Customer balances, receipts and payments',
        screen: CollectionsScreen(),
      ),
      const _MoreAction(
        icon: Icons.receipt_long_outlined,
        title: 'Expenses',
        subtitle: 'Offline claims and finance review status',
        screen: ExpensesScreen(),
      ),
      const _MoreAction(
        icon: Icons.local_gas_station_outlined,
        title: 'Fuel Management',
        subtitle: 'Vehicle refueling, odometer, GPS and receipt evidence',
        screen: FuelScreen(),
      ),
      const _MoreAction(
        icon: Icons.route_outlined,
        title: 'Mileage',
        subtitle: 'GPS distance, odometer variance and fuel efficiency',
        screen: MileageScreen(),
      ),
      const _MoreAction(
        icon: Icons.track_changes_outlined,
        title: 'Targets',
        subtitle: 'Current goals and authoritative progress',
        screen: TargetsScreen(),
      ),
      const _MoreAction(
        icon: Icons.alt_route_rounded,
        title: 'Smart Route',
        subtitle: "Today's optimized customer order, priorities and distance",
        screen: SmartRouteScreen(),
      ),
      const _MoreAction(
        icon: Icons.route_outlined,
        title: 'Routes',
        subtitle: 'Assigned routes and customer sequence',
        screen: RoutesScreen(),
      ),
      const _MoreAction(
        icon: Icons.local_shipping_outlined,
        title: 'Stock & Returns',
        subtitle: 'Van stock, damaged goods and customer returns',
        screen: StockReturnsScreen(),
      ),
      const _MoreAction(
        icon: Icons.inventory_2_outlined,
        title: 'Products',
        subtitle: 'Cached product catalog and pricing',
        screen: ProductsScreen(),
      ),
      const _MoreAction(
        icon: Icons.health_and_safety_outlined,
        title: 'Mobile Diagnostics',
        subtitle:
            'Battery, GPS, background tracking, permissions and sync health',
        screen: MobileDiagnosticsScreen(),
      ),
      const _MoreAction(
        icon: Icons.sync_outlined,
        title: 'Sync',
        subtitle: 'Review and upload pending offline work',
        screen: SyncScreen(),
      ),
    ];

    return RefreshIndicator(
      onRefresh: () => syncAndReload(context, triggerSource: 'pull:more'),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          const FieldPulseHeroCard(
            child: Row(
              children: [
                FieldPulseIconBadge(
                  icon: Icons.grid_view_rounded,
                  color: Color(0xFF7CC7FF),
                  size: 50,
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Field tools',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Sales, routes, collections, stock and device tools in one place.',
                        style: TextStyle(
                          color: Color(0xFFBBD0E8),
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const FieldPulseSectionHeader(
            title: 'Preferences',
            subtitle: 'Language and personal app settings',
          ),
          const SizedBox(height: 10),
          const FieldPulseGlassCard(
            padding: EdgeInsets.zero,
            child: LanguageSelectorButton(),
          ),
          const SizedBox(height: 8),
          const FieldPulseSectionHeader(
            title: 'Field tools',
            subtitle: 'Sales, routes, collections, stock and device tools in one place.',
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final oneColumn = constraints.maxWidth < 390;
              final width = oneColumn
                  ? constraints.maxWidth
                  : (constraints.maxWidth - 12) / 2;

              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final action in actions)
                    SizedBox(
                      width: width,
                      child: _MoreActionCard(
                        action: action,
                        onTap: () =>
                            _open(context, action.title, action.screen),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MoreAction {
  const _MoreAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.screen,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget screen;
}

class _MoreActionCard extends StatelessWidget {
  const _MoreActionCard({required this.action, required this.onTap});

  final _MoreAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => FieldPulseGlassCard(
    margin: EdgeInsets.zero,
    onTap: onTap,
    padding: const EdgeInsets.all(15),
    child: SizedBox(
      height: 116,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FieldPulseIconBadge(icon: action.icon, size: 42),
              const Spacer(),
              Icon(
                Icons.arrow_outward_rounded,
                size: 18,
                color: Theme.of(context).colorScheme.primary.withValues(alpha: .72),
              ),
            ],
          ),
          const Spacer(),
          Text(
            action.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w800, height: 1.15),
          ),
          const SizedBox(height: 4),
          Text(
            action.subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.25),
          ),
        ],
      ),
    ),
  );
}
