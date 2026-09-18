import 'package:timezone/data/latest_10y.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/workday_window.dart';
import 'clock.dart';

/// Initializes the IANA timezone database exactly once.
///
/// Called from `main()` before the first frame so the (fast but non-trivial)
/// data parse never blocks the interaction thread, and lazily by the resolver
/// for tests.
void initializeTenantTimeZones() => TenantTimeResolver.ensureData();

/// Resolves company (tenant) wall-clock time from an IANA timezone.
///
/// Automatic Start/End must follow the configured tenant timezone, NOT the
/// device timezone. An invalid or missing timezone yields null so callers can
/// surface a safe waiting state instead of silently evaluating in the device
/// zone. DST transitions are delegated to the IANA database shipped with the
/// `timezone` package — no custom offset math.
class TenantTimeResolver {
  const TenantTimeResolver({this.clock = const Clock()});

  final Clock clock;

  static bool _dataInitialized = false;

  /// Loads/parses the IANA database once (idempotent).
  static void ensureData() {
    if (!_dataInitialized) {
      tz_data.initializeTimeZones();
      _dataInitialized = true;
    }
  }

  /// The resolved IANA location, or null when [timezone] is missing/invalid.
  tz.Location? locationFor(String? timezone) {
    final name = timezone?.trim();
    if (name == null || name.isEmpty) {
      return null;
    }
    ensureData();
    try {
      return tz.getLocation(name);
    } catch (_) {
      // Common alias that PHP's timezone_identifiers_list() also accepts.
      if (name.toUpperCase() == 'UTC') {
        try {
          return tz.getLocation('Etc/UTC');
        } catch (_) {
          return null;
        }
      }
      return null;
    }
  }

  bool isValidTimezone(String? timezone) => locationFor(timezone) != null;

  /// "Now" expressed as tenant-local wall-clock time, or null when the
  /// timezone is missing/invalid.
  DateTime? nowIn(String? timezone) {
    final location = locationFor(timezone);
    if (location == null) {
      return null;
    }
    return tz.TZDateTime.from(clock.now(), location);
  }

  /// Converts an arbitrary instant into tenant-local wall-clock time, or null
  /// when the timezone is missing/invalid.
  DateTime? atIn(String? timezone, DateTime instant) {
    final location = locationFor(timezone);
    if (location == null) {
      return null;
    }
    return tz.TZDateTime.from(instant, location);
  }

  /// Delay until the next work-window boundary in the TENANT timezone.
  ///
  /// The nearest future start/end boundary wins (required for overnight
  /// windows, where tomorrow's end can be nearer than tomorrow's start).
  /// Returns null when the timezone is missing/invalid.
  Duration? nextBoundaryDelay(WorkdayWindow window, String? timezone) {
    final location = locationFor(timezone);
    if (location == null) {
      return null;
    }
    final now = tz.TZDateTime.from(clock.now(), location);

    tz.TZDateTime boundary(int dayOffset, int minutes) => tz.TZDateTime(
      location,
      now.year,
      now.month,
      now.day + dayOffset,
      minutes ~/ 60,
      minutes % 60,
    );

    final boundaries = <tz.TZDateTime>[
      boundary(0, window.startMinutes),
      boundary(0, window.endMinutes),
      boundary(1, window.startMinutes),
      boundary(1, window.endMinutes),
    ];

    // A small epsilon guarantees the evaluation runs just after the boundary.
    const epsilon = Duration(seconds: 1);
    Duration? nearest;
    for (final candidate in boundaries) {
      if (!candidate.isAfter(now)) {
        continue;
      }
      final delay = candidate.toUtc().difference(now.toUtc()) + epsilon;
      if (nearest == null || delay < nearest) {
        nearest = delay;
      }
    }
    return nearest;
  }
}
