import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/location/location_permission_service.dart';
import '../../core/models/attendance.dart';
import '../../l10n/app_l10n.dart';
import 'attendance_controller.dart';
import 'attendance_history_screen.dart';

/// Dashboard attendance panel: Start Day when idle, live tracking status while
/// working, completed summary after End Day.
class AttendanceCard extends StatelessWidget {
  const AttendanceCard({super.key});

  @override
  Widget build(BuildContext context) {
    final attendance = context.watch<AttendanceController>();

    if (attendance.restoring) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final session = attendance.activeSession;
    if (session != null) {
      return _ActiveSessionCard(session: session);
    }
    return _StartDayCard(completed: attendance.completedToday);
  }
}

// ---------------------------------------------------------------------------
// Idle / completed state
// ---------------------------------------------------------------------------

class _StartDayCard extends StatelessWidget {
  const _StartDayCard({this.completed});

  final LocalWorkSession? completed;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AttendanceController>();
    if (controller.automaticMode) {
      return _AutomaticStartCard(completed: completed, controller: controller);
    }
    return _ManualStartCard(completed: completed);
  }
}

class _ManualStartCard extends StatelessWidget {
  const _ManualStartCard({this.completed});

  final LocalWorkSession? completed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.today_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  completed == null ? l10n.dayNotStarted : l10n.dayCompleted,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                _historyButton(context),
              ],
            ),
            if (completed != null) ...[
              const SizedBox(height: 4),
              Text(
                '${formatTime(completed!.startTime)} – '
                '${formatTime(completed!.endTime)}  ·  '
                '${formatDuration(completed!.duration ?? Duration.zero)}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ] else ...[
              const SizedBox(height: 4),
              Text(
                l10n.startYourDay,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (completed == null) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('startDayButton'),
                  onPressed: () => _startDayFlow(context),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(l10n.startDay),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Widget _historyButton(BuildContext context) => IconButton(
  tooltip: AppL10n.of(context).attendanceHistory,
  icon: const Icon(Icons.history),
  onPressed: () => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const AttendanceHistoryScreen()),
  ),
);

/// Automatic mode dashboard states. The work session itself is created by the
/// exact same Start Day flow; this card only communicates/advances policy.
class _AutomaticStartCard extends StatelessWidget {
  const _AutomaticStartCard({this.completed, required this.controller});

  final LocalWorkSession? completed;
  final AttendanceController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    final state = controller.automaticState;
    final completedState = state == AutomaticPolicyState.completedToday;
    final outside =
        state == AutomaticPolicyState.outsideSchedule ||
        state == AutomaticPolicyState.completedToday;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  completedState
                      ? Icons.check_circle_outline
                      : (outside ? Icons.event_busy : Icons.schedule),
                  color: scheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  completedState
                      ? l10n.dayCompleted
                      : (outside
                            ? l10n.workDayNotActive
                            : l10n.automaticWorkDay),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                _historyButton(context),
              ],
            ),
            const SizedBox(height: 6),
            ..._body(context, l10n, state),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(
    BuildContext context,
    AppL10n l10n,
    AutomaticPolicyState state,
  ) {
    switch (state) {
      case AutomaticPolicyState.waitingForSchedule:
        return [
          Text(
            l10n.startsAt(controller.workdayStartLabel ?? ''),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ];
      case AutomaticPolicyState.outsideSchedule:
      case AutomaticPolicyState.completedToday:
        final summary = completed ?? controller.completedToday;
        return [
          Text(
            summary == null
                ? l10n.scheduleWindow(
                    controller.workdayStartLabel ?? '',
                    controller.workdayEndLabel ?? '',
                  )
                : '${formatTime(summary.startTime)} – '
                      '${formatTime(summary.endTime)}  ·  '
                      '${formatDuration(summary.duration ?? Duration.zero)}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ];
      case AutomaticPolicyState.waitingForPrivacy:
        return [
          Text(
            l10n.automaticTrackingWaiting,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.reviewTrackingPolicyHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          _actionButton(
            key: const Key('reviewTrackingPolicyButton'),
            icon: Icons.privacy_tip_outlined,
            label: l10n.reviewTrackingPolicy,
            onPressed: () => _reviewTrackingPolicy(context),
          ),
        ];
      case AutomaticPolicyState.waitingForPermission:
        return [
          Text(
            l10n.automaticTrackingWaiting,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            l10n.locationPermissionRequired,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          _actionButton(
            key: const Key('grantPermissionButton'),
            icon: Icons.my_location,
            label: l10n.grantLocationPermission,
            onPressed: () => _startDayFlow(context),
          ),
        ];
      case AutomaticPolicyState.waitingForServices:
        return [
          Text(
            l10n.automaticTrackingWaiting,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            l10n.locationServicesDisabled,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          _actionButton(
            key: const Key('openLocationSettingsButton'),
            icon: Icons.location_off_outlined,
            label: l10n.openLocationSettings,
            onPressed: () => unawaited(controller.openLocationSettings()),
          ),
        ];
      case AutomaticPolicyState.waitingForLocation:
        return [
          Text(
            l10n.automaticTrackingWaiting,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            l10n.automaticWaitingForLocation,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          _actionButton(
            key: const Key('retryAutomaticButton'),
            icon: Icons.refresh,
            label: l10n.retry,
            onPressed: () => unawaited(controller.retryAutomaticStart()),
          ),
        ];
      case AutomaticPolicyState.missingTimezone:
        return [
          Text(
            l10n.automaticTrackingWaiting,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            l10n.timezoneUnavailable,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ];
      case AutomaticPolicyState.gpsDisabled:
        return [
          Text(
            l10n.gpsDisabledByPolicy,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('startDayButton'),
              onPressed: () => _startDayFlow(context),
              icon: const Icon(Icons.play_arrow),
              label: Text(l10n.startDay),
            ),
          ),
        ];
      case AutomaticPolicyState.starting:
        return [
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          Text(
            l10n.automaticTrackingWaiting,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ];
      case AutomaticPolicyState.failed:
        return [
          Text(
            l10n.automaticTrackingWaiting,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          _actionButton(
            key: const Key('retryAutomaticButton'),
            icon: Icons.refresh,
            label: l10n.retry,
            onPressed: () => unawaited(controller.retryAutomaticStart()),
          ),
        ];
      case AutomaticPolicyState.notSignedIn:
      case AutomaticPolicyState.manual:
      case AutomaticPolicyState.active:
        return [Text(l10n.startYourDay)];
    }
  }

  Widget _actionButton({
    required Key key,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) => SizedBox(
    width: double.infinity,
    child: FilledButton.icon(
      key: key,
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
    ),
  );
}

Future<void> _reviewTrackingPolicy(BuildContext context) async {
  final controller = context.read<AttendanceController>();
  final agreed = await showGpsPrivacyDialog(context);
  if (agreed != true) {
    return;
  }
  await controller.acknowledgePrivacy();
  await controller.retryAutomaticStart();
}

Future<void> _startDayFlow(BuildContext context) async {
  final controller = context.read<AttendanceController>();
  var result = await controller.startDay();

  if (result.outcome == StartDayOutcome.needsPrivacyAck) {
    if (!context.mounted) {
      return;
    }
    final agreed = await showGpsPrivacyDialog(context);
    if (agreed != true) {
      return;
    }
    result = await controller.startDay(privacyAlreadyAcknowledged: true);
  }

  if (!context.mounted) {
    return;
  }
  await _presentStartResult(context, result);
}

Future<void> _presentStartResult(
  BuildContext context,
  StartDayResult result,
) async {
  final l10n = AppL10n.of(context);
  final controller = context.read<AttendanceController>();
  final messenger = ScaffoldMessenger.of(context);

  switch (result.outcome) {
    case StartDayOutcome.started:
      if (!result.trackingStarted && result.gpsTrackingEnabled) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.trackingStartFailed),
            action: SnackBarAction(
              label: l10n.retry,
              onPressed: () => unawaited(controller.resumeTracking()),
            ),
          ),
        );
      } else if (!result.gpsTrackingEnabled) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.gpsDisabledByPolicy)),
        );
      }
      if (result.backgroundAccess == BackgroundLocationAccess.needsSettings ||
          result.backgroundAccess == BackgroundLocationAccess.denied) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(l10n.backgroundLocationTitle),
            content: Text(l10n.backgroundLocationBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(l10n.ok),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  unawaited(controller.openAppSettings());
                },
                child: Text(l10n.openSettings),
              ),
            ],
          ),
        );
      }
      if (!result.notificationPermissionGranted) {
        if (!context.mounted) {
          return;
        }
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(l10n.notificationPermissionTitle),
            content: Text(l10n.notificationPermissionBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(l10n.ok),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  unawaited(controller.openAppSettings());
                },
                child: Text(l10n.openSettings),
              ),
            ],
          ),
        );
      }
    case StartDayOutcome.servicesDisabled:
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.servicesDisabledTitle),
          content: Text(l10n.servicesDisabledBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                unawaited(controller.openLocationSettings());
              },
              child: Text(l10n.openLocationSettings),
            ),
          ],
        ),
      );
    case StartDayOutcome.permissionDenied:
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.permissionDeniedTitle),
          content: Text(l10n.permissionDeniedBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                unawaited(
                  controller.startDay(privacyAlreadyAcknowledged: true),
                );
              },
              child: Text(l10n.retry),
            ),
          ],
        ),
      );
    case StartDayOutcome.permissionPermanentlyDenied:
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.permissionDeniedTitle),
          content: Text(l10n.permissionPermanentlyDeniedBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                unawaited(controller.openAppSettings());
              },
              child: Text(l10n.openSettings),
            ),
          ],
        ),
      );
    case StartDayOutcome.locationUnavailable:
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.locationUnavailableTitle),
          content: Text(l10n.locationUnavailableBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                unawaited(
                  controller.startDay(privacyAlreadyAcknowledged: true),
                );
              },
              child: Text(l10n.retry),
            ),
          ],
        ),
      );
    case StartDayOutcome.alreadyActive:
      await controller.refreshPendingGpsCount();
    case StartDayOutcome.alreadyCompletedToday:
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.sessionAlreadyCompletedToday)),
      );
    case StartDayOutcome.failed:
      messenger.showSnackBar(
        SnackBar(content: Text(result.message ?? l10n.error)),
      );
    case StartDayOutcome.needsPrivacyAck:
      break;
  }
}

/// Mandatory GPS tracking disclosure shown before the first tracked Start Day.
Future<bool?> showGpsPrivacyDialog(BuildContext context) {
  final l10n = AppL10n.of(context);
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.gpsPrivacyTitle),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.gpsPrivacyIntro),
            const SizedBox(height: 12),
            _Bullet(text: l10n.gpsPrivacyBullet1),
            _Bullet(text: l10n.gpsPrivacyBullet2),
            _Bullet(text: l10n.gpsPrivacyBullet3),
            _Bullet(text: l10n.gpsPrivacyBullet4),
            _Bullet(text: l10n.gpsPrivacyBullet5),
            _Bullet(text: l10n.gpsPrivacyBullet6),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.gpsPrivacyDecline),
        ),
        FilledButton(
          key: const Key('gpsPrivacyAgree'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.gpsPrivacyAgree),
        ),
      ],
    ),
  );
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  '),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Active session state
// ---------------------------------------------------------------------------

class _ActiveSessionCard extends StatefulWidget {
  const _ActiveSessionCard({required this.session});

  final LocalWorkSession session;

  @override
  State<_ActiveSessionCard> createState() => _ActiveSessionCardState();
}

class _ActiveSessionCardState extends State<_ActiveSessionCard> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    final attendance = context.watch<AttendanceController>();
    final active = attendance.isTracking;
    final elapsed = DateTime.now().difference(widget.session.startTime);
    final lastPoint = attendance.lastGpsPoint;

    return Card(
      color: active ? scheme.primaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.work_outline, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  l10n.working,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                _TrackingBadge(active: active),
                IconButton(
                  tooltip: l10n.attendanceHistory,
                  icon: const Icon(Icons.history),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AttendanceHistoryScreen(),
                    ),
                  ),
                ),
              ],
            ),
            if (widget.session.startSource ==
                WorkSessionStartSource.automatic) ...[
              const SizedBox(height: 4),
              Text(
                l10n.startedAutomatically,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (!active) ...[
              const SizedBox(height: 8),
              _TrackingPausedNotice(reason: attendance.pauseReason),
            ],
            const SizedBox(height: 12),
            _InfoRow(
              label: l10n.sessionStartedAt,
              value: formatTime(widget.session.startTime),
            ),
            _InfoRow(label: l10n.elapsedLabel, value: formatDuration(elapsed)),
            _InfoRow(
              label: l10n.gpsStatusLabel,
              value: lastPoint == null
                  ? l10n.waitingForFix
                  : l10n.lastCapturedAt(formatTime(lastPoint.recordedAt)),
            ),
            _InfoRow(
              label: l10n.pendingGpsPoints(attendance.pendingGpsCount),
              value: attendance.pendingGpsCount == 0 ? '✓' : '…',
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('endDayButton'),
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.errorContainer,
                  foregroundColor: scheme.onErrorContainer,
                ),
                onPressed: () => _endDayFlow(context),
                icon: const Icon(Icons.stop_circle_outlined),
                label: Text(l10n.endDay),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackingBadge extends StatelessWidget {
  const _TrackingBadge({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    final color = active ? scheme.primary : scheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            active ? Icons.gps_fixed : Icons.gps_off,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            active ? l10n.trackingActive : l10n.trackingPaused,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _TrackingPausedNotice extends StatelessWidget {
  const _TrackingPausedNotice({required this.reason});

  final TrackingPauseReason reason;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final scheme = Theme.of(context).colorScheme;

    final (message, action) = switch (reason) {
      TrackingPauseReason.authorizationLost => (
        l10n.authorizationLostBody,
        null,
      ),
      TrackingPauseReason.permissionMissing => (
        l10n.trackingPermissionPaused,
        l10n.openSettings,
      ),
      TrackingPauseReason.servicesDisabled => (
        l10n.trackingServicesPaused,
        l10n.openLocationSettings,
      ),
      TrackingPauseReason.gpsDisabled => (l10n.gpsDisabledByPolicy, null),
      _ => (l10n.trackingStartFailed, l10n.resumeTracking),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: Theme.of(context).textTheme.bodySmall),
          if (action != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () {
                  final controller = context.read<AttendanceController>();
                  switch (reason) {
                    case TrackingPauseReason.permissionMissing:
                      unawaited(controller.openAppSettings());
                    case TrackingPauseReason.servicesDisabled:
                      unawaited(controller.openLocationSettings());
                    default:
                      unawaited(controller.resumeTracking());
                  }
                },
                child: Text(action),
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> _endDayFlow(BuildContext context) async {
  final l10n = AppL10n.of(context);
  final controller = context.read<AttendanceController>();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.endDayConfirmTitle),
      content: Text(l10n.endDayConfirmBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('endDayConfirm'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.endDay),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) {
    return;
  }

  final result = await controller.endDay();
  if (!context.mounted) {
    return;
  }
  final messenger = ScaffoldMessenger.of(context);
  switch (result.outcome) {
    case EndDayOutcome.ended:
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.usedFallback ? l10n.endDayFallbackNote : l10n.dayCompleted,
          ),
        ),
      );
    case EndDayOutcome.notActive:
      messenger.showSnackBar(SnackBar(content: Text(l10n.error)));
    case EndDayOutcome.failed:
      messenger.showSnackBar(
        SnackBar(content: Text(result.message ?? l10n.error)),
      );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Formatting helpers
// ---------------------------------------------------------------------------

String formatTime(DateTime? time) =>
    time == null ? '—' : DateFormat('HH:mm:ss').format(time.toLocal());

String formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$hours:$minutes:$seconds';
}
