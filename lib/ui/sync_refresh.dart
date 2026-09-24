import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/appointment_controller.dart';
import '../state/call_activity_controller.dart';
import '../state/collection_controller.dart';
import '../state/expense_controller.dart';
import '../state/master_data_controller.dart';
import '../state/order_controller.dart';
import '../state/sync_controller.dart';
import '../state/target_controller.dart';
import '../state/visit_controller.dart';

Future<void> reloadAllLocal(BuildContext context) async {
  await context.read<MasterDataController>().reloadLocal();
  if (!context.mounted) return;
  await context.read<AppointmentController>().reloadLocal();
  if (!context.mounted) return;
  await context.read<VisitController>().reloadLocal();
  if (!context.mounted) return;
  await context.read<CallActivityController>().reloadLocal();
  if (!context.mounted) return;
  await context.read<OrderController>().reloadLocal();
  if (!context.mounted) return;
  await context.read<CollectionController>().reloadLocal();
  if (!context.mounted) return;
  await context.read<ExpenseController>().reloadLocal();
  if (!context.mounted) return;
  await context.read<TargetController>().reloadLocal();
  if (!context.mounted) return;
  await context.read<SyncController>().refreshHealth();
}

Future<void> syncAndReload(
  BuildContext context, {
  String triggerSource = 'pull_refresh',
}) async {
  await context.read<SyncController>().run(triggerSource: triggerSource);

  if (!context.mounted) return;

  await reloadAllLocal(context);
}
