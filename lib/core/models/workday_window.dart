import 'attendance_tracking_settings.dart';

/// Pure evaluator for a company work window (local `HH:mm` boundaries).
///
/// Supports normal daytime windows (`08:00 → 17:00`) and overnight windows
/// (`20:00 → 04:00`). All comparisons are on the device-local wall clock; the
/// optional tenant timezone is not applied in this phase (documented in
/// [AttendanceTrackingSettings.timezone]).
class WorkdayWindow {
  const WorkdayWindow({required this.startMinutes, required this.endMinutes});

  /// Returns null when the boundaries are not valid `HH:mm` or form an empty
  /// window (start == end).
  static WorkdayWindow? parse(String start, String end) {
    final startMinutes = parseHhMm(start);
    final endMinutes = parseHhMm(end);
    if (startMinutes == null || endMinutes == null) {
      return null;
    }
    if (startMinutes == endMinutes) {
      return null;
    }
    return WorkdayWindow(startMinutes: startMinutes, endMinutes: endMinutes);
  }

  static WorkdayWindow? fromSettings(AttendanceTrackingSettings settings) =>
      parse(settings.workdayStartTime, settings.workdayEndTime);

  final int startMinutes;
  final int endMinutes;

  bool get isOvernight => endMinutes < startMinutes;

  String get startLabel => formatHhMm(startMinutes);
  String get endLabel => formatHhMm(endMinutes);

  static int _minutesOfDay(DateTime local) => local.hour * 60 + local.minute;

  /// True when [local] falls inside the window. Midnight is not an end
  /// boundary for overnight windows: `20:00 → 04:00` contains 23:30 and 03:30.
  bool contains(DateTime local) {
    final minutes = _minutesOfDay(local);
    if (!isOvernight) {
      return minutes >= startMinutes && minutes < endMinutes;
    }
    return minutes >= startMinutes || minutes < endMinutes;
  }

  /// True when the next window opening is still ahead (covers "before work"
  /// for daytime windows and the daytime gap of overnight windows).
  bool isBeforeStart(DateTime local) {
    final minutes = _minutesOfDay(local);
    if (!isOvernight) {
      return minutes < startMinutes;
    }
    return minutes >= endMinutes && minutes < startMinutes;
  }

  /// Delay until the next boundary (window start or window end), used for the
  /// single lightweight boundary timer. Boundary instants are computed for
  /// today and tomorrow local dates; the nearest future one wins (required for
  /// overnight windows, where tomorrow's end can be nearer than tomorrow's
  /// start).
  Duration? nextBoundaryDelay(DateTime local) {
    final boundaries = <DateTime>[
      _boundaryOn(local, startMinutes),
      _boundaryOn(local, endMinutes),
      _boundaryOn(local.add(const Duration(days: 1)), startMinutes),
      _boundaryOn(local.add(const Duration(days: 1)), endMinutes),
    ];
    // A small epsilon guarantees the evaluation runs just after the boundary.
    const epsilon = Duration(seconds: 1);
    Duration? nearest;
    for (final boundary in boundaries) {
      if (!boundary.isAfter(local)) {
        continue;
      }
      final delay = boundary.difference(local) + epsilon;
      if (nearest == null || delay < nearest) {
        nearest = delay;
      }
    }
    return nearest;
  }

  DateTime _boundaryOn(DateTime day, int minutes) =>
      DateTime(day.year, day.month, day.day).add(Duration(minutes: minutes));
}
